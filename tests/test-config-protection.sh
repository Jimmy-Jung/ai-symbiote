#!/bin/bash
# Integration tests for config-protection.sh hook.
#
# Author: JunyoungJung
# Date: 2026-04-16
#
# Usage: bash tests/test-config-protection.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT_PATH="$PROJECT_ROOT/shared/hooks/scripts/config-protection.sh"

PASSED=0
FAILED=0
TOTAL=0

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  TOTAL=$((TOTAL + 1))
  if echo "$haystack" | grep -qF "$needle" 2>/dev/null; then
    PASSED=$((PASSED + 1))
    printf "${GREEN}  PASS${NC} %s\n" "$desc"
  else
    FAILED=$((FAILED + 1))
    printf "${RED}  FAIL${NC} %s\n    needle: %s\n    haystack: %s\n" "$desc" "$needle" "$haystack"
  fi
}

assert_not_contains() {
  local desc="$1" needle="$2" haystack="$3"
  TOTAL=$((TOTAL + 1))
  if ! echo "$haystack" | grep -qF "$needle" 2>/dev/null; then
    PASSED=$((PASSED + 1))
    printf "${GREEN}  PASS${NC} %s\n" "$desc"
  else
    FAILED=$((FAILED + 1))
    printf "${RED}  FAIL${NC} %s\n    should NOT contain: %s\n" "$desc" "$needle"
  fi
}

assert_file_contains() {
  local desc="$1" needle="$2" file_path="$3"
  TOTAL=$((TOTAL + 1))
  if grep -qF "$needle" "$file_path" 2>/dev/null; then
    PASSED=$((PASSED + 1))
    printf "${GREEN}  PASS${NC} %s\n" "$desc"
  else
    FAILED=$((FAILED + 1))
    printf "${RED}  FAIL${NC} %s\n    needle: %s\n    file: %s\n" "$desc" "$needle" "$file_path"
  fi
}

setup_env() {
  local tmp_dir
  tmp_dir=$(mktemp -d /tmp/config-protection-test-XXXXXX)
  mkdir -p "$tmp_dir"
  cat > "$tmp_dir/manifest.json" <<'EOF'
{
  "projectPath": "/tmp/test-project",
  "project": { "name": "demo", "type": "app", "languages": ["typescript"] },
  "stack": { "packageManager": "npm", "frameworks": ["react"] }
}
EOF
  echo "$tmp_dir"
}

teardown_env() { rm -rf "$1" 2>/dev/null; }

run_hook() {
  local state_dir="$1" input="$2"
  printf '%s' "$input" | \
    HARNESS_TEST_STATE_DIR="$state_dir" \
    bash "$SCRIPT_PATH" 2>/dev/null
}

# ============================================================
# Test 1: Block on .swiftlint.yml edit
# ============================================================
test_block_swiftlint() {
  printf "${YELLOW}Test 1: Block on .swiftlint.yml edit${NC}\n"
  local dir output
  dir=$(setup_env)

  output=$(run_hook "$dir" '{"tool_name":"Edit","tool_input":{"file_path":"/project/.swiftlint.yml","old_string":"a","new_string":"b"}}')

  assert_contains "blocks .swiftlint.yml" "Config Protection" "$output"
  assert_contains "message mentions file" ".swiftlint.yml" "$output"
  assert_contains "message mentions fix code" "Fix the code" "$output"
  assert_contains "output denies permission" '"continue":false' "$output"

  teardown_env "$dir"
}

# ============================================================
# Test 2: Block on .eslintrc.json edit
# ============================================================
test_block_eslintrc_json() {
  printf "${YELLOW}Test 2: Block on .eslintrc.json edit${NC}\n"
  local dir output
  dir=$(setup_env)

  output=$(run_hook "$dir" '{"tool_name":"Edit","tool_input":{"file_path":"/project/.eslintrc.json","old_string":"a","new_string":"b"}}')

  assert_contains "blocks .eslintrc.json" "Config Protection" "$output"
  assert_contains "output denies permission" '"continue":false' "$output"

  teardown_env "$dir"
}

