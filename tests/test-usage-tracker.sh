#!/bin/bash
# Integration tests for usage-tracker.sh.
#
# Usage: bash tests/test-usage-tracker.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TRACKER_SCRIPT="$PROJECT_ROOT/shared/hooks/scripts/usage-tracker.sh"

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

counter_value() {
  local file="$1"
  [ -f "$file" ] || {
    echo "0"
    return 0
  }
  cut -d'|' -f1 "$file" 2>/dev/null
}

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

STATE_DIR="$TMPDIR/state"
mkdir -p "$STATE_DIR/usage-data/skills" "$STATE_DIR/usage-data/commands" "$STATE_DIR/state"

run_hook() {
  local input="$1"
  printf '%s' "$input" | HARNESS_TEST_STATE_DIR="$STATE_DIR" bash "$TRACKER_SCRIPT" 2>/dev/null
}

echo ""
echo "=== usage-tracker.sh Tests ==="
echo ""

echo "--- Test 1: Claude command-message increments skills and commands ---"
run_hook '{"hook_event_name":"UserPromptSubmit","prompt":"<command-message>ai-symbiote:plan</command-message>\n<command-name>/ai-symbiote:plan</command-name>"}'
assert_eq "skills/plan count after command-message" "1" "$(counter_value "$STATE_DIR/usage-data/skills/plan")"
assert_eq "commands/plan count after command-message" "1" "$(counter_value "$STATE_DIR/usage-data/commands/plan")"

echo ""
echo "--- Test 2: immediate SKILL.md Read is deduplicated after command-message ---"
run_hook "{\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$PROJECT_ROOT/shared/skills/plan/SKILL.md\"}}"
assert_eq "skills/plan still 1 after immediate Read" "1" "$(counter_value "$STATE_DIR/usage-data/skills/plan")"

echo ""
echo "--- Test 3: Skill tool input increments skills ---"
run_hook '{"hook_event_name":"PostToolUse","tool_name":"Skill","tool_input":{"skill":"ai-symbiote:review"}}'
assert_eq "skills/review count after Skill tool" "1" "$(counter_value "$STATE_DIR/usage-data/skills/review")"

echo ""
echo "--- Test 4: command-name tag increments skills and commands ---"
run_hook '{"hook_event_name":"UserPromptSubmit","prompt":"<command-name>/ai-symbiote:setup</command-name>"}'
assert_eq "skills/setup count after command-name" "1" "$(counter_value "$STATE_DIR/usage-data/skills/setup")"
assert_eq "commands/setup count after command-name" "1" "$(counter_value "$STATE_DIR/usage-data/commands/setup")"

echo ""
echo "--- Test 5: bare slash command increments skills and commands ---"
run_hook '{"hook_event_name":"UserPromptSubmit","prompt":"  /ai-symbiote:security scan this repo"}'
assert_eq "skills/security count after bare slash command" "1" "$(counter_value "$STATE_DIR/usage-data/skills/security")"
assert_eq "commands/security count after bare slash command" "1" "$(counter_value "$STATE_DIR/usage-data/commands/security")"

echo ""
echo "--- Test 6: legacy Read increments skill when no recent marker exists ---"
run_hook "{\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$PROJECT_ROOT/shared/skills/analyze/SKILL.md\"}}"
assert_eq "skills/analyze count after legacy Read" "1" "$(counter_value "$STATE_DIR/usage-data/skills/analyze")"

echo ""
echo "=== Results ==="
printf "Passed: %d / %d\n" "$PASSED" "$TOTAL"
if [ "$FAILED" -gt 0 ]; then
  printf "${RED}Failed: %d${NC}\n" "$FAILED"
  exit 1
else
  printf "${GREEN}All tests passed!${NC}\n"
fi
