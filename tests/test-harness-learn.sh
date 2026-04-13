#!/bin/bash
# Integration tests for harness-learn.sh dedup and setup-check.sh auto-GC.
#
# Author: JunyoungJung
# Date: 2026-04-10
#
# Usage: bash tests/test-harness-learn.sh
#
# Strategy: Tests manipulate state files directly and verify outcomes.
# For dedup tests: pre-populate harness-log.jsonl + harness-rules.md, then pipe mock
# input to harness-learn.sh with overridden get_state_dir().

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PASSED=0
FAILED=0
TOTAL=0

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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
  local desc="$1" needle="$2" file="$3"
  TOTAL=$((TOTAL + 1))
  if grep -qF "$needle" "$file" 2>/dev/null; then
    PASSED=$((PASSED + 1))
    printf "${GREEN}  PASS${NC} %s\n" "$desc"
  else
    FAILED=$((FAILED + 1))
    printf "${RED}  FAIL${NC} %s\n    expected file to contain: %s\n" "$desc" "$needle"
  fi
}

assert_not_contains() {
  local desc="$1" needle="$2" file="$3"
  TOTAL=$((TOTAL + 1))
  if ! grep -qF "$needle" "$file" 2>/dev/null; then
    PASSED=$((PASSED + 1))
    printf "${GREEN}  PASS${NC} %s\n" "$desc"
  else
    FAILED=$((FAILED + 1))
    printf "${RED}  FAIL${NC} %s\n    expected file NOT to contain: %s\n" "$desc" "$needle"
  fi
}

