#!/bin/bash
# Integration tests for pre-edit-write-dispatcher.sh.
#
# Tests the consolidated Edit/Write pre-flight dispatcher that runs
# config-protection, gateguard-gate, and suggest-compact in sequence.
#
# Author: JunyoungJung
# Date: 2026-04-16
#
# Usage: bash tests/test-dispatcher.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DISPATCHER_SCRIPT="$PROJECT_ROOT/shared/hooks/scripts/pre-edit-write-dispatcher.sh"
TRACKER_SCRIPT="$PROJECT_ROOT/shared/hooks/scripts/gateguard-tracker.sh"

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
    printf "${RED}  FAIL${NC} %s\n    should NOT contain: %s\n    haystack: %s\n" "$desc" "$needle" "$haystack"
  fi
}

assert_empty() {
  local desc="$1" value="$2"
  TOTAL=$((TOTAL + 1))
  if [ -z "$value" ]; then
    PASSED=$((PASSED + 1))
    printf "${GREEN}  PASS${NC} %s\n" "$desc"
  else
    FAILED=$((FAILED + 1))
    printf "${RED}  FAIL${NC} %s\n    expected empty output\n    actual: %s\n" "$desc" "$value"
  fi
}

# --- Setup ---
TEST_TMPDIR=$(mktemp -d)
TEST_STATE=$(mktemp -d)
mkdir -p "$TEST_STATE"
echo '{"projectPath":"/tmp/test-project"}' > "$TEST_STATE/manifest.json"

# Create a real file for "existing file" tests
TEST_EXISTING_FILE="$TEST_TMPDIR/existing-file.swift"
echo "// existing" > "$TEST_EXISTING_FILE"

TEST_SESSION="dispatcher-test-$$"

trap 'rm -rf "$TEST_TMPDIR" "$TEST_STATE"' EXIT

# Helper: run dispatcher with given JSON input
run_dispatcher() {
  local input="$1"
  shift
  printf '%s' "$input" | \
    TMPDIR="$TEST_TMPDIR" \
    CLAUDE_SESSION_ID="$TEST_SESSION" \
    HARNESS_TEST_STATE_DIR="$TEST_STATE" \
    SYMBIOTE_HOME="$TEST_TMPDIR" \
    CLAUDE_PROJECT_DIR="/tmp/test-project" \
    "$@" \
    bash "$DISPATCHER_SCRIPT" 2>/dev/null
}

# Helper: run gateguard tracker to record a file read
run_tracker() {
  local file_path="$1"
  echo "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$file_path\"}}" | \
    TMPDIR="$TEST_TMPDIR" CLAUDE_SESSION_ID="$TEST_SESSION" \
    HARNESS_TEST_STATE_DIR="$TEST_STATE" \
    bash "$TRACKER_SCRIPT" 2>/dev/null
}

# ============================================================
printf "\n${YELLOW}=== ai-symbiote Dispatcher Tests ===${NC}\n"

# ============================================================
# Test 1: Config protection blocks before gateguard runs
# ============================================================
printf "\n${YELLOW}Test 1: Config protection blocks before gateguard runs${NC}\n"
rm -f "$TEST_TMPDIR/symbiote-gateguard-$TEST_SESSION"
rm -f "$TEST_TMPDIR/symbiote-compact-$TEST_SESSION"

OUTPUT=$(run_dispatcher '{"tool_name":"Edit","tool_input":{"file_path":"/project/.swiftlint.yml","old_string":"a","new_string":"b"}}')

assert_contains "blocks .swiftlint.yml" "Config Protection" "$OUTPUT"
assert_contains "output denies permission" '"permissionDecision":"deny"' "$OUTPUT"
assert_not_contains "does not stop continuation" '"continue":false' "$OUTPUT"
assert_not_contains "gateguard does not fire" "GateGuard" "$OUTPUT"

# ============================================================
# Test 2: GateGuard blocks unread file
# ============================================================
printf "\n${YELLOW}Test 2: GateGuard blocks unread file${NC}\n"
rm -f "$TEST_TMPDIR/symbiote-gateguard-$TEST_SESSION"
rm -f "$TEST_TMPDIR/symbiote-compact-$TEST_SESSION"

OUTPUT=$(run_dispatcher "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$TEST_EXISTING_FILE\",\"old_string\":\"a\",\"new_string\":\"b\"}}")

assert_contains "blocks unread file" "GateGuard" "$OUTPUT"
assert_contains "mentions Read first" "Read" "$OUTPUT"
assert_contains "output denies" '"permissionDecision":"deny"' "$OUTPUT"
assert_not_contains "does not stop continuation" '"continue":false' "$OUTPUT"

# ============================================================
# Test 3: Dispatcher no longer emits compact notice in PreToolUse
# ============================================================
printf "\n${YELLOW}Test 3: Dispatcher no longer emits compact notice${NC}\n"
rm -f "$TEST_TMPDIR/symbiote-gateguard-$TEST_SESSION"
rm -f "$TEST_TMPDIR/symbiote-compact-$TEST_SESSION"

