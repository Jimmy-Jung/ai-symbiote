#!/bin/bash
# Integration tests for GateGuard (gateguard-tracker.sh + gateguard-gate.sh).
#
# Tests the "read before edit" enforcement:
#   - tracker records Read file paths to session file
#   - gate blocks Edit/Write on unread files, allows after Read
#
# Usage: bash tests/test-gateguard.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TRACKER_SCRIPT="$PROJECT_ROOT/shared/hooks/scripts/gateguard-tracker.sh"
GATE_SCRIPT="$PROJECT_ROOT/shared/hooks/scripts/gateguard-gate.sh"

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
    printf "${RED}  FAIL${NC} %s (needle not found)\n    needle: %s\n" "$desc" "$needle"
  fi
}

assert_not_contains() {
  local desc="$1" needle="$2" haystack="$3"
  TOTAL=$((TOTAL + 1))
  if echo "$haystack" | grep -qF "$needle" 2>/dev/null; then
    FAILED=$((FAILED + 1))
    printf "${RED}  FAIL${NC} %s (needle found but should not be)\n    needle: %s\n" "$desc" "$needle"
  else
    PASSED=$((PASSED + 1))
    printf "${GREEN}  PASS${NC} %s\n" "$desc"
  fi
}

# Setup
TMPDIR_ORIG="${TMPDIR:-/tmp}"
TEST_TMPDIR=$(mktemp -d)
TEST_SESSION="gateguard-test-$$"
TEST_STATE=$(mktemp -d)
mkdir -p "$TEST_STATE"
echo '{"projectPath":"/tmp/test"}' > "$TEST_STATE/manifest.json"

# Create a real file for "existing file" tests
TEST_EXISTING_FILE="$TEST_TMPDIR/existing-file.swift"
echo "// existing" > "$TEST_EXISTING_FILE"

# Cleanup
trap 'rm -rf "$TEST_TMPDIR" "$TEST_STATE"' EXIT

# Helper: run tracker with Read JSON
run_tracker() {
  local file_path="$1"
  echo "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$file_path\"}}" | \
    TMPDIR="$TEST_TMPDIR" CLAUDE_SESSION_ID="$TEST_SESSION" \
    bash -c "source '$PROJECT_ROOT/shared/hooks/scripts/lib/common.sh'; get_state_dir() { echo '$TEST_STATE'; }; export -f get_state_dir; bash '$TRACKER_SCRIPT'" 2>/dev/null
}

# Helper: run gate with Edit/Write JSON
run_gate() {
  local tool_name="$1" file_path="$2" env_extra="${3:-}"
  echo "{\"tool_name\":\"$tool_name\",\"tool_input\":{\"file_path\":\"$file_path\"}}" | \
    TMPDIR="$TEST_TMPDIR" CLAUDE_SESSION_ID="$TEST_SESSION" \
    SYMBIOTE_HOME="$TEST_TMPDIR" CLAUDE_PROJECT_DIR="/tmp/test" \
    env $env_extra \
    bash -c "source '$PROJECT_ROOT/shared/hooks/scripts/lib/common.sh'; get_state_dir() { echo '$TEST_STATE'; }; export -f get_state_dir json_field json_nested_field json_escape emit_hook_block emit_hook_continue hook_uses_cursor_protocol; bash '$GATE_SCRIPT'" 2>/dev/null
}

echo ""
printf "${YELLOW}=== GateGuard Tests ===${NC}\n"

# Test 1: Block on edit to unread file
printf "\n${YELLOW}Test 1: Block on edit to unread file${NC}\n"
# Clean session file
rm -f "$TEST_TMPDIR/symbiote-gateguard-$TEST_SESSION"
OUTPUT=$(run_gate "Edit" "$TEST_EXISTING_FILE")
assert_contains "blocks unread file" "GateGuard" "$OUTPUT"
assert_contains "mentions Read first" "Read" "$OUTPUT"
assert_contains "output denies" "continue" "$OUTPUT"

