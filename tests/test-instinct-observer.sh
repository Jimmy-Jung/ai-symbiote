#!/bin/bash
# Integration tests for instinct-observer.sh (Stop hook).
#
# Usage: bash tests/test-instinct-observer.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OBSERVER_SCRIPT="$PROJECT_ROOT/shared/hooks/scripts/instinct-observer.sh"

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

TMPDIR_ROOT=$(mktemp -d)
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

run_hook() {
  local state_dir="$1" input="$2"
  printf '%s' "$input" | HARNESS_TEST_STATE_DIR="$state_dir" bash "$OBSERVER_SCRIPT" 2>/dev/null
}

echo ""
echo "=== instinct-observer.sh Tests ==="
echo ""

# --- Test 1: Creates instincts directory ---
echo "--- Test 1: Creates instincts directory ---"
STATE_DIR="$TMPDIR_ROOT/test1"
mkdir -p "$STATE_DIR"
run_hook "$STATE_DIR" '{"type":"stop"}' >/dev/null
assert_eq "instincts dir exists" "true" "$([ -d "$STATE_DIR/instincts" ] && echo true || echo false)"

echo ""

# --- Test 2: Creates project-id.txt ---
echo "--- Test 2: Creates project-id.txt ---"
assert_eq "project-id.txt exists" "true" "$([ -f "$STATE_DIR/instincts/project-id.txt" ] && echo true || echo false)"
PROJECT_ID=$(cat "$STATE_DIR/instincts/project-id.txt")
assert_eq "project-id.txt is not empty" "true" "$([ -n "$PROJECT_ID" ] && echo true || echo false)"

echo ""

# --- Test 3: Appends observation to observations.jsonl ---
echo "--- Test 3: Appends observation to observations.jsonl ---"
assert_eq "observations.jsonl exists" "true" "$([ -f "$STATE_DIR/instincts/observations.jsonl" ] && echo true || echo false)"
LINE_COUNT=$(wc -l < "$STATE_DIR/instincts/observations.jsonl" | tr -d ' ')
assert_eq "observations.jsonl has 1 line" "1" "$LINE_COUNT"
RECORD=$(cat "$STATE_DIR/instincts/observations.jsonl")
assert_contains "record contains ts field" '"ts":' "$RECORD"
assert_contains "record contains session_id field" '"session_id":' "$RECORD"
assert_contains "record contains project_id field" '"project_id":' "$RECORD"
assert_contains "record contains type field" '"type":"observation"' "$RECORD"

# Run again to verify append
run_hook "$STATE_DIR" '{"type":"stop"}' >/dev/null
LINE_COUNT=$(wc -l < "$STATE_DIR/instincts/observations.jsonl" | tr -d ' ')
assert_eq "observations.jsonl has 2 lines after second run" "2" "$LINE_COUNT"

echo ""

# --- Test 4: Passes stdin through to stdout ---
echo "--- Test 4: Passes stdin through to stdout ---"
STATE_DIR="$TMPDIR_ROOT/test4"
mkdir -p "$STATE_DIR"
INPUT='{"type":"stop","transcript_path":"/tmp/test"}'
OUTPUT=$(run_hook "$STATE_DIR" "$INPUT")
assert_eq "stdout matches stdin" "$INPUT" "$OUTPUT"

echo ""

# --- Test 5: Handles missing git remote gracefully ---
echo "--- Test 5: Handles missing git remote gracefully ---"
STATE_DIR="$TMPDIR_ROOT/test5"
mkdir -p "$STATE_DIR"
# Run in /tmp where there's no git repo
OUTPUT=$(printf '{"type":"stop"}' | HARNESS_TEST_STATE_DIR="$STATE_DIR" bash -c 'cd /tmp && bash "'"$OBSERVER_SCRIPT"'"' 2>/dev/null)
assert_eq "instincts dir created despite no git" "true" "$([ -d "$STATE_DIR/instincts" ] && echo true || echo false)"
assert_eq "project-id.txt created despite no git" "true" "$([ -f "$STATE_DIR/instincts/project-id.txt" ] && echo true || echo false)"
FALLBACK_ID=$(cat "$STATE_DIR/instincts/project-id.txt")
assert_eq "fallback project ID is not empty" "true" "$([ -n "$FALLBACK_ID" ] && echo true || echo false)"

echo ""
echo "=== Results ==="
printf "Passed: %d / %d\n" "$PASSED" "$TOTAL"
if [ "$FAILED" -gt 0 ]; then
  printf "${RED}Failed: %d${NC}\n" "$FAILED"
  exit 1
else
  printf "${GREEN}All tests passed!${NC}\n"
fi