# ============================================================
# Test 3: Allow on regular .swift file
# ============================================================
test_allow_swift() {
  printf "${YELLOW}Test 3: Allow on regular .swift file${NC}\n"
  local dir output
  dir=$(setup_env)

  output=$(run_hook "$dir" '{"tool_name":"Edit","tool_input":{"file_path":"/project/Sources/App.swift","old_string":"a","new_string":"b"}}')

  assert_contains "continues for .swift" '"continue":true' "$output"
  assert_not_contains "no block message" "Config Protection" "$output"

  teardown_env "$dir"
}

# ============================================================
# Test 4: Allow on .ts file
# ============================================================
test_allow_ts() {
  printf "${YELLOW}Test 4: Allow on .ts file${NC}\n"
  local dir output
  dir=$(setup_env)

  output=$(run_hook "$dir" '{"tool_name":"Edit","tool_input":{"file_path":"/project/src/index.ts","old_string":"a","new_string":"b"}}')

  assert_contains "continues for .ts" '"continue":true' "$output"
  assert_not_contains "no block message" "Config Protection" "$output"

  teardown_env "$dir"
}

# ============================================================
# Test 5: Override with SYMBIOTE_ALLOW_CONFIG_EDIT=1
# ============================================================
test_override_allows() {
  printf "${YELLOW}Test 5: Override with SYMBIOTE_ALLOW_CONFIG_EDIT=1${NC}\n"
  local dir output
  dir=$(setup_env)

  output=$(printf '%s' '{"tool_name":"Edit","tool_input":{"file_path":"/project/.swiftlint.yml","old_string":"a","new_string":"b"}}' | \
    HARNESS_TEST_STATE_DIR="$dir" \
    SYMBIOTE_ALLOW_CONFIG_EDIT=1 \
    bash "$SCRIPT_PATH" 2>/dev/null)

  assert_contains "override allows .swiftlint.yml" '"continue":true' "$output"
  assert_not_contains "no block message with override" "Config Protection" "$output"

  teardown_env "$dir"
}

# ============================================================
# Test 6: Custom protectedConfigs from manifest.json
# ============================================================
test_custom_protected_configs() {
  printf "${YELLOW}Test 6: Custom protectedConfigs from manifest.json${NC}\n"
  local dir output
  dir=$(setup_env)

  # Override manifest with custom protectedConfigs
  cat > "$dir/manifest.json" <<'EOF'
{
  "projectPath": "/tmp/test-project",
  "project": { "name": "demo", "type": "app", "languages": ["python"] },
  "security": { "protectedConfigs": "setup.cfg tox.ini mypy.ini" }
}
EOF

  # Custom config should be blocked
  output=$(run_hook "$dir" '{"tool_name":"Edit","tool_input":{"file_path":"/project/tox.ini","old_string":"a","new_string":"b"}}')
  assert_contains "blocks custom config tox.ini" "Config Protection" "$output"
  assert_contains "message mentions tox.ini" "tox.ini" "$output"

  # Default config should NOT be blocked (custom list replaces defaults)
  output=$(run_hook "$dir" '{"tool_name":"Edit","tool_input":{"file_path":"/project/.eslintrc.json","old_string":"a","new_string":"b"}}')
  # .eslintrc.json is NOT in the custom list, but wildcard match still applies for eslintrc*
  # Actually, the custom list replaces defaults AND the wildcard logic still runs
  # .eslintrc* wildcard catches this even with custom list
  assert_contains "eslintrc wildcard still active" "Config Protection" "$output"

  teardown_env "$dir"
}

# ============================================================
# Test 7: security-log.jsonl records blocked event
# ============================================================
test_security_log_records() {
  printf "${YELLOW}Test 7: security-log.jsonl records blocked event${NC}\n"
  local dir output
  dir=$(setup_env)

  output=$(run_hook "$dir" '{"tool_name":"Edit","tool_input":{"file_path":"/project/.prettierrc.json","old_string":"a","new_string":"b"}}')

  assert_contains "blocks .prettierrc.json" "Config Protection" "$output"
  assert_file_contains "security log has config_protection category" "config_protection" "$dir/security-log.jsonl"
  assert_file_contains "security log has blocked action" '"action":"blocked"' "$dir/security-log.jsonl"
  assert_file_contains "security log has file name" ".prettierrc.json" "$dir/security-log.jsonl"

  teardown_env "$dir"
}

