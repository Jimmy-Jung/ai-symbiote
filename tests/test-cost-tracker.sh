#!/bin/bash
# Integration tests for cost-tracker.sh (Stop hook).
#
# Usage: bash tests/test-cost-tracker.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TRACKER_SCRIPT="$PROJECT_ROOT/shared/hooks/scripts/cost-tracker.sh"

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
  printf '%s' "$input" | HARNESS_TEST_STATE_DIR="$state_dir" bash "$TRACKER_SCRIPT" 2>/dev/null
}

echo ""
echo "=== cost-tracker.sh Tests ==="
echo ""

# --- Test 1: Creates sessions.jsonl with session record ---
echo "--- Test 1: Creates sessions.jsonl with session record ---"
STATE_DIR="$TMPDIR_ROOT/test1"
mkdir -p "$STATE_DIR"
run_hook "$STATE_DIR" '{"type":"stop","transcript_path":"/tmp/test"}' >/dev/null
assert_eq "sessions.jsonl exists" "true" "$([ -f "$STATE_DIR/usage-data/sessions.jsonl" ] && echo true || echo false)"
LINE_COUNT=$(wc -l < "$STATE_DIR/usage-data/sessions.jsonl" | tr -d ' ')
assert_eq "sessions.jsonl has 1 line" "1" "$LINE_COUNT"

echo ""

# --- Test 2: Record contains "ts" and "session_id" fields ---
echo "--- Test 2: Record contains ts and session_id fields ---"
RECORD=$(cat "$STATE_DIR/usage-data/sessions.jsonl")
assert_contains "record contains ts field" '"ts":' "$RECORD"
assert_contains "record contains session_id field" '"session_id":' "$RECORD"
assert_contains "record contains completed field" '"completed":true' "$RECORD"

echo ""

# --- Test 3: Truncation at 101 records ---
echo "--- Test 3: Truncation at 101 records ---"
STATE_DIR="$TMPDIR_ROOT/test3"
mkdir -p "$STATE_DIR/usage-data"
# Pre-populate with 101 lines
for i in $(seq 1 101); do
  echo "{\"ts\":\"2026-01-01T00:00:${i}Z\",\"session_id\":\"s$i\",\"completed\":true}" >> "$STATE_DIR/usage-data/sessions.jsonl"
done
PRE_LINES=$(wc -l < "$STATE_DIR/usage-data/sessions.jsonl" | tr -d ' ')
assert_eq "pre-populated with 101 lines" "101" "$PRE_LINES"
run_hook "$STATE_DIR" '{"type":"stop"}' >/dev/null
POST_LINES=$(wc -l < "$STATE_DIR/usage-data/sessions.jsonl" | tr -d ' ')
assert_eq "truncated to 100 lines after adding 1 more" "100" "$POST_LINES"

echo ""

# --- Test 4: Passes stdin through to stdout ---
echo "--- Test 4: Passes stdin through to stdout ---"
STATE_DIR="$TMPDIR_ROOT/test4"
mkdir -p "$STATE_DIR"
INPUT='{"type":"stop","transcript_path":"/tmp/test"}'
OUTPUT=$(run_hook "$STATE_DIR" "$INPUT")
assert_eq "stdout matches stdin" "$INPUT" "$OUTPUT"

echo ""

# --- Test 5: Handles missing usage-data directory ---
echo "--- Test 5: Handles missing usage-data directory (creates it) ---"
STATE_DIR="$TMPDIR_ROOT/test5"
mkdir -p "$STATE_DIR"
# Do NOT create usage-data dir — the script should create it
run_hook "$STATE_DIR" '{"type":"stop"}' >/dev/null
assert_eq "usage-data dir created" "true" "$([ -d "$STATE_DIR/usage-data" ] && echo true || echo false)"
assert_eq "sessions.jsonl created" "true" "$([ -f "$STATE_DIR/usage-data/sessions.jsonl" ] && echo true || echo false)"

echo ""
echo "=== Results ==="
printf "Passed: %d / %d\n" "$PASSED" "$TOTAL"
if [ "$FAILED" -gt 0 ]; then
  printf "${RED}Failed: %d${NC}\n" "$FAILED"
  exit 1
else
  printf "${GREEN}All tests passed!${NC}\n"
fi