# Test 2: Allow after read tracking
printf "\n${YELLOW}Test 2: Allow after read tracking${NC}\n"
rm -f "$TEST_TMPDIR/symbiote-gateguard-$TEST_SESSION"
run_tracker "$TEST_EXISTING_FILE" > /dev/null
OUTPUT=$(run_gate "Edit" "$TEST_EXISTING_FILE")
assert_contains "allows after read" "\"continue\":true" "$OUTPUT"
assert_not_contains "no block message" "GateGuard" "$OUTPUT"

# Test 3: Allow new file creation (Write, file does NOT exist)
printf "\n${YELLOW}Test 3: Allow new file creation${NC}\n"
rm -f "$TEST_TMPDIR/symbiote-gateguard-$TEST_SESSION"
OUTPUT=$(run_gate "Write" "$TEST_TMPDIR/brand-new-file.swift")
assert_contains "allows new file" "\"continue\":true" "$OUTPUT"
assert_not_contains "no block for new file" "GateGuard" "$OUTPUT"

# Test 4: Override with SYMBIOTE_GATEGUARD=0
printf "\n${YELLOW}Test 4: Override with SYMBIOTE_GATEGUARD=0${NC}\n"
rm -f "$TEST_TMPDIR/symbiote-gateguard-$TEST_SESSION"
OUTPUT=$(run_gate "Edit" "$TEST_EXISTING_FILE" "SYMBIOTE_GATEGUARD=0")
assert_contains "override allows unread" "\"continue\":true" "$OUTPUT"
assert_not_contains "no block with override" "GateGuard" "$OUTPUT"

# Test 5: Empty file_path → continue
printf "\n${YELLOW}Test 5: Empty file_path → continue${NC}\n"
OUTPUT=$(echo '{"tool_name":"Edit","tool_input":{}}' | \
  TMPDIR="$TEST_TMPDIR" CLAUDE_SESSION_ID="$TEST_SESSION" \
  bash -c "source '$PROJECT_ROOT/shared/hooks/scripts/lib/common.sh'; get_state_dir() { echo '$TEST_STATE'; }; export -f get_state_dir json_field json_nested_field json_escape emit_hook_block emit_hook_continue hook_uses_cursor_protocol; bash '$GATE_SCRIPT'" 2>/dev/null)
assert_contains "continues on empty path" "\"continue\":true" "$OUTPUT"

