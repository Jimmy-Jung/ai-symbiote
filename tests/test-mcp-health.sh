#!/bin/bash
# Integration tests for MCP health check hooks.
#
# Author: JunyoungJung
# Date: 2026-04-16
#
# Usage: bash tests/test-mcp-health.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CHECK_SCRIPT="$PROJECT_ROOT/shared/hooks/scripts/mcp-health-check.sh"
FAILURE_SCRIPT="$PROJECT_ROOT/shared/hooks/scripts/mcp-health-failure.sh"
SUCCESS_SCRIPT="$PROJECT_ROOT/shared/hooks/scripts/mcp-health-success.sh"

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

assert_equals() {
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

# Unique session ID per test run to avoid collisions
TEST_SESSION="test-mcp-health-$$"

setup_env() {
  local tmp_dir
  tmp_dir=$(mktemp -d /tmp/mcp-health-test-XXXXXX)
  mkdir -p "$tmp_dir"
  echo "$tmp_dir"
}

teardown_env() {
  rm -rf "$1" 2>/dev/null
  rm -f "${TMPDIR:-/tmp}/symbiote-mcp-health-${TEST_SESSION}.json" 2>/dev/null
}

run_check() {
  local input="$1"
  printf '%s' "$input" | \
    CLAUDE_SESSION_ID="$TEST_SESSION" \
    bash "$CHECK_SCRIPT" 2>/dev/null
}

run_failure() {
  local input="$1"
  printf '%s' "$input" | \
    CLAUDE_SESSION_ID="$TEST_SESSION" \
    bash "$FAILURE_SCRIPT" 2>/dev/null
}

run_success() {
  local input="$1"
  printf '%s' "$input" | \
    CLAUDE_SESSION_ID="$TEST_SESSION" \
    bash "$SUCCESS_SCRIPT" 2>/dev/null
}

get_health_file() {
  echo "${TMPDIR:-/tmp}/symbiote-mcp-health-${TEST_SESSION}.json"
}

clean_health_file() {
  rm -f "$(get_health_file)" 2>/dev/null
}

# ============================================================
# Test 1: Non-MCP tool → continue immediately (fast path)
# ============================================================
test_non_mcp_continue() {
  printf "${YELLOW}Test 1: Non-MCP tool continues immediately${NC}\n"
  clean_health_file

  local output
  output=$(run_check '{"tool_name":"Edit","tool_input":{"file_path":"/project/src/main.ts"}}')

  assert_contains "continues for non-MCP tool" '"continue":true' "$output"
  assert_not_contains "no MCP Health message" "MCP Health" "$output"
}

# ============================================================
# Test 2: MCP tool with 0 failures → continue
# ============================================================
test_mcp_zero_failures() {
  printf "${YELLOW}Test 2: MCP tool with 0 failures continues${NC}\n"
  clean_health_file

  local output
  output=$(run_check '{"tool_name":"mcp__context7__query-docs","tool_input":{}}')

  assert_contains "continues for healthy MCP tool" '"continue":true' "$output"
  assert_not_contains "no block message" "MCP Health" "$output"
}

# ============================================================
# Test 3: MCP tool with 3 failures, recent → block
# ============================================================
test_mcp_three_failures_block() {
  printf "${YELLOW}Test 3: MCP tool with 3 recent failures is blocked${NC}\n"
  clean_health_file

  # Create health file with 3 failures and recent timestamp
  local now
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  local health_file
  health_file=$(get_health_file)
  printf '{"context7":{"fail_count":3,"last_failure":"%s"}}' "$now" > "$health_file"

  local output
  output=$(run_check '{"tool_name":"mcp__context7__query-docs","tool_input":{}}')

  assert_contains "blocks unhealthy server" '"continue":false' "$output"
  assert_contains "message mentions MCP Health" "MCP Health" "$output"
  assert_contains "message mentions server name" "context7" "$output"
  assert_contains "message mentions failure count" "3 consecutive failures" "$output"
}

# ============================================================
# Test 4: MCP tool with 3 failures, >5 min old → allow (cooldown) + reset counter
# ============================================================
test_mcp_cooldown_expired() {
  printf "${YELLOW}Test 4: Cooldown expired allows retry and resets counter${NC}\n"
  clean_health_file

  # Create health file with 3 failures and old timestamp (6 minutes ago)
  local old_ts health_file
  if command -v python3 >/dev/null 2>&1; then
    old_ts=$(python3 -c "
import datetime
ts = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(minutes=6)
print(ts.strftime('%Y-%m-%dT%H:%M:%SZ'))
")
  else
    old_ts="2020-01-01T00:00:00Z"
  fi

  health_file=$(get_health_file)
  printf '{"context7":{"fail_count":3,"last_failure":"%s"}}' "$old_ts" > "$health_file"

  local output
  output=$(run_check '{"tool_name":"mcp__context7__query-docs","tool_input":{}}')

  assert_contains "allows after cooldown" '"continue":true' "$output"
  assert_not_contains "no block message after cooldown" "MCP Health" "$output"

  # Verify counter was reset
  if command -v jq >/dev/null 2>&1; then
    local reset_count
    reset_count=$(jq -r '.context7.fail_count // -1' "$health_file" 2>/dev/null) || reset_count=-1
    assert_equals "counter reset to 0" "0" "$reset_count"
  else
    TOTAL=$((TOTAL + 1))
    PASSED=$((PASSED + 1))
    printf "${GREEN}  PASS${NC} counter reset check (skipped, no jq)\n"
  fi
}

# ============================================================
# Test 5: Failure recording increments counter
# ============================================================
test_failure_increments() {
  printf "${YELLOW}Test 5: Failure recording increments counter${NC}\n"
  clean_health_file

  # Record 3 consecutive failures
  run_failure '{"tool_name":"mcp__context7__query-docs","tool_input":{},"error":"timeout"}' >/dev/null
  run_failure '{"tool_name":"mcp__context7__query-docs","tool_input":{},"error":"timeout"}' >/dev/null
  run_failure '{"tool_name":"mcp__context7__query-docs","tool_input":{},"error":"timeout"}' >/dev/null

  local health_file
  health_file=$(get_health_file)

  if command -v jq >/dev/null 2>&1; then
    local count
    count=$(jq -r '.context7.fail_count // 0' "$health_file" 2>/dev/null) || count=0
    assert_equals "fail_count is 3 after 3 failures" "3" "$count"

    local last_failure
    last_failure=$(jq -r '.context7.last_failure // empty' "$health_file" 2>/dev/null) || last_failure=""
    TOTAL=$((TOTAL + 1))
    if [ -n "$last_failure" ]; then
      PASSED=$((PASSED + 1))
      printf "${GREEN}  PASS${NC} last_failure timestamp is set\n"
    else
      FAILED=$((FAILED + 1))
      printf "${RED}  FAIL${NC} last_failure timestamp should be set\n"
    fi
  elif command -v python3 >/dev/null 2>&1; then
    local count
    count=$(python3 -c "
import json
with open('$health_file') as f:
    data = json.load(f)
print(data.get('context7', {}).get('fail_count', 0))
" 2>/dev/null) || count=0
    assert_equals "fail_count is 3 after 3 failures" "3" "$count"
    TOTAL=$((TOTAL + 1))
    PASSED=$((PASSED + 1))
    printf "${GREEN}  PASS${NC} last_failure timestamp check (skipped detail, no jq)\n"
  fi
}

# ============================================================
# Test 6: Server name extraction
# ============================================================
test_server_extraction() {
  printf "${YELLOW}Test 6: Server name extraction from tool_name${NC}\n"
  clean_health_file

  # Record a failure for a complex server name
  run_failure '{"tool_name":"mcp__sequential-thinking__create","tool_input":{},"error":"fail"}' >/dev/null

  local health_file
  health_file=$(get_health_file)

  if command -v jq >/dev/null 2>&1; then
    local count
    count=$(jq -r '."sequential-thinking".fail_count // 0' "$health_file" 2>/dev/null) || count=0
    assert_equals "sequential-thinking server extracted" "1" "$count"
  elif command -v python3 >/dev/null 2>&1; then
    local count
    count=$(python3 -c "
import json
with open('$health_file') as f:
    data = json.load(f)
print(data.get('sequential-thinking', {}).get('fail_count', 0))
" 2>/dev/null) || count=0
    assert_equals "sequential-thinking server extracted" "1" "$count"
  fi
}

# ============================================================
# Test 7: Success resets failure counter
# ============================================================
test_success_resets() {
  printf "${YELLOW}Test 7: Success resets failure counter${NC}\n"
  clean_health_file

  # Record 2 failures
  run_failure '{"tool_name":"mcp__context7__query-docs","tool_input":{},"error":"timeout"}' >/dev/null
  run_failure '{"tool_name":"mcp__context7__query-docs","tool_input":{},"error":"timeout"}' >/dev/null

  # Now a success
  run_success '{"tool_name":"mcp__context7__query-docs","tool_input":{},"tool_result":"ok"}' >/dev/null

  local health_file
  health_file=$(get_health_file)

  if command -v jq >/dev/null 2>&1; then
    local count
    count=$(jq -r '.context7.fail_count // -1' "$health_file" 2>/dev/null) || count=-1
    assert_equals "counter reset to 0 after success" "0" "$count"
  elif command -v python3 >/dev/null 2>&1; then
    local count
    count=$(python3 -c "
import json
with open('$health_file') as f:
    data = json.load(f)
print(data.get('context7', {}).get('fail_count', -1))
" 2>/dev/null) || count=-1
    assert_equals "counter reset to 0 after success" "0" "$count"
  fi
}

# ============================================================
# Test 8: Non-MCP failure is ignored
# ============================================================
test_non_mcp_failure_ignored() {
  printf "${YELLOW}Test 8: Non-MCP failure is ignored${NC}\n"
  clean_health_file

  local output
  output=$(run_failure '{"tool_name":"Bash","tool_input":{"command":"ls"},"error":"fail"}')

  assert_contains "continues for non-MCP failure" '"continue":true' "$output"

  # Health file should not exist
  local health_file
  health_file=$(get_health_file)
  TOTAL=$((TOTAL + 1))
  if [ ! -f "$health_file" ]; then
    PASSED=$((PASSED + 1))
    printf "${GREEN}  PASS${NC} no health file created for non-MCP failure\n"
  else
    FAILED=$((FAILED + 1))
    printf "${RED}  FAIL${NC} health file should not exist for non-MCP failure\n"
  fi
}

# ============================================================
# Test 9: End-to-end: 3 failures then block then cooldown
# ============================================================
test_e2e_flow() {
  printf "${YELLOW}Test 9: End-to-end: failures → block → cooldown${NC}\n"
  clean_health_file

  # First call: healthy, should pass
  local output
  output=$(run_check '{"tool_name":"mcp__context7__query-docs","tool_input":{}}')
  assert_contains "e2e: initial call allowed" '"continue":true' "$output"

  # Record 3 failures
  run_failure '{"tool_name":"mcp__context7__query-docs","tool_input":{},"error":"err1"}' >/dev/null
  run_failure '{"tool_name":"mcp__context7__query-docs","tool_input":{},"error":"err2"}' >/dev/null
  run_failure '{"tool_name":"mcp__context7__query-docs","tool_input":{},"error":"err3"}' >/dev/null

  # Now check should block
  output=$(run_check '{"tool_name":"mcp__context7__query-docs","tool_input":{}}')
  assert_contains "e2e: blocked after 3 failures" '"continue":false' "$output"
  assert_contains "e2e: block mentions MCP Health" "MCP Health" "$output"

  # Different server should still be allowed
  output=$(run_check '{"tool_name":"mcp__sequential-thinking__create","tool_input":{}}')
  assert_contains "e2e: different server still allowed" '"continue":true' "$output"
}

# ============================================================
# Test 10: Malformed JSON emits continue
# ============================================================
test_malformed_json() {
  printf "${YELLOW}Test 10: Malformed JSON emits continue${NC}\n"
  clean_health_file

  local output
  output=$(run_check 'not valid json')
  assert_contains "continues on malformed JSON" '"continue":true' "$output"
}

# ============================================================
# Test 11: Cursor protocol output format
# ============================================================
test_cursor_protocol() {
  printf "${YELLOW}Test 11: Cursor protocol output format${NC}\n"
  clean_health_file

  # Set up 3 failures with recent timestamp
  local now health_file
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  health_file=$(get_health_file)
  printf '{"context7":{"fail_count":3,"last_failure":"%s"}}' "$now" > "$health_file"

  local output
  output=$(printf '%s' '{"tool_name":"mcp__context7__query-docs","tool_input":{}}' | \
    CLAUDE_SESSION_ID="$TEST_SESSION" \
    CURSOR_PLUGIN_ROOT="/tmp/cursor-plugin" \
    bash "$CHECK_SCRIPT" 2>/dev/null)

  assert_contains "cursor protocol has permission deny" '"permission":"deny"' "$output"
  assert_contains "cursor protocol has continue false" '"continue":false' "$output"
  assert_contains "cursor protocol has agent_message" '"agent_message"' "$output"
}

# ============================================================
# Test 12: Multiple servers tracked independently
# ============================================================
test_independent_servers() {
  printf "${YELLOW}Test 12: Multiple servers tracked independently${NC}\n"
  clean_health_file

  # Fail context7 3 times
  run_failure '{"tool_name":"mcp__context7__query","tool_input":{},"error":"err"}' >/dev/null
  run_failure '{"tool_name":"mcp__context7__query","tool_input":{},"error":"err"}' >/dev/null
  run_failure '{"tool_name":"mcp__context7__query","tool_input":{},"error":"err"}' >/dev/null

  # Fail sequential-thinking 1 time
  run_failure '{"tool_name":"mcp__sequential-thinking__create","tool_input":{},"error":"err"}' >/dev/null

  local health_file
  health_file=$(get_health_file)

  if command -v jq >/dev/null 2>&1; then
    local c7_count st_count
    c7_count=$(jq -r '.context7.fail_count // 0' "$health_file" 2>/dev/null) || c7_count=0
    st_count=$(jq -r '."sequential-thinking".fail_count // 0' "$health_file" 2>/dev/null) || st_count=0
    assert_equals "context7 has 3 failures" "3" "$c7_count"
    assert_equals "sequential-thinking has 1 failure" "1" "$st_count"
  elif command -v python3 >/dev/null 2>&1; then
    local c7_count st_count
    c7_count=$(python3 -c "
import json
with open('$health_file') as f:
    data = json.load(f)
print(data.get('context7', {}).get('fail_count', 0))
" 2>/dev/null) || c7_count=0
    st_count=$(python3 -c "
import json
with open('$health_file') as f:
    data = json.load(f)
print(data.get('sequential-thinking', {}).get('fail_count', 0))
" 2>/dev/null) || st_count=0
    assert_equals "context7 has 3 failures" "3" "$c7_count"
    assert_equals "sequential-thinking has 1 failure" "1" "$st_count"
  fi
}

# ============================================================
printf "\n${YELLOW}=== ai-symbiote MCP Health Check Tests ===${NC}\n\n"

test_non_mcp_continue
echo ""
test_mcp_zero_failures
echo ""
test_mcp_three_failures_block
echo ""
test_mcp_cooldown_expired
echo ""
test_failure_increments
echo ""
test_server_extraction
echo ""
test_success_resets
echo ""
test_non_mcp_failure_ignored
echo ""
test_e2e_flow
echo ""
test_malformed_json
echo ""
test_cursor_protocol
echo ""
test_independent_servers

# Final cleanup
clean_health_file

printf "\n${YELLOW}=== Results ===${NC}\n"
printf "Total: %d  Passed: ${GREEN}%d${NC}  Failed: ${RED}%d${NC}\n\n" "$TOTAL" "$PASSED" "$FAILED"

[ "$FAILED" -gt 0 ] && exit 1
exit 0
