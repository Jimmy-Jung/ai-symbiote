#!/bin/bash
# Integration tests for setup-check.sh security summary injection.
#
# Usage: bash tests/test-setup-check-security.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SETUP_CHECK_SCRIPT="$PROJECT_ROOT/shared/hooks/scripts/setup-check.sh"

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

assert_file_contains() {
  local desc="$1" needle="$2" file_path="$3"
  TOTAL=$((TOTAL + 1))
  if grep -qF "$needle" "$file_path" 2>/dev/null; then
    PASSED=$((PASSED + 1))
    printf "${GREEN}  PASS${NC} %s\n" "$desc"
  else
    FAILED=$((FAILED + 1))
    printf "${RED}  FAIL${NC} %s\n    needle: %s\n    file: %s\n" "$desc" "$needle" "$file_path"
  fi
}

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

STATE_DIR="$TMPDIR/state"
mkdir -p "$STATE_DIR/state"

cat > "$STATE_DIR/manifest.json" <<'EOF'
{
  "projectPath": "/tmp/test-project",
  "project": { "name": "demo", "type": "app", "languages": ["typescript"] },
  "stack": { "packageManager": "npm", "frameworks": ["react"] }
}
EOF

cat > "$STATE_DIR/context.md" <<'EOF'
## Project Summary
- Demo project
EOF

cat > "$STATE_DIR/security-baseline.json" <<'EOF'
{
  "scan_date": "2026-04-15T09:00:00Z",
  "score": 72,
  "summary": { "critical": 1, "high": 2, "medium": 1, "info": 0 }
}
EOF

cat > "$STATE_DIR/security-log.jsonl" <<'EOF'
{"v":2,"ts":"2026-04-15T09:10:00Z","type":"security","category":"file_scan","file":"src/app.ts","warn_count":1,"action":"warned","session_pid":"1"}
{"v":2,"ts":"2026-04-15T09:12:00Z","type":"security","category":"secret_exposure","rule_id":"SEC-003","risk":"CRITICAL","command":"cat .env","action":"blocked","session_pid":"2"}
EOF

cat > "$STATE_DIR/state/security-tool-recommendations.json" <<'EOF'
{
  "generatedAt": "2026-04-15T09:00:00Z",
  "source": "security-scan",
  "score": 72,
  "recommendations": [
    { "tool": "gitleaks", "skillHint": "/ai-symbiote:cli-store gitleaks" },
    { "tool": "semgrep", "skillHint": "/ai-symbiote:cli-store semgrep" },
    { "tool": "trivy", "skillHint": "/ai-symbiote:cli-store trivy" }
  ]
}
EOF

echo ""
echo "=== setup-check.sh Security Summary Tests ==="
echo ""

OUTPUT=$(HARNESS_TEST_STATE_DIR="$STATE_DIR" bash "$SETUP_CHECK_SCRIPT")

assert_contains "setup-check returns continue json" "\"continue\":true" "$OUTPUT"
assert_contains "injects compact security summary" "[Security] score=72/100 | C:1 H:2 M:1 I:0 | activity b=1 w=1 latest=secret_exposure @ cat .env | pending=gitleaks, semgrep +1 more. Run /security status for details." "$OUTPUT"
assert_contains "injects context excerpt with pointer" "[Symbiote Context]" "$OUTPUT"
assert_contains "context has file pointer" "Full details: Read" "$OUTPUT"
assert_file_contains "setup-check self-heals agentPlatforms" "\"agentPlatforms\": [" "$STATE_DIR/manifest.json"
assert_file_contains "setup-check adds claude platform" "\"claude\"" "$STATE_DIR/manifest.json"
assert_file_contains "setup-check adds codex platform" "\"codex\"" "$STATE_DIR/manifest.json"
assert_file_contains "setup-check adds cursor platform" "\"cursor\"" "$STATE_DIR/manifest.json"
assert_file_contains "setup-check defaults security summary level" "\"sessionSummaryLevel\": \"auto\"" "$STATE_DIR/manifest.json"

CURSOR_OUTPUT=$(HARNESS_TEST_STATE_DIR="$STATE_DIR" CURSOR_PLUGIN_ROOT="/tmp/cursor-plugin" bash "$SETUP_CHECK_SCRIPT")
assert_contains "cursor setup-check returns permission allow" "\"permission\":\"allow\"" "$CURSOR_OUTPUT"
assert_contains "cursor setup-check returns additional_context" "\"additional_context\":\"" "$CURSOR_OUTPUT"
assert_contains "cursor setup-check returns agent_message" "\"agent_message\":\"" "$CURSOR_OUTPUT"

cat > "$STATE_DIR/security-baseline.json" <<'EOF'
{
  "scan_date": "2026-04-15T11:00:00Z",
  "score": 96,
  "summary": { "critical": 0, "high": 0, "medium": 1, "info": 0 }
}
EOF

