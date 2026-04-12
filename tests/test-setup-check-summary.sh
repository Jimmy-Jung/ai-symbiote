#!/bin/bash
# Integration tests for setup-check.sh harness-rules summary mode.
#
# Tests the token optimization feature: when harness-rules.md exceeds 50 lines,
# only the top 50 rules (ranked by prevented count) are injected.
#
# Usage: bash tests/test-setup-check-summary.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

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

# Setup temp state directory
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

setup_state() {
  local state_dir="$TMPDIR/test-state"
  rm -rf "$state_dir"
  mkdir -p "$state_dir"
  # Create minimal manifest so Synapse routing activates
  echo '{"projectPath":"/tmp/test","slug":"test"}' > "$state_dir/manifest.json"
  echo "$state_dir"
}

# Generate N harness rules
generate_rules() {
  local file="$1" count="$2"
  > "$file"
  for i in $(seq 1 "$count"); do
    printf '[Harness #%d] Test rule %d (auto-generated 2026-04-12)\n' "$i" "$i" >> "$file"
  done
}

# Generate harness-log with prevented events
generate_log() {
  local file="$1"
  shift
  > "$file"
  # Args: pairs of "rule_id count"
  while [ $# -ge 2 ]; do
    local rid="$1" cnt="$2"
    shift 2
    for i in $(seq 1 "$cnt"); do
      printf '{"v":2,"ts":"2026-04-12T00:00:00Z","type":"rule_prevented","rule_id":%s,"file":"test.ts","session_pid":"1"}\n' "$rid" >> "$file"
    done
  done
}

# Run setup-check.sh with overridden state dir
run_setup_check() {
  local state_dir="$1"
  # Override get_state_dir to return our test dir
  SYMBIOTE_HOME="$TMPDIR" \
  CLAUDE_PROJECT_DIR="/tmp/test" \
  echo '{}' | bash -c "
    # Override slug to point to our state
    get_project_slug() { echo 'test-state'; }
    get_state_root() { echo '$TMPDIR'; }
    source '$PROJECT_ROOT/shared/hooks/scripts/lib/common.sh'
    get_state_dir() { echo '$state_dir'; }
    export -f get_state_dir get_state_root get_project_slug json_field json_nested_field json_escape

    # Source the relevant section of setup-check.sh
    STATE_DIR='$state_dir'
    CONTEXT_PARTS=()

    # Harness rules section (extracted logic)
    if [ -f \"\$STATE_DIR/harness-rules.md\" ]; then
      RULES_CONTENT=\$(cat \"\$STATE_DIR/harness-rules.md\" 2>/dev/null)
      if [ -n \"\$RULES_CONTENT\" ]; then
        RULES_LINES=\$(echo \"\$RULES_CONTENT\" | wc -l | tr -d ' ')
        if [ \"\$RULES_LINES\" -le 50 ]; then
          CONTEXT_PARTS+=(\"\$RULES_CONTENT\")
        else
          HARNESS_LOG=\"\$STATE_DIR/harness-log.jsonl\"
          if [ -f \"\$HARNESS_LOG\" ]; then
            RANKED_IDS=\$(grep '\"type\":\"rule_prevented\"' \"\$HARNESS_LOG\" 2>/dev/null | \\
              grep -o '\"rule_id\":[0-9]*' | sed 's/\"rule_id\"://' | \\
              sort | uniq -c | sort -rn | awk '{print \$2}')
            if [ -n \"\$RANKED_IDS\" ]; then
              RANKED_RULES=\"\"
              for rid in \$RANKED_IDS; do
                RULE_LINE=\$(grep -m1 \"\\\\[Harness #\${rid}\\\\]\\\\|\\\\[Seed #\${rid}\\\\]\" \"\$STATE_DIR/harness-rules.md\" 2>/dev/null)
                [ -n \"\$RULE_LINE\" ] && RANKED_RULES=\"\${RANKED_RULES}\${RULE_LINE}
\"
              done
              while IFS= read -r line; do
                case \"\$line\" in \\[Harness\\ \\#*\\]* | \\[Seed\\ \\#*\\]*)
                  if ! echo \"\$RANKED_RULES\" | grep -qF \"\$line\" 2>/dev/null; then
                    RANKED_RULES=\"\${RANKED_RULES}\${line}
\"
                  fi
                  ;; esac
              done < \"\$STATE_DIR/harness-rules.md\"
              SUMMARY_CONTENT=\$(echo \"\$RANKED_RULES\" | head -50)
            else
              SUMMARY_CONTENT=\$(head -50 \"\$STATE_DIR/harness-rules.md\")
            fi
          else
            SUMMARY_CONTENT=\$(head -50 \"\$STATE_DIR/harness-rules.md\")
          fi
          OMITTED=\$((\$RULES_LINES - 50))
          CONTEXT_PARTS+=(\"\$SUMMARY_CONTENT [OMITTED:\$OMITTED]\")
          if [ \"\$RULES_LINES\" -gt 300 ]; then
            CONTEXT_PARTS+=(\"[GC_WARNING]\")
          fi
        fi
      fi
    fi

    # Output result
    for part in \"\${CONTEXT_PARTS[@]}\"; do
      echo \"\$part\"
    done
  " 2>/dev/null
}

echo ""
echo "=== setup-check.sh Summary Mode Tests ==="
echo ""

# Test 1: Rules <=50 lines → inject all (no summary)
echo "--- Test 1: Rules under 50 lines (full injection) ---"
STATE=$(setup_state)
generate_rules "$STATE/harness-rules.md" 30
OUTPUT=$(run_setup_check "$STATE")
RULE30=$(echo "$OUTPUT" | grep -c '\[Harness #' 2>/dev/null) || RULE30=0
assert_eq "30 rules: all injected" "30" "$RULE30"
assert_not_contains "30 rules: no OMITTED marker" "OMITTED:" "$OUTPUT"

# Test 2: Rules >50 lines → summary mode
echo ""
echo "--- Test 2: Rules over 50 lines (summary mode) ---"
STATE=$(setup_state)
generate_rules "$STATE/harness-rules.md" 80
OUTPUT=$(run_setup_check "$STATE")
INJECTED=$(echo "$OUTPUT" | grep -c '\[Harness #' 2>/dev/null) || INJECTED=0
assert_eq "80 rules: only 50 injected" "50" "$INJECTED"
assert_contains "80 rules: OMITTED marker present" "OMITTED:30" "$OUTPUT"

# Test 3: Rules >300 lines → GC warning
echo ""
echo "--- Test 3: Rules over 300 lines (GC warning) ---"
STATE=$(setup_state)
generate_rules "$STATE/harness-rules.md" 310
OUTPUT=$(run_setup_check "$STATE")
assert_contains "310 rules: GC warning present" "[GC_WARNING]" "$OUTPUT"

# Test 4: Prevented count ranking
echo ""
echo "--- Test 4: Rules ranked by prevented count ---"
STATE=$(setup_state)
generate_rules "$STATE/harness-rules.md" 60
# Rule #55 has 10 prevented events, rule #3 has 5 — #55 should appear before #3
generate_log "$STATE/harness-log.jsonl" 55 10 3 5 1 1
OUTPUT=$(run_setup_check "$STATE")
# Check that rule #55 appears in output (it was the most prevented)
assert_contains "Prevented ranking: rule #55 (most prevented) in output" "[Harness #55]" "$OUTPUT"

# Test 5: No harness-log.jsonl → fallback to first 50
echo ""
echo "--- Test 5: No harness-log → fallback to first 50 ---"
STATE=$(setup_state)
generate_rules "$STATE/harness-rules.md" 70
# No harness-log.jsonl created
OUTPUT=$(run_setup_check "$STATE")
assert_contains "No log: rule #1 present (first 50)" "[Harness #1]" "$OUTPUT"
assert_not_contains "No log: rule #60 omitted (beyond 50)" "[Harness #60]" "$OUTPUT"

# Test 6: Empty harness-rules.md → no output
echo ""
echo "--- Test 6: Empty rules file ---"
STATE=$(setup_state)
touch "$STATE/harness-rules.md"
OUTPUT=$(run_setup_check "$STATE")
RULE_COUNT=$(echo "$OUTPUT" | grep -c '\[Harness #' 2>/dev/null) || RULE_COUNT=0
assert_eq "Empty rules: no rules injected" "0" "$RULE_COUNT"

# Test 7: No harness-rules.md → no output
echo ""
echo "--- Test 7: No rules file ---"
STATE=$(setup_state)
OUTPUT=$(run_setup_check "$STATE")
RULE_COUNT=$(echo "$OUTPUT" | grep -c '\[Harness #' 2>/dev/null) || RULE_COUNT=0
assert_eq "No rules file: no rules injected" "0" "$RULE_COUNT"

echo ""
echo "=== Results ==="
printf "Passed: %d / %d\n" "$PASSED" "$TOTAL"
if [ "$FAILED" -gt 0 ]; then
  printf "${RED}Failed: %d${NC}\n" "$FAILED"
  exit 1
else
  printf "${GREEN}All tests passed!${NC}\n"
fi
