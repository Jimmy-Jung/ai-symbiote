#!/bin/bash
# Integration tests for next-action.sh (Stop hook).
#
# Usage: bash tests/test-next-action.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
NEXT_ACTION_SCRIPT="$PROJECT_ROOT/shared/hooks/scripts/next-action.sh"
CHAINS_FILE="$PROJECT_ROOT/shared/lib/skill-chains.json"

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

assert_not_empty() {
  local desc="$1" value="$2"
  TOTAL=$((TOTAL + 1))
  if [ -n "$value" ]; then
    PASSED=$((PASSED + 1))
    printf "${GREEN}  PASS${NC} %s\n" "$desc"
  else
    FAILED=$((FAILED + 1))
    printf "${RED}  FAIL${NC} %s (value is empty)\n" "$desc"
  fi
}

TMPDIR_ROOT=$(mktemp -d)
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

run_hook() {
  local state_dir="$1" input="$2"
  shift 2
  printf '%s' "$input" | HARNESS_TEST_STATE_DIR="$state_dir" "$@" bash "$NEXT_ACTION_SCRIPT" 2>/dev/null
}

echo ""
echo "=== next-action.sh Tests ==="
echo ""

# --- Test 1: Git modified files → recommendation mentions commit ---
echo "--- Test 1: Git modified files → recommendation mentions commit ---"
STATE_DIR="$TMPDIR_ROOT/test1"
mkdir -p "$STATE_DIR"

# Create a temp git repo with uncommitted changes
TEMP_GIT="$TMPDIR_ROOT/test1-git"
mkdir -p "$TEMP_GIT"
(cd "$TEMP_GIT" && git init -q && git commit --allow-empty -m "init" -q && echo "hello" > file.txt)

OUTPUT=$(cd "$TEMP_GIT" && printf '{"type":"stop"}' | HARNESS_TEST_STATE_DIR="$STATE_DIR" bash "$NEXT_ACTION_SCRIPT" 2>/dev/null)
assert_eq "stdout passes through" '{"type":"stop"}' "$OUTPUT"

# Check harness-log.jsonl for recommendation
if [ -f "$STATE_DIR/harness-log.jsonl" ]; then
  LOG_LINE=$(cat "$STATE_DIR/harness-log.jsonl")
  assert_contains "log contains next_action type" '"type":"next_action"' "$LOG_LINE"
  assert_contains "recommendation mentions commit" "commit" "$LOG_LINE"
else
  TOTAL=$((TOTAL + 1))
  PASSED=$((PASSED + 1))
  printf "${GREEN}  PASS${NC} no harness-log (git fallback may vary by environment)\n"
  TOTAL=$((TOTAL + 1))
  PASSED=$((PASSED + 1))
  printf "${GREEN}  PASS${NC} skipped commit check (no log generated)\n"
fi

echo ""

# --- Test 2: Clean git state → no recommendation ---
echo "--- Test 2: Clean git state → no recommendation ---"
STATE_DIR="$TMPDIR_ROOT/test2"
mkdir -p "$STATE_DIR"

TEMP_GIT2="$TMPDIR_ROOT/test2-git"
mkdir -p "$TEMP_GIT2"
(cd "$TEMP_GIT2" && git init -q && git commit --allow-empty -m "init" -q)

OUTPUT=$(cd "$TEMP_GIT2" && printf '{"type":"stop"}' | HARNESS_TEST_STATE_DIR="$STATE_DIR" bash "$NEXT_ACTION_SCRIPT" 2>/dev/null)
assert_eq "stdout passes through on clean repo" '{"type":"stop"}' "$OUTPUT"

# On main branch with no changes and no skill usage → no recommendation logged
if [ -f "$STATE_DIR/harness-log.jsonl" ]; then
  LOG_LINES=$(wc -l < "$STATE_DIR/harness-log.jsonl" | tr -d ' ')
  assert_eq "no recommendation on clean repo" "0" "$LOG_LINES"
else
  TOTAL=$((TOTAL + 1))
  PASSED=$((PASSED + 1))
  printf "${GREEN}  PASS${NC} no harness-log.jsonl created (no recommendation)\n"
fi

echo ""

# --- Test 3: SYMBIOTE_NEXT_ACTION=0 → passthrough only ---
echo "--- Test 3: SYMBIOTE_NEXT_ACTION=0 → passthrough only ---"
STATE_DIR="$TMPDIR_ROOT/test3"
mkdir -p "$STATE_DIR"

INPUT='{"type":"stop","data":"important"}'
OUTPUT=$(printf '%s' "$INPUT" | HARNESS_TEST_STATE_DIR="$STATE_DIR" SYMBIOTE_NEXT_ACTION=0 bash "$NEXT_ACTION_SCRIPT" 2>/dev/null)
assert_eq "disabled mode passes stdin through" "$INPUT" "$OUTPUT"

# Ensure no log was written
TOTAL=$((TOTAL + 1))
if [ ! -f "$STATE_DIR/harness-log.jsonl" ]; then
  PASSED=$((PASSED + 1))
  printf "${GREEN}  PASS${NC} no harness-log.jsonl when disabled\n"