# Track the file as read so gateguard doesn't block
run_tracker "$TEST_EXISTING_FILE" > /dev/null

OUTPUT=$(printf '%s' "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$TEST_EXISTING_FILE\",\"old_string\":\"a\",\"new_string\":\"b\"}}" | \
  TMPDIR="$TEST_TMPDIR" \
  CLAUDE_SESSION_ID="$TEST_SESSION" \
  HARNESS_TEST_STATE_DIR="$TEST_STATE" \
  SYMBIOTE_HOME="$TEST_TMPDIR" \
  CLAUDE_PROJECT_DIR="/tmp/test-project" \
  COMPACT_THRESHOLD=1 \
  bash "$DISPATCHER_SCRIPT" 2>/dev/null)

assert_empty "dispatcher stays silent even at compact threshold" "$OUTPUT"

# ============================================================
# Test 4: Allow regular file edit after read
# ============================================================
printf "\n${YELLOW}Test 4: Allow regular file edit after read${NC}\n"
rm -f "$TEST_TMPDIR/symbiote-gateguard-$TEST_SESSION"
rm -f "$TEST_TMPDIR/symbiote-compact-$TEST_SESSION"

# Track the file as read
run_tracker "$TEST_EXISTING_FILE" > /dev/null

OUTPUT=$(run_dispatcher "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$TEST_EXISTING_FILE\",\"old_string\":\"a\",\"new_string\":\"b\"}}")

assert_empty "allows after read without extra output" "$OUTPUT"
assert_not_contains "no config block" "Config Protection" "$OUTPUT"
assert_not_contains "no gateguard block" "GateGuard" "$OUTPUT"

# ============================================================
# Test 5: Dispatcher respects SYMBIOTE_ALLOW_CONFIG_EDIT override
# ============================================================
printf "\n${YELLOW}Test 5: Dispatcher respects SYMBIOTE_ALLOW_CONFIG_EDIT override${NC}\n"
rm -f "$TEST_TMPDIR/symbiote-gateguard-$TEST_SESSION"
rm -f "$TEST_TMPDIR/symbiote-compact-$TEST_SESSION"

# Track the file as read to ensure gateguard doesn't block
run_tracker "/project/.swiftlint.yml" > /dev/null

OUTPUT=$(printf '%s' '{"tool_name":"Edit","tool_input":{"file_path":"/project/.swiftlint.yml","old_string":"a","new_string":"b"}}' | \
  TMPDIR="$TEST_TMPDIR" \
  CLAUDE_SESSION_ID="$TEST_SESSION" \
  HARNESS_TEST_STATE_DIR="$TEST_STATE" \
  SYMBIOTE_HOME="$TEST_TMPDIR" \
  CLAUDE_PROJECT_DIR="/tmp/test-project" \
  SYMBIOTE_ALLOW_CONFIG_EDIT=1 \
  bash "$DISPATCHER_SCRIPT" 2>/dev/null)

assert_empty "override allows config edit without extra output" "$OUTPUT"
assert_not_contains "no config block with override" "Config Protection" "$OUTPUT"

# ============================================================
# Test 6: Dispatcher respects SYMBIOTE_GATEGUARD=0 override
# ============================================================
printf "\n${YELLOW}Test 6: Dispatcher respects SYMBIOTE_GATEGUARD=0 override${NC}\n"
rm -f "$TEST_TMPDIR/symbiote-gateguard-$TEST_SESSION"
rm -f "$TEST_TMPDIR/symbiote-compact-$TEST_SESSION"

OUTPUT=$(printf '%s' "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$TEST_EXISTING_FILE\",\"old_string\":\"a\",\"new_string\":\"b\"}}" | \
  TMPDIR="$TEST_TMPDIR" \
  CLAUDE_SESSION_ID="$TEST_SESSION" \
  HARNESS_TEST_STATE_DIR="$TEST_STATE" \
  SYMBIOTE_HOME="$TEST_TMPDIR" \
  CLAUDE_PROJECT_DIR="/tmp/test-project" \
  SYMBIOTE_GATEGUARD=0 \
  bash "$DISPATCHER_SCRIPT" 2>/dev/null)

assert_empty "gateguard disabled allows unread without extra output" "$OUTPUT"
assert_not_contains "no gateguard block with override" "GateGuard" "$OUTPUT"

# ============================================================
printf "\n${YELLOW}=== Results ===${NC}\n"
printf "Total: %d  Passed: ${GREEN}%d${NC}  Failed: ${RED}%d${NC}\n\n" "$TOTAL" "$PASSED" "$FAILED"

[ "$FAILED" -gt 0 ] && exit 1
printf "${GREEN}All tests passed!${NC}\n"
exit 0
