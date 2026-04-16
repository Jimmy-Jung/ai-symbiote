#!/bin/bash
# Integration tests for suggest-compact.sh.
#
# Usage: bash tests/test-suggest-compact.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPACT_SCRIPT="$PROJECT_ROOT/shared/hooks/scripts/suggest-compact.sh"

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

TEST_TMPDIR=$(mktemp -d)
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# Helper to run the hook with a fresh or existing session
run_hook() {
  local session_id="$1"
  local threshold="${2:-50}"
  echo '{}' | CLAUDE_SESSION_ID="$session_id" TMPDIR="$TEST_TMPDIR" COMPACT_THRESHOLD="$threshold" bash "$COMPACT_SCRIPT" 2>/dev/null
}

echo ""
echo "=== suggest-compact.sh Tests ==="
echo ""

# --- Test 1: Counter increments on each call ---
echo "--- Test 1: Counter increments on each call ---"
SESSION_T1="test1-$$"
run_hook "$SESSION_T1" 50 >/dev/null
COUNTER_VAL=$(cat "$TEST_TMPDIR/symbiote-compact-${SESSION_T1}" 2>/dev/null)
assert_eq "counter is 1 after first call" "1" "$COUNTER_VAL"

run_hook "$SESSION_T1" 50 >/dev/null
COUNTER_VAL=$(cat "$TEST_TMPDIR/symbiote-compact-${SESSION_T1}" 2>/dev/null)
assert_eq "counter is 2 after second call" "2" "$COUNTER_VAL"

run_hook "$SESSION_T1" 50 >/dev/null
COUNTER_VAL=$(cat "$TEST_TMPDIR/symbiote-compact-${SESSION_T1}" 2>/dev/null)
assert_eq "counter is 3 after third call" "3" "$COUNTER_VAL"

echo ""

# --- Test 2: No suggestion below threshold ---
echo "--- Test 2: No suggestion below threshold (49 calls, threshold=50) ---"
SESSION_T2="test2-$$"
ALL_OUTPUT=""
for i in $(seq 1 49); do
  OUTPUT=$(run_hook "$SESSION_T2" 50)
  ALL_OUTPUT="${ALL_OUTPUT}${OUTPUT}"
done
assert_not_contains "no [Compact] notice in 49 calls" "[Compact]" "$ALL_OUTPUT"

echo ""

# --- Test 3: Suggestion at threshold ---
echo "--- Test 3: Suggestion at threshold (COMPACT_THRESHOLD=5, 5th call) ---"
SESSION_T3="test3-$$"
for i in $(seq 1 4); do
  run_hook "$SESSION_T3" 5 >/dev/null
done
OUTPUT=$(run_hook "$SESSION_T3" 5)
assert_contains "notice at threshold" "[Compact] 5 tool calls" "$OUTPUT"

echo ""

# --- Test 4: Re-alert at threshold+25 ---
echo "--- Test 4: Re-alert at threshold+25 (threshold=3, expect alerts at 3 and 28) ---"
SESSION_T4="test4-$$"
FIRST_ALERT=""
SECOND_ALERT=""
for i in $(seq 1 28); do
  OUTPUT=$(run_hook "$SESSION_T4" 3)
  if [ "$i" -eq 3 ]; then
    FIRST_ALERT="$OUTPUT"
  fi
  if [ "$i" -eq 28 ]; then
    SECOND_ALERT="$OUTPUT"
  fi
done
assert_contains "first alert at count=3" "[Compact] 3 tool calls" "$FIRST_ALERT"
assert_contains "second alert at count=28 (3+25)" "[Compact] 28 tool calls" "$SECOND_ALERT"

echo ""

# --- Test 5: Invalid threshold clamped ---
echo "--- Test 5: Invalid threshold clamped ---"

# COMPACT_THRESHOLD=0 → clamped to 1, first call triggers notice
SESSION_T5A="test5a-$$"
OUTPUT=$(run_hook "$SESSION_T5A" 0)
assert_contains "threshold=0 clamped to 1, notice on first call" "[Compact] 1 tool calls" "$OUTPUT"

# COMPACT_THRESHOLD=99999 → clamped to 10000
SESSION_T5B="test5b-$$"
OUTPUT=$(run_hook "$SESSION_T5B" 99999)
assert_not_contains "threshold=99999 clamped to 10000, no notice on first call" "[Compact]" "$OUTPUT"

echo ""
echo "=== Results ==="
printf "Passed: %d / %d\n" "$PASSED" "$TOTAL"
if [ "$FAILED" -gt 0 ]; then
  printf "${RED}Failed: %d${NC}\n" "$FAILED"
  exit 1
else
  printf "${GREEN}All tests passed!${NC}\n"
fi