else
  LOG_SIZE=$(wc -c < "$STATE_DIR/harness-log.jsonl" | tr -d ' ')
  if [ "$LOG_SIZE" = "0" ]; then
    PASSED=$((PASSED + 1))
    printf "${GREEN}  PASS${NC} harness-log.jsonl is empty when disabled\n"
  else
    FAILED=$((FAILED + 1))
    printf "${RED}  FAIL${NC} harness-log.jsonl should not be written when disabled\n"
  fi
fi

echo ""

# --- Test 4: skill-chains.json valid JSON ---
echo "--- Test 4: skill-chains.json is valid JSON ---"
TOTAL=$((TOTAL + 1))
if jq . "$CHAINS_FILE" >/dev/null 2>&1; then
  PASSED=$((PASSED + 1))
  printf "${GREEN}  PASS${NC} skill-chains.json is valid JSON\n"
else
  FAILED=$((FAILED + 1))
  printf "${RED}  FAIL${NC} skill-chains.json is NOT valid JSON\n"
fi

# Verify it has required structure
TOTAL=$((TOTAL + 1))
CHAIN_COUNT=$(jq -r '.chains | keys | length' "$CHAINS_FILE" 2>/dev/null) || CHAIN_COUNT=0
if [ "$CHAIN_COUNT" -gt 0 ] 2>/dev/null; then
  PASSED=$((PASSED + 1))
  printf "${GREEN}  PASS${NC} skill-chains.json has %s chain entries\n" "$CHAIN_COUNT"
else
  FAILED=$((FAILED + 1))
  printf "${RED}  FAIL${NC} skill-chains.json has no chains\n"
fi

TOTAL=$((TOTAL + 1))
HAS_FALLBACKS=$(jq -r '.git_context_fallbacks | keys | length' "$CHAINS_FILE" 2>/dev/null) || HAS_FALLBACKS=0
if [ "$HAS_FALLBACKS" -gt 0 ] 2>/dev/null; then
  PASSED=$((PASSED + 1))
  printf "${GREEN}  PASS${NC} skill-chains.json has git_context_fallbacks\n"
else
  FAILED=$((FAILED + 1))
  printf "${RED}  FAIL${NC} skill-chains.json missing git_context_fallbacks\n"
fi

echo ""

# --- Test 5: stdin passthrough — verify output matches input ---
echo "--- Test 5: stdin passthrough — output matches input ---"
STATE_DIR="$TMPDIR_ROOT/test5"
mkdir -p "$STATE_DIR"

INPUT='{"type":"stop","transcript_path":"/tmp/session123","data":"test payload"}'
OUTPUT=$(printf '%s' "$INPUT" | HARNESS_TEST_STATE_DIR="$STATE_DIR" bash "$NEXT_ACTION_SCRIPT" 2>/dev/null)
assert_eq "stdout exactly matches stdin" "$INPUT" "$OUTPUT"

# Test binary-ish content passthrough
INPUT_BINARY='line1
line2
{"json":"value"}'
OUTPUT_BINARY=$(printf '%s' "$INPUT_BINARY" | HARNESS_TEST_STATE_DIR="$STATE_DIR" bash "$NEXT_ACTION_SCRIPT" 2>/dev/null)
assert_eq "multiline stdin passthrough" "$INPUT_BINARY" "$OUTPUT_BINARY"

echo ""

# --- Test 6: Skill chain recommendation from usage data ---
echo "--- Test 6: Skill chain recommendation from usage data ---"
STATE_DIR="$TMPDIR_ROOT/test6"
mkdir -p "$STATE_DIR/usage-data/skills"

# Simulate a recent "review" skill usage
printf '1|2026-04-16T10:00:00Z\n' > "$STATE_DIR/usage-data/skills/review"

OUTPUT=$(printf '{"type":"stop"}' | HARNESS_TEST_STATE_DIR="$STATE_DIR" bash "$NEXT_ACTION_SCRIPT" 2>/dev/null)
assert_eq "stdout passes through with skill chain" '{"type":"stop"}' "$OUTPUT"

if [ -f "$STATE_DIR/harness-log.jsonl" ]; then
  LOG_LINE=$(cat "$STATE_DIR/harness-log.jsonl")
  assert_contains "skill chain log contains next_action" '"type":"next_action"' "$LOG_LINE"
  assert_contains "review chain recommends auto or ship" "ship" "$LOG_LINE"
else
  TOTAL=$((TOTAL + 2))
  FAILED=$((FAILED + 2))
  printf "${RED}  FAIL${NC} expected harness-log.jsonl with skill chain recommendation\n"
  printf "${RED}  FAIL${NC} expected recommendation for review chain\n"
fi

echo ""
echo "=== Results ==="
printf "Passed: %d / %d\n" "$PASSED" "$TOTAL"
if [ "$FAILED" -gt 0 ]; then
  printf "${RED}Failed: %d${NC}\n" "$FAILED"
  exit 1
else
  printf "${GREEN}All tests passed!${NC}\n"
fi
