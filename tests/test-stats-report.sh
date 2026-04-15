#!/bin/bash
# Integration tests for stats report script.
#
# Usage: bash tests/test-stats-report.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
STATS_SCRIPT="$PROJECT_ROOT/shared/skills/stats/scripts/stats-report.sh"

PASSED=0
FAILED=0
TOTAL=0

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  TOTAL=$((TOTAL + 1))
  if echo "$haystack" | grep -qF "$needle" 2>/dev/null; then
    PASSED=$((PASSED + 1))
    printf "${GREEN}  PASS${NC} %s\n" "$desc"
  else
    FAILED=$((FAILED + 1))
    printf "${RED}  FAIL${NC} %s\n    needle: %s\n" "$desc" "$needle"
  fi
}

assert_path_missing() {
  local desc="$1" path="$2"
  TOTAL=$((TOTAL + 1))
  if [ ! -e "$path" ]; then
    PASSED=$((PASSED + 1))
    printf "${GREEN}  PASS${NC} %s\n" "$desc"
  else
    FAILED=$((FAILED + 1))
    printf "${RED}  FAIL${NC} %s\n    path still exists: %s\n" "$desc" "$path"
  fi
}

assert_file_contains() {
  local desc="$1" needle="$2" file="$3"
  TOTAL=$((TOTAL + 1))
  if grep -qF "$needle" "$file" 2>/dev/null; then
    PASSED=$((PASSED + 1))
    printf "${GREEN}  PASS${NC} %s\n" "$desc"
  else
    FAILED=$((FAILED + 1))
    printf "${RED}  FAIL${NC} %s\n    file: %s\n    needle: %s\n" "$desc" "$file" "$needle"
  fi
}

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

STATE_DIR="$TMPDIR/state"
mkdir -p "$STATE_DIR/usage-data/skills" "$STATE_DIR/usage-data/commands" "$STATE_DIR/state"

cat > "$STATE_DIR/usage-data/.tracked-since" <<'EOF'
2026-04-01T00:00:00Z
EOF

cat > "$STATE_DIR/usage-data/skills/security" <<'EOF'
3|2026-04-14T10:00:00Z
EOF

cat > "$STATE_DIR/usage-data/skills/setup" <<'EOF'
1|2026-04-13T08:00:00Z
EOF

cat > "$STATE_DIR/usage-data/commands/security" <<'EOF'
4|2026-04-14T10:00:00Z
EOF

cat > "$STATE_DIR/context.md" <<'EOF'
## Project Summary
- Demo project
[Harness #1] Verify test coverage before merge
[Seed #S1] Prefer explicit imports
EOF

cat > "$STATE_DIR/harness-rules.md" <<'EOF'
[Harness #1] Verify test coverage before merge
[Harness #2] Re-run failing integration tests before reporting done
[Seed #S1] Prefer explicit imports
EOF

cat > "$STATE_DIR/harness-log.jsonl" <<'EOF'
{"v":2,"ts":"2026-04-03T10:00:00Z","type":"rule_created","rule_id":1,"file":"tests/a.sh"}
{"v":2,"ts":"2026-04-10T11:00:00Z","type":"rule_created","rule_id":2,"file":"tests/b.sh"}
{"v":2,"ts":"2026-04-12T09:00:00Z","error_type":"loop_verify_fail","file":"tests/a.sh","session_pid":"1"}
{"v":2,"ts":"2026-04-13T09:00:00Z","error_type":"loop_verify_fail","file":"tests/a.sh","session_pid":"1"}
{"v":2,"ts":"2026-04-13T10:00:00Z","type":"rule_prevented","rule_id":1,"file":"tests/a.sh","session_pid":"1"}
{"v":2,"ts":"2026-04-14T10:00:00Z","error_type":"guard_blocked","command":"rm -rf dist","workaround":"remove target","session_pid":"1"}
EOF

cat > "$STATE_DIR/security-log.jsonl" <<'EOF'
{"v":2,"ts":"2026-04-14T09:00:00Z","type":"security","category":"file_scan","file":"src/app.ts","warn_count":2,"warnings":"warn","action":"warned","session_pid":"1"}
{"v":2,"ts":"2026-04-14T09:05:00Z","type":"security","category":"secret_exposure","rule_id":"SEC-003","risk":"CRITICAL","command":"cat .env","action":"blocked","session_pid":"2"}
EOF

echo ""
echo "=== stats-report.sh Tests ==="
echo ""

REPORT_OUTPUT=$(bash "$STATS_SCRIPT" --state-dir "$STATE_DIR" --plugin-root "$PROJECT_ROOT/shared")
assert_contains "report prints usage header" "[Usage Stats] Tracking period:" "$REPORT_OUTPUT"
assert_contains "report includes active security skill" "security" "$REPORT_OUTPUT"
assert_contains "report includes harness section" "[Harness Evolution Metrics]" "$REPORT_OUTPUT"
assert_contains "report includes security telemetry section" "[Security Telemetry]" "$REPORT_OUTPUT"
assert_contains "report summarizes blocked and warned events" "Events: 2  |  Blocked: 1  |  Warned: 1" "$REPORT_OUTPUT"
assert_contains "report includes top security category" "Top categories: file_scan x1, secret_exposure x1" "$REPORT_OUTPUT"
assert_contains "report includes recent blocked security event" "secret_exposure | cat .env" "$REPORT_OUTPUT"
assert_contains "report includes guard blocked summary" "rm -rf dist x1" "$REPORT_OUTPUT"

BASELINE_OUTPUT=$(bash "$STATS_SCRIPT" --baseline --state-dir "$STATE_DIR" --plugin-root "$PROJECT_ROOT/shared")
assert_contains "baseline prints header" "[Harness Baseline] Measured on" "$BASELINE_OUTPUT"
assert_contains "baseline prints repeat rate" "Repeat rate:" "$BASELINE_OUTPUT"
assert_file_contains "baseline file created" "\"repeatRate\"" "$STATE_DIR/state/stats-baseline.json"

RESET_OUTPUT=$(bash "$STATS_SCRIPT" --reset --state-dir "$STATE_DIR" --plugin-root "$PROJECT_ROOT/shared")
assert_contains "reset prints completion" "Tracking data reset complete" "$RESET_OUTPUT"
assert_path_missing "reset removes tracked since" "$STATE_DIR/usage-data/.tracked-since"
assert_path_missing "reset removes stored baseline" "$STATE_DIR/state/stats-baseline.json"

echo ""
echo "=== Results ==="
printf "Passed: %d / %d\n" "$PASSED" "$TOTAL"
if [ "$FAILED" -gt 0 ]; then
  printf "${RED}Failed: %d${NC}\n" "$FAILED"
  exit 1
else
  printf "${GREEN}All tests passed!${NC}\n"
fi