cat > "$STATE_DIR/security-log.jsonl" <<'EOF'
{"v":2,"ts":"2026-04-15T11:05:00Z","type":"security","category":"file_scan","file":"src/app.ts","warn_count":1,"action":"warned","session_pid":"3"}
EOF

LOW_RISK_OUTPUT=$(HARNESS_TEST_STATE_DIR="$STATE_DIR" bash "$SETUP_CHECK_SCRIPT")

assert_contains "low risk summary keeps score" "[Security] score=96/100 | C:0 H:0 M:1 I:0 | last_scan=2026-04-15T11:00:00Z. Run /security status for details." "$LOW_RISK_OUTPUT"
TOTAL=$((TOTAL + 1))
if echo "$LOW_RISK_OUTPUT" | grep -qF "pending=" 2>/dev/null; then
  FAILED=$((FAILED + 1))
  printf "${RED}  FAIL${NC} low risk summary hides pending tools\n    found: pending=\n"
else
  PASSED=$((PASSED + 1))
  printf "${GREEN}  PASS${NC} low risk summary hides pending tools\n"
fi
TOTAL=$((TOTAL + 1))
if echo "$LOW_RISK_OUTPUT" | grep -qF "activity b=" 2>/dev/null; then
  FAILED=$((FAILED + 1))
  printf "${RED}  FAIL${NC} low risk summary hides activity details\n    found: activity b=\n"
else
  PASSED=$((PASSED + 1))
  printf "${GREEN}  PASS${NC} low risk summary hides activity details\n"
fi

cat > "$STATE_DIR/manifest.json" <<'EOF'
{
  "projectPath": "/tmp/test-project",
  "project": { "name": "demo", "type": "app", "languages": ["typescript"] },
  "stack": { "packageManager": "npm", "frameworks": ["react"] },
  "security": { "sessionSummaryLevel": "verbose" }
}
EOF

VERBOSE_OUTPUT=$(HARNESS_TEST_STATE_DIR="$STATE_DIR" bash "$SETUP_CHECK_SCRIPT")
assert_contains "verbose summary always shows activity" "activity b=0 w=1 latest=file_scan @ src/app.ts" "$VERBOSE_OUTPUT"
assert_contains "verbose summary always shows pending tools" "pending=gitleaks, semgrep +1 more" "$VERBOSE_OUTPUT"

cat > "$STATE_DIR/manifest.json" <<'EOF'
{
  "projectPath": "/tmp/test-project",
  "project": { "name": "demo", "type": "app", "languages": ["typescript"] },
  "stack": { "packageManager": "npm", "frameworks": ["react"] },
  "security": { "sessionSummaryLevel": "quiet" }
}
EOF

QUIET_OUTPUT=$(HARNESS_TEST_STATE_DIR="$STATE_DIR" bash "$SETUP_CHECK_SCRIPT")
assert_contains "quiet summary keeps minimal score line" "[Security] score=96/100 | C:0 H:0 M:1 I:0 | last_scan=2026-04-15T11:00:00Z. Run /security status for details." "$QUIET_OUTPUT"
TOTAL=$((TOTAL + 1))
if echo "$QUIET_OUTPUT" | grep -qF "pending=" 2>/dev/null; then
  FAILED=$((FAILED + 1))
  printf "${RED}  FAIL${NC} quiet summary hides pending tools\n    found: pending=\n"
else
  PASSED=$((PASSED + 1))
  printf "${GREEN}  PASS${NC} quiet summary hides pending tools\n"
fi
TOTAL=$((TOTAL + 1))
if echo "$QUIET_OUTPUT" | grep -qF "activity b=" 2>/dev/null; then
  FAILED=$((FAILED + 1))
  printf "${RED}  FAIL${NC} quiet summary hides activity details\n    found: activity b=\n"
else
  PASSED=$((PASSED + 1))
  printf "${GREEN}  PASS${NC} quiet summary hides activity details\n"
fi

rm -f "$STATE_DIR/manifest.json"
NO_MANIFEST_OUTPUT=$(HARNESS_TEST_STATE_DIR="$STATE_DIR" bash "$SETUP_CHECK_SCRIPT")
assert_contains "missing manifest guides setup in plan mode" "[Symbiote] manifest.json not found. Run setup in plan mode first to initialize the project." "$NO_MANIFEST_OUTPUT"
assert_contains "missing manifest points to setup entrypoint" "Use shared/skills/setup/scripts/begin-setup.sh for the entrypoint; without --approve it prints the Setup Plan via render-setup-plan.sh and setup-plan.md before any execution." "$NO_MANIFEST_OUTPUT"

echo ""
echo "=== Results ==="
printf "Passed: %d / %d\n" "$PASSED" "$TOTAL"
if [ "$FAILED" -gt 0 ]; then
  printf "${RED}Failed: %d${NC}\n" "$FAILED"
  exit 1
else
  printf "${GREEN}All tests passed!${NC}\n"
fi