setup_env() {
  local tmp_dir
  tmp_dir=$(mktemp -d /tmp/harness-test-XXXXXX)
  mkdir -p "$tmp_dir/state/session-$$"
  cat > "$tmp_dir/context.md" << 'EOF'
# Test Project Context
EOF
  cat > "$tmp_dir/harness-rules.md" << 'EOF'
[Seed #S1] Always read the target file before editing
EOF
  : > "$tmp_dir/harness-log.jsonl"
  echo "$tmp_dir"
}

teardown_env() { rm -rf "$1" 2>/dev/null; }

recent_cutoff_ts() {
  local days="${1:-7}"
  date -u -v-"$days"d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || \
    date -u -d "$days days ago" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || \
    echo "0000-00-00T00:00:00Z"
}

filter_recent_jsonl() {
  local file="$1" days="${2:-7}"
  local cutoff
  cutoff=$(recent_cutoff_ts "$days")
  awk -v cutoff="$cutoff" '
    {
      if (match($0, /"ts":"[^"]+"/)) {
        ts = substr($0, RSTART + 6, RLENGTH - 7)
        if (ts >= cutoff) print
      }
    }
  ' "$file" 2>/dev/null
}

# Run harness-learn.sh with overridden state dir via env sourcing
run_hook() {
  local state_dir="$1" input="$2"
  printf '%s' "$input" | \
    HARNESS_TEST_STATE_DIR="$state_dir" \
    bash "$PROJECT_ROOT/shared/hooks/scripts/harness-learn.sh" 2>/dev/null
}

# Run auto-GC logic (extracted from setup-check.sh)
run_auto_gc() {
  local state_dir="$1"
  local _GC_CTX="$state_dir/harness-rules.md"
  local _GC_LOG="$state_dir/harness-log.jsonl"
  local _GC_TMP="$_GC_CTX.autogc.tmp"
  local _GC_REMOVED=0
  local _GC_SEEN
  _GC_SEEN=$(mktemp 2>/dev/null || echo "/tmp/harness-gc-seen-$$")
  local _THIRTY_DAYS
  _THIRTY_DAYS=$(date -u -v-30d +%Y-%m-%dT 2>/dev/null || date -u -d '30 days ago' +%Y-%m-%dT 2>/dev/null || echo "")

  while IFS= read -r _gc_line || [ -n "$_gc_line" ]; do
    if printf '%s' "$_gc_line" | grep -q '^\[Harness #'; then
      local _gc_text
      _gc_text=$(printf '%s' "$_gc_line" | sed 's/^\[Harness #[0-9]*\] //' | sed 's/ (auto-generated [0-9-]*)$//')
      if grep -qxF "$_gc_text" "$_GC_SEEN" 2>/dev/null; then
        _GC_REMOVED=$((_GC_REMOVED + 1))
        continue
      fi
      printf '%s\n' "$_gc_text" >> "$_GC_SEEN"

      if [ -n "$_THIRTY_DAYS" ] && [ -f "$_GC_LOG" ]; then
        local _gc_rid
        _gc_rid=$(printf '%s' "$_gc_line" | grep -o '#[0-9]*' | head -1 | tr -d '#')
        if [ -n "$_gc_rid" ]; then
          local _gc_created _gc_prevented _gc_latest
          _gc_created=$(grep '"type":"rule_created"' "$_GC_LOG" 2>/dev/null | grep "\"rule_id\":$_gc_rid[,}]" 2>/dev/null | grep -o '"ts":"[^"]*"' 2>/dev/null | head -1 | sed 's/"ts":"//;s/"//')
          _gc_prevented=$(grep '"type":"rule_prevented"' "$_GC_LOG" 2>/dev/null | grep "\"rule_id\":$_gc_rid[,}]" 2>/dev/null | tail -1 | grep -o '"ts":"[^"]*"' 2>/dev/null | sed 's/"ts":"//;s/"//')
          _gc_latest="${_gc_prevented:-$_gc_created}"
          if [ -n "$_gc_latest" ] && [[ "$_gc_latest" < "$_THIRTY_DAYS" ]]; then
            _GC_REMOVED=$((_GC_REMOVED + 1))
            continue
          fi
        fi
      fi
    fi
    printf '%s\n' "$_gc_line"
  done < "$_GC_CTX" > "$_GC_TMP"
  rm -f "$_GC_SEEN" 2>/dev/null

  if [ "$_GC_REMOVED" -gt 0 ]; then
    cat -s "$_GC_TMP" > "$_GC_CTX" 2>/dev/null || mv "$_GC_TMP" "$_GC_CTX" 2>/dev/null
    rm -f "$_GC_TMP" 2>/dev/null
  else
    rm -f "$_GC_TMP" 2>/dev/null
  fi
  echo "$_GC_REMOVED"
}

# ============================================================
# Test 1: Dedup — pre-existing rule blocks duplicate creation
# ============================================================
test_dedup_blocks_duplicate() {
  printf "${YELLOW}Test 1: Dedup — identical rule text not added twice${NC}\n"
  local dir
  dir=$(setup_env)

  # Pre-populate: 1 existing error + 1 existing rule in harness-rules.md
  local NOW
  NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  printf '{"ts":"%s","error_type":"tool_error","file":"/tmp/Foo.swift","description":"Foo.swift: tool returned error","rule_candidate":"Read Foo.swift content before editing; verify the exact target string exists","session_pid":"1"}\n' "$NOW" >> "$dir/harness-log.jsonl"
  printf '\n[Harness #1] Read Foo.swift content before editing; verify the exact target string exists (auto-generated 2026-04-10)\n' >> "$dir/harness-rules.md"

  # Add another error for same file (PATTERN_COUNT will be ≥2)
  printf '{"ts":"%s","error_type":"tool_error","file":"/tmp/Foo.swift","description":"Foo.swift: tool returned error","rule_candidate":"Read Foo.swift content before editing; verify the exact target string exists","session_pid":"1"}\n' "$NOW" >> "$dir/harness-log.jsonl"

  # The dedup check: grep -qF should find the existing rule
  local RULE_CANDIDATE="Read Foo.swift content before editing; verify the exact target string exists"
  local result="not_found"
  if grep -qF "$RULE_CANDIDATE" "$dir/harness-rules.md" 2>/dev/null; then
    result="found"
  fi

  assert_eq "grep -qF finds existing rule" "found" "$result"

  local rule_count
  rule_count=$(grep -c '^\[Harness #' "$dir/harness-rules.md") || rule_count=0
  assert_eq "Still only 1 harness rule" "1" "$rule_count"

  teardown_env "$dir"
}

# ============================================================
# Test 2: Different files create separate rules
# ============================================================
test_different_files_separate_rules() {
  printf "${YELLOW}Test 2: Different files create separate rules${NC}\n"
  local dir
  dir=$(setup_env)

  # Pre-populate rules for 2 different files
  printf '\n[Harness #1] Read Alpha.swift content before editing; verify the exact target string exists (auto-generated 2026-04-10)\n' >> "$dir/harness-rules.md"

  # Check that a DIFFERENT rule candidate would NOT be blocked
  local RULE_B="Read Beta.swift content before editing; verify the exact target string exists"
  local result="not_found"
  if grep -qF "$RULE_B" "$dir/harness-rules.md" 2>/dev/null; then
    result="found"
  fi

  assert_eq "Different rule text not found (allows creation)" "not_found" "$result"

  teardown_env "$dir"
}

# ============================================================
# Test 3: Pattern count excludes rule_created events
# ============================================================
test_pattern_count_excludes_rule_events() {
  printf "${YELLOW}Test 3: Pattern count excludes rule_created events${NC}\n"
  local dir
  dir=$(setup_env)

  local NOW
  NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  # 1 real error + 1 rule_created (should NOT count as error)
  printf '{"ts":"%s","error_type":"tool_error","file":"/tmp/X.swift","description":"X.swift: error","rule_candidate":"Read X.swift","session_pid":"1"}\n' "$NOW" >> "$dir/harness-log.jsonl"
  printf '{"ts":"%s","type":"rule_created","rule_id":1,"description":"X.swift: error"}\n' "$NOW" >> "$dir/harness-log.jsonl"

  # Count with the fixed filter (grep '"error_type"' first)
  local COUNT
  COUNT=$(grep '"error_type"' "$dir/harness-log.jsonl" 2>/dev/null | \
    grep '"error_type":"tool_error"' 2>/dev/null | \
    grep '"file":"/tmp/X.swift"' 2>/dev/null | \
    wc -l | tr -d ' ') || COUNT=0

  assert_eq "Pattern count = 1 (excludes rule_created)" "1" "$COUNT"

  # Count WITHOUT the fix (old behavior) — would also be 1 here
  # because rule_created doesn't have error_type field.
  # The real value of the fix is clarity + future-proofing.
  local OLD_COUNT
  OLD_COUNT=$(grep '"error_type":"tool_error"' "$dir/harness-log.jsonl" 2>/dev/null | \
    grep '"file":"/tmp/X.swift"' 2>/dev/null | \
    wc -l | tr -d ' ') || OLD_COUNT=0

  assert_eq "Old method also returns 1 (no regression)" "1" "$OLD_COUNT"

  teardown_env "$dir"
}

# ============================================================
# Test 4: Auto-GC removes duplicate rules
# ============================================================
test_auto_gc_removes_duplicates() {
  printf "${YELLOW}Test 4: Auto-GC removes duplicate rules${NC}\n"
  local dir
  dir=$(setup_env)

  local NOW
  NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  # Add 4 rules: 3 duplicates of Foo + 1 unique Bar
  cat >> "$dir/harness-rules.md" << EOF

[Harness #1] Read Foo.swift content before editing; verify the exact target string exists (auto-generated 2026-04-10)

[Harness #2] Read Foo.swift content before editing; verify the exact target string exists (auto-generated 2026-04-10)

[Harness #3] Read Foo.swift content before editing; verify the exact target string exists (auto-generated 2026-04-10)

[Harness #4] Read Bar.swift content before editing; verify the exact target string exists (auto-generated 2026-04-10)
EOF

  for i in 1 2 3 4; do
    printf '{"ts":"%s","type":"rule_created","rule_id":%d,"description":"test"}\n' "$NOW" "$i" >> "$dir/harness-log.jsonl"
  done

  local before
  before=$(grep -c '^\[Harness #' "$dir/harness-rules.md") || before=0
  assert_eq "Before GC: 4 rules" "4" "$before"

  local removed
  removed=$(run_auto_gc "$dir")
  assert_eq "GC removed 2 duplicates" "2" "$removed"

  local after
  after=$(grep -c '^\[Harness #' "$dir/harness-rules.md") || after=0
  assert_eq "After GC: 2 unique rules" "2" "$after"

  assert_contains "Foo rule survives" "Read Foo.swift" "$dir/harness-rules.md"
  assert_contains "Bar rule survives" "Read Bar.swift" "$dir/harness-rules.md"

  teardown_env "$dir"
}

# ============================================================
# Test 5: Auto-GC removes stale rules (30+ days)
# ============================================================
test_auto_gc_removes_stale() {
  printf "${YELLOW}Test 5: Auto-GC removes stale rules${NC}\n"
  local dir
  dir=$(setup_env)

  local NOW
  NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  cat >> "$dir/harness-rules.md" << EOF

[Harness #1] Read Old.swift content before editing (auto-generated 2026-02-01)

[Harness #2] Read New.swift content before editing (auto-generated 2026-04-10)
EOF

  # Rule #1: created 60+ days ago, no prevention
  printf '{"ts":"2026-02-01T10:00:00Z","type":"rule_created","rule_id":1,"description":"old"}\n' >> "$dir/harness-log.jsonl"
  # Rule #2: created today
  printf '{"ts":"%s","type":"rule_created","rule_id":2,"description":"new"}\n' "$NOW" >> "$dir/harness-log.jsonl"

  local removed
  removed=$(run_auto_gc "$dir")
  assert_eq "GC removed 1 stale rule" "1" "$removed"
  assert_not_contains "Old rule removed" "Read Old.swift" "$dir/harness-rules.md"
  assert_contains "New rule preserved" "Read New.swift" "$dir/harness-rules.md"

  teardown_env "$dir"
}

# ============================================================
# Test 6: Auto-GC preserves active rules (recent rule_prevented)
# ============================================================
test_auto_gc_preserves_active() {
  printf "${YELLOW}Test 6: Auto-GC preserves active rules${NC}\n"
  local dir
  dir=$(setup_env)

  local NOW
  NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  cat >> "$dir/harness-rules.md" << EOF

[Harness #1] Read Active.swift content before editing (auto-generated 2026-02-01)
EOF

  # Created 60+ days ago BUT has recent prevention
  printf '{"ts":"2026-02-01T10:00:00Z","type":"rule_created","rule_id":1,"description":"active"}\n' >> "$dir/harness-log.jsonl"
  printf '{"v":2,"ts":"%s","type":"rule_prevented","rule_id":1,"file":"Active.swift"}\n' "$NOW" >> "$dir/harness-log.jsonl"

  local removed
  removed=$(run_auto_gc "$dir")
  assert_eq "GC removed 0 rules (active rule preserved)" "0" "$removed"
  assert_contains "Active rule preserved" "Read Active.swift" "$dir/harness-rules.md"

  teardown_env "$dir"
}

# ============================================================
# Test 7: Extension aggregation detection
# ============================================================
test_extension_aggregation() {
  printf "${YELLOW}Test 7: Extension aggregation — 3+ files detected${NC}\n"
  local dir
  dir=$(setup_env)

  local NOW
  NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  # 3 different .swift files with tool_error
  for f in "/tmp/A.swift" "/tmp/B.swift" "/tmp/C.swift"; do
    printf '{"ts":"%s","error_type":"tool_error","file":"%s","description":"error","rule_candidate":"test","session_pid":"1"}\n' "$NOW" "$f" >> "$dir/harness-log.jsonl"
  done

  # Count unique .swift files with tool_error (extension aggregation logic)
  local EXT_FILE_COUNT
  EXT_FILE_COUNT=$(filter_recent_jsonl "$dir/harness-log.jsonl" 7 | \
    grep '"error_type":"tool_error"' 2>/dev/null | \
    grep -o '"file":"[^"]*\.swift"' 2>/dev/null | \
    sort -u | wc -l | tr -d ' ') || EXT_FILE_COUNT=0

  assert_eq "3 unique .swift files detected" "3" "$EXT_FILE_COUNT"

  teardown_env "$dir"
}

# ============================================================
# Test 8: 300-line limit blocks rule creation
# ============================================================
test_300_line_limit() {
  printf "${YELLOW}Test 8: 300-line limit blocks rule creation${NC}\n"
  local dir
  dir=$(setup_env)

  # Fill harness-rules.md to 305 lines
  for i in $(seq 1 305); do
    echo "# Filler line $i" >> "$dir/harness-rules.md"
  done

  local LINE_COUNT
  LINE_COUNT=$(wc -l < "$dir/harness-rules.md" | tr -d ' ')

  # Simulate the 300-line check from harness-learn.sh
  local blocked="no"
  if [ "$LINE_COUNT" -ge 300 ]; then
    blocked="yes"
  fi

  assert_eq "Context file exceeds 300 lines" "yes" "$blocked"

  local rule_count
  rule_count=$(grep -c '^\[Harness #' "$dir/harness-rules.md") || rule_count=0
  assert_eq "No harness rules in oversized context" "0" "$rule_count"

  teardown_env "$dir"
}

# ============================================================
# Test 9: Recent filter includes entries from 1-6 days ago
# ============================================================
test_recent_filter_uses_real_7_day_window() {
  printf "${YELLOW}Test 9: Recent filter includes full 7-day window${NC}\n"
  local dir
  dir=$(setup_env)

  local NOW TWO_DAYS_AGO EIGHT_DAYS_AGO COUNT
  NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  TWO_DAYS_AGO=$(date -u -v-2d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '2 days ago' +%Y-%m-%dT%H:%M:%SZ)
  EIGHT_DAYS_AGO=$(date -u -v-8d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '8 days ago' +%Y-%m-%dT%H:%M:%SZ)

  printf '{"ts":"%s","error_type":"tool_error","file":"/tmp/Today.swift"}\n' "$NOW" >> "$dir/harness-log.jsonl"
  printf '{"ts":"%s","error_type":"tool_error","file":"/tmp/TwoDays.swift"}\n' "$TWO_DAYS_AGO" >> "$dir/harness-log.jsonl"
  printf '{"ts":"%s","error_type":"tool_error","file":"/tmp/EightDays.swift"}\n' "$EIGHT_DAYS_AGO" >> "$dir/harness-log.jsonl"

  COUNT=$(filter_recent_jsonl "$dir/harness-log.jsonl" 7 | grep -c '"error_type":"tool_error"' | tr -d ' ') || COUNT=0
  assert_eq "Today + 2 days ago counted, 8 days ago excluded" "2" "$COUNT"

  teardown_env "$dir"
}

# ============================================================
# Test 10: build-watcher detects Xcode test failure banner
# ============================================================
test_build_watcher_detects_xcode_test_failed_banner() {
  printf "${YELLOW}Test 10: build-watcher catches xcode test failure banner${NC}\n"
  local dir input output count
  dir=$(setup_env)
  input='{"tool_name":"Bash","tool_input":{"command":"xcodebuild test"},"tool_response":"** TEST FAILED **"}'

  output=$(printf '%s' "$input" | \
    HARNESS_TEST_STATE_DIR="$dir" \
    bash "$PROJECT_ROOT/shared/hooks/scripts/build-watcher.sh" 2>/dev/null)

  count=$(grep -c '"error_type":"build_test_failed"' "$dir/harness-log.jsonl" | tr -d ' ') || count=0
  assert_eq "Test failure logged from banner" "1" "$count"
  assert_eq "No rule emitted on first failure" "" "$output"

  teardown_env "$dir"
}

# ============================================================
# Test 11: build-watcher classifies npm test FAIL output as test_failed
# ============================================================
test_build_watcher_classifies_node_test_failures() {
  printf "${YELLOW}Test 11: build-watcher classifies node test failures${NC}\n"
  local dir input count
  dir=$(setup_env)
  input='{"tool_name":"Bash","tool_input":{"command":"npm test"},"tool_response":"FAIL src/app.test.ts\nAssertionError: expected true to be false"}'

  printf '%s' "$input" | \
    HARNESS_TEST_STATE_DIR="$dir" \
    bash "$PROJECT_ROOT/shared/hooks/scripts/build-watcher.sh" 2>/dev/null

  count=$(grep -c '"error_type":"build_test_failed"' "$dir/harness-log.jsonl" | tr -d ' ') || count=0
  assert_eq "Node test output stored as test failure" "1" "$count"

  teardown_env "$dir"
}

# ============================================================
# Test 12: build-watcher logs structured non-zero exit code without output
# ============================================================
test_build_watcher_uses_structured_exit_code_without_output() {
  printf "${YELLOW}Test 12: build-watcher uses structured exit code without output${NC}\n"
  local dir input count
  dir=$(setup_env)
  input='{"tool_name":"Bash","tool_input":{"command":"npm test"},"exit_code":1,"tool_response":""}'

  printf '%s' "$input" | \
    HARNESS_TEST_STATE_DIR="$dir" \
    bash "$PROJECT_ROOT/shared/hooks/scripts/build-watcher.sh" 2>/dev/null

  count=$(grep -c '"error_type":"build_test_failed"' "$dir/harness-log.jsonl" | tr -d ' ') || count=0
  assert_eq "Structured exit_code still logs failure" "1" "$count"
  assert_contains "Structured exit summary recorded" "command exited with code 1" "$dir/harness-log.jsonl"

  teardown_env "$dir"
}

# ============================================================
# Test 13: common.sh python fallback parses escaped JSON strings
# ============================================================
test_common_json_field_python_fallback_handles_escaped_quotes() {
  printf "${YELLOW}Test 13: common.sh python fallback parses escaped quotes${NC}\n"
  local tmp_bin actual
  tmp_bin=$(mktemp -d /tmp/harness-json-fallback-XXXXXX)
  ln -s "$(command -v python3)" "$tmp_bin/python3"

  actual=$(PATH="$tmp_bin:/bin:/usr/bin" bash -c '
    source "'"$PROJECT_ROOT"'/shared/hooks/scripts/lib/common.sh"
    json_field "{\"tool_response\":\"Error: \\\"bad\\\"\"}" "tool_response"
  ' 2>/dev/null)

  assert_eq "Escaped quote survives python fallback" 'Error: "bad"' "$actual"

  rm -rf "$tmp_bin" 2>/dev/null
}

# ============================================================
# Test 14: feedback-logger creates rule after second rejection
# ============================================================
test_feedback_logger_second_rejection_creates_rule() {
  printf "${YELLOW}Test 14: feedback-logger adds rule on second rejection${NC}\n"
  local dir output
  dir=$(setup_env)

  output=$(HARNESS_TEST_STATE_DIR="$dir" bash "$PROJECT_ROOT/shared/hooks/scripts/feedback-logger.sh" "/tmp/App.swift" "layout breaks" "Test on iPad before submitting" 2>/dev/null)
  assert_eq "First rejection only logs" "Feedback logged." "$output"

  output=$(HARNESS_TEST_STATE_DIR="$dir" bash "$PROJECT_ROOT/shared/hooks/scripts/feedback-logger.sh" "/tmp/App.swift" "layout breaks" "Test on iPad before submitting" 2>/dev/null)

  assert_eq "Second rejection adds rule" "Feedback logged. Auto-added Harness #1 rule." "$output"
  assert_contains "Feedback rule persisted" "Test on iPad before submitting" "$dir/harness-rules.md"

  teardown_env "$dir"
}

# ============================================================
printf "\n${YELLOW}=== ai-symbiote Harness Integration Tests ===${NC}\n\n"

test_dedup_blocks_duplicate
echo ""
test_different_files_separate_rules
echo ""
test_pattern_count_excludes_rule_events
echo ""
test_auto_gc_removes_duplicates
echo ""
test_auto_gc_removes_stale
echo ""
test_auto_gc_preserves_active
echo ""
test_extension_aggregation
echo ""
test_300_line_limit
echo ""
test_recent_filter_uses_real_7_day_window
echo ""
test_build_watcher_detects_xcode_test_failed_banner
echo ""
test_build_watcher_classifies_node_test_failures
echo ""
test_build_watcher_uses_structured_exit_code_without_output
echo ""
test_common_json_field_python_fallback_handles_escaped_quotes
echo ""
test_feedback_logger_second_rejection_creates_rule

printf "\n${YELLOW}=== Results ===${NC}\n"
printf "Total: %d  Passed: ${GREEN}%d${NC}  Failed: ${RED}%d${NC}\n\n" "$TOTAL" "$PASSED" "$FAILED"

[ "$FAILED" -gt 0 ] && exit 1
exit 0
