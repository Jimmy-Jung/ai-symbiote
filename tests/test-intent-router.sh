#!/bin/bash
# Integration tests for intent-router.sh (UserPromptSubmit hook).
#
# Usage: bash tests/test-intent-router.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ROUTER_SCRIPT="$PROJECT_ROOT/shared/hooks/scripts/intent-router.sh"
HINTS_FILE="$PROJECT_ROOT/shared/lib/intent-hints.json"

PASSED=0
FAILED=0
TOTAL=0

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  TOTAL=$((TOTAL + 1))
  if [ "$expected" = "$actual" ]; then
    PASSED=$((PASSED + 1))
    printf "${GREEN}  PASS${NC} %s\n" "$desc"
  else
    FAILED=$((FAILED + 1))
    printf "${RED}  FAIL${NC} %s\n    expected: %s\n    actual:   %s\n" "$desc" "$expected" "$actual"
  fi
}

assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  TOTAL=$((TOTAL + 1))
  if printf '%s' "$haystack" | grep -q "$needle"; then
    PASSED=$((PASSED + 1))
    printf "${GREEN}  PASS${NC} %s\n" "$desc"
  else
    FAILED=$((FAILED + 1))
    printf "${RED}  FAIL${NC} %s\n    expected to contain: %s\n    actual: %s\n" "$desc" "$needle" "$haystack"
  fi
}

assert_not_contains() {
  local desc="$1" needle="$2" haystack="$3"
  TOTAL=$((TOTAL + 1))
  if ! printf '%s' "$haystack" | grep -q "$needle"; then
    PASSED=$((PASSED + 1))
    printf "${GREEN}  PASS${NC} %s\n" "$desc"
  else
    FAILED=$((FAILED + 1))
    printf "${RED}  FAIL${NC} %s\n    expected NOT to contain: %s\n    actual: %s\n" "$desc" "$needle" "$haystack"
  fi
}

run_hook() {
  local input="$1"
  printf '%s' "$input" | bash "$ROUTER_SCRIPT" 2>/dev/null
}

run_hook_cursor() {
  local input="$1"
  printf '%s' "$input" | CURSOR_PLUGIN_ROOT="/tmp/fake-cursor" bash "$ROUTER_SCRIPT" 2>/dev/null
}

echo ""
echo "=== intent-router.sh Tests ==="
echo ""

# --- Test 1: Normal prompt → output contains Intent and systemMessage ---
echo "--- Test 1: Normal prompt emits systemMessage with intent hints ---"
INPUT='{"user_prompt":"버그 수정해줘 로그인이 안 돼"}'
OUTPUT=$(run_hook "$INPUT")
assert_contains "output contains Intent Router marker" "Intent Router" "$OUTPUT"
assert_contains "output contains systemMessage" "systemMessage" "$OUTPUT"
assert_contains "output contains continue:true" '"continue":true' "$OUTPUT"

echo ""

# --- Test 2: Short prompt (1 word) → emit_hook_continue ---
echo "--- Test 2: Short prompt (1 word) passes through ---"
INPUT='{"user_prompt":"안녕"}'
OUTPUT=$(run_hook "$INPUT")
assert_contains "output contains continue:true" '"continue":true' "$OUTPUT"
assert_not_contains "short prompt has no Intent Router" "Intent Router" "$OUTPUT"

echo ""

# --- Test 3: Slash command → emit_hook_continue ---
echo "--- Test 3: Slash command passes through ---"
INPUT='{"user_prompt":"/commit"}'
OUTPUT=$(run_hook "$INPUT")
assert_contains "output contains continue:true" '"continue":true' "$OUTPUT"
assert_not_contains "slash command has no Intent Router" "Intent Router" "$OUTPUT"

echo ""

# --- Test 4: Empty prompt → emit_hook_continue ---
echo "--- Test 4: Empty prompt passes through ---"
INPUT='{"user_prompt":""}'
OUTPUT=$(run_hook "$INPUT")
assert_contains "output contains continue:true" '"continue":true' "$OUTPUT"
assert_not_contains "empty prompt has no Intent Router" "Intent Router" "$OUTPUT"

# Also test missing user_prompt field
INPUT='{}'
OUTPUT=$(run_hook "$INPUT")
assert_contains "missing field → continue:true" '"continue":true' "$OUTPUT"

echo ""

# --- Test 5: intent-hints.json valid JSON ---
echo "--- Test 5: intent-hints.json is valid JSON ---"
TOTAL=$((TOTAL + 1))
if jq . "$HINTS_FILE" >/dev/null 2>&1; then
  PASSED=$((PASSED + 1))
  printf "${GREEN}  PASS${NC} intent-hints.json is valid JSON\n"
else
  FAILED=$((FAILED + 1))
  printf "${RED}  FAIL${NC} intent-hints.json is NOT valid JSON\n"
fi

# Verify it has required structure
TOTAL=$((TOTAL + 1))
CATEGORIES=$(jq -r '.categories | keys | length' "$HINTS_FILE" 2>/dev/null) || CATEGORIES=0
if [ "$CATEGORIES" -gt 0 ] 2>/dev/null; then
  PASSED=$((PASSED + 1))
  printf "${GREEN}  PASS${NC} intent-hints.json has %s categories\n" "$CATEGORIES"
else
  FAILED=$((FAILED + 1))
  printf "${RED}  FAIL${NC} intent-hints.json has no categories\n"
fi

echo ""

# --- Test 6: Cursor protocol format ---
echo "--- Test 6: Cursor protocol format ---"
INPUT='{"user_prompt":"버그 수정해줘 로그인이 안 돼 에러가 발생해"}'
OUTPUT=$(run_hook_cursor "$INPUT")
assert_contains "cursor output has permission:allow" '"permission":"allow"' "$OUTPUT"
assert_contains "cursor output has continue:true" '"continue":true' "$OUTPUT"

echo ""
echo "=== Results ==="
printf "Passed: %d / %d\n" "$PASSED" "$TOTAL"
if [ "$FAILED" -gt 0 ]; then
  printf "${RED}Failed: %d${NC}\n" "$FAILED"
  exit 1
else
  printf "${GREEN}All tests passed!${NC}\n"
fi