# ============================================================
# Test 8: Empty file_path emits continue
# ============================================================
test_empty_file_path() {
  printf "${YELLOW}Test 8: Empty file_path emits continue${NC}\n"
  local dir output
  dir=$(setup_env)

  output=$(run_hook "$dir" '{"tool_name":"Edit","tool_input":{"old_string":"a","new_string":"b"}}')
  assert_contains "continues on missing file_path" '"continue":true' "$output"

  teardown_env "$dir"
}

# ============================================================
# Test 9: Malformed JSON emits continue
# ============================================================
test_malformed_json() {
  printf "${YELLOW}Test 9: Malformed JSON emits continue${NC}\n"
  local dir output
  dir=$(setup_env)

  output=$(run_hook "$dir" 'not valid json at all')
  assert_contains "continues on malformed JSON" '"continue":true' "$output"

  teardown_env "$dir"
}

# ============================================================
# Test 10: Wildcard match for .eslintrc.cjs variant
# ============================================================
test_eslintrc_wildcard() {
  printf "${YELLOW}Test 10: Wildcard match for .eslintrc.cjs${NC}\n"
  local dir output
  dir=$(setup_env)

  output=$(run_hook "$dir" '{"tool_name":"Edit","tool_input":{"file_path":"/project/.eslintrc.cjs","old_string":"a","new_string":"b"}}')
  assert_contains "blocks .eslintrc.cjs via wildcard" "Config Protection" "$output"

  teardown_env "$dir"
}

# ============================================================
# Test 11: biome.json is blocked
# ============================================================
test_block_biome() {
  printf "${YELLOW}Test 11: biome.json is blocked${NC}\n"
  local dir output
  dir=$(setup_env)

  output=$(run_hook "$dir" '{"tool_name":"Write","tool_input":{"file_path":"/project/biome.json","content":"{}"}}')
  assert_contains "blocks biome.json" "Config Protection" "$output"

  teardown_env "$dir"
}

# ============================================================
# Test 12: Cursor protocol output format
# ============================================================
test_cursor_protocol() {
  printf "${YELLOW}Test 12: Cursor protocol output format${NC}\n"
  local dir output
  dir=$(setup_env)

  output=$(printf '%s' '{"tool_name":"Edit","tool_input":{"file_path":"/project/.swiftlint.yml","old_string":"a","new_string":"b"}}' | \
    HARNESS_TEST_STATE_DIR="$dir" \
    CURSOR_PLUGIN_ROOT="/tmp/cursor-plugin" \
    bash "$SCRIPT_PATH" 2>/dev/null)

  assert_contains "cursor protocol has permission deny" '"permission":"deny"' "$output"
  assert_contains "cursor protocol has continue false" '"continue":false' "$output"
  assert_contains "cursor protocol has agent_message" '"agent_message"' "$output"

  teardown_env "$dir"
}

# ============================================================
printf "\n${YELLOW}=== ai-symbiote Config Protection Tests ===${NC}\n\n"

test_block_swiftlint
echo ""
test_block_eslintrc_json
echo ""
test_allow_swift
echo ""
test_allow_ts
echo ""
test_override_allows
echo ""
test_custom_protected_configs
echo ""
test_security_log_records
echo ""
test_empty_file_path
echo ""
test_malformed_json
echo ""
test_eslintrc_wildcard
echo ""
test_block_biome
echo ""
test_cursor_protocol

printf "\n${YELLOW}=== Results ===${NC}\n"
printf "Total: %d  Passed: ${GREEN}%d${NC}  Failed: ${RED}%d${NC}\n\n" "$TOTAL" "$PASSED" "$FAILED"

[ "$FAILED" -gt 0 ] && exit 1
exit 0