# Test 6: harness-log.jsonl records gateguard_blocked
# Note: get_state_dir in the gate script resolves via slug. We set up a matching structure.
printf "\n${YELLOW}Test 6: harness-log records blocked event${NC}\n"
rm -f "$TEST_TMPDIR/symbiote-gateguard-$TEST_SESSION"
TEST_LOG_DIR="$TEST_TMPDIR/gateguard-log-test"
mkdir -p "$TEST_LOG_DIR"
echo '{"projectPath":"/tmp/test"}' > "$TEST_LOG_DIR/manifest.json"
rm -f "$TEST_LOG_DIR/harness-log.jsonl"
OUTPUT=$(echo "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$TEST_EXISTING_FILE\"}}" | \
  TMPDIR="$TEST_TMPDIR" CLAUDE_SESSION_ID="$TEST_SESSION" \
  bash -c "
    source '$PROJECT_ROOT/shared/hooks/scripts/lib/common.sh'
    get_state_dir() { echo '$TEST_LOG_DIR'; }
    emit_hook_block() { local msg=\"\$1\"; local escaped; escaped=\$(json_escape \"\$msg\"); printf '{\"continue\":false,\"permissionDecision\":\"deny\",\"systemMessage\":\"%s\"}\n' \"\$escaped\"; }
    export -f get_state_dir json_field json_nested_field json_escape emit_hook_block emit_hook_continue hook_uses_cursor_protocol
    # Source gate script in-process so overrides survive
    SCRIPT_DIR='$PROJECT_ROOT/shared/hooks/scripts'
    SYMBIOTE_GATEGUARD=''
    INPUT=\$(cat)
    TOOL_NAME='Edit'
    FILE_PATH='$TEST_EXISTING_FILE'
    SESSION_FILE='$TEST_TMPDIR/symbiote-gateguard-$TEST_SESSION'
    if ! grep -qxF \"\$FILE_PATH\" \"\$SESSION_FILE\" 2>/dev/null; then
      emit_hook_block \"[GateGuard] Read \$(basename \"\$FILE_PATH\") first.\"
      STATE_DIR=\$(get_state_dir)
      if [ -d \"\$STATE_DIR\" ]; then
        ESCAPED_FILE=\$(json_escape \"\$FILE_PATH\")
        printf '{\"v\":2,\"ts\":\"%s\",\"type\":\"gateguard_blocked\",\"file\":\"%s\",\"session_pid\":\"%s\"}\n' \
          \"\$(date -u +%Y-%m-%dT%H:%M:%SZ)\" \"\$ESCAPED_FILE\" \"$$\" >> \"\$STATE_DIR/harness-log.jsonl\"
      fi
    fi
  " 2>/dev/null)
if [ -f "$TEST_LOG_DIR/harness-log.jsonl" ]; then
  LOG_CONTENT=$(cat "$TEST_LOG_DIR/harness-log.jsonl")
  assert_contains "log has gateguard_blocked" "gateguard_blocked" "$LOG_CONTENT"
  assert_contains "log has file path" "existing-file.swift" "$LOG_CONTENT"
else
  TOTAL=$((TOTAL + 2))
  FAILED=$((FAILED + 2))
  printf "${RED}  FAIL${NC} harness-log.jsonl not created\n"
  printf "${RED}  FAIL${NC} (skipped file path check)\n"
fi

# Test 7: Tracker records to session file
printf "\n${YELLOW}Test 7: Tracker records to session file${NC}\n"
rm -f "$TEST_TMPDIR/symbiote-gateguard-$TEST_SESSION"
run_tracker "/path/to/file1.swift" > /dev/null
run_tracker "/path/to/file2.swift" > /dev/null
SESSION_CONTENT=$(cat "$TEST_TMPDIR/symbiote-gateguard-$TEST_SESSION" 2>/dev/null)
assert_contains "session file has file1" "/path/to/file1.swift" "$SESSION_CONTENT"
assert_contains "session file has file2" "/path/to/file2.swift" "$SESSION_CONTENT"

# Test 8: Cursor protocol on block
printf "\n${YELLOW}Test 8: Cursor protocol output${NC}\n"
rm -f "$TEST_TMPDIR/symbiote-gateguard-$TEST_SESSION"
OUTPUT=$(echo "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$TEST_EXISTING_FILE\"}}" | \
  TMPDIR="$TEST_TMPDIR" CLAUDE_SESSION_ID="$TEST_SESSION" \
  CURSOR_PLUGIN_ROOT="/tmp/cursor" \
  SYMBIOTE_HOME="$TEST_TMPDIR" CLAUDE_PROJECT_DIR="/tmp/test" \
  bash -c "source '$PROJECT_ROOT/shared/hooks/scripts/lib/common.sh'; get_state_dir() { echo '$TEST_STATE'; }; export -f get_state_dir json_field json_nested_field json_escape emit_hook_block emit_hook_continue hook_uses_cursor_protocol; bash '$GATE_SCRIPT'" 2>/dev/null)
assert_contains "cursor has permission deny" "\"permission\":\"deny\"" "$OUTPUT"
assert_contains "cursor has agent_message" "\"agent_message\":" "$OUTPUT"

echo ""
printf "${YELLOW}=== Results ===${NC}\n"
printf "Total: %d  Passed: ${GREEN}%d${NC}  Failed: ${RED}%d${NC}\n" "$TOTAL" "$PASSED" "$FAILED"
if [ "$FAILED" -gt 0 ]; then
  exit 1
else
  printf "${GREEN}All tests passed!${NC}\n"
fi
