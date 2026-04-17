#!/bin/bash
# Integration tests for the Security OS Phase 2 baseline scanner.
#
# Usage: bash tests/test-security-scan.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCAN_SCRIPT="$PROJECT_ROOT/shared/skills/security/scripts/security-scan.sh"

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

assert_file_contains_regex() {
  local desc="$1" pattern="$2" file="$3"
  TOTAL=$((TOTAL + 1))
  if grep -qE -- "$pattern" "$file" 2>/dev/null; then
    PASSED=$((PASSED + 1))
    printf "${GREEN}  PASS${NC} %s\n" "$desc"
  else
    FAILED=$((FAILED + 1))
    printf "${RED}  FAIL${NC} %s\n    file: %s\n    pattern: %s\n" "$desc" "$file" "$pattern"
  fi
}

assert_file_contains() {
  local desc="$1" needle="$2" file="$3"
  TOTAL=$((TOTAL + 1))
  if grep -qF -- "$needle" "$file" 2>/dev/null; then
    PASSED=$((PASSED + 1))
    printf "${GREEN}  PASS${NC} %s\n" "$desc"
  else
    FAILED=$((FAILED + 1))
    printf "${RED}  FAIL${NC} %s\n    file: %s\n    needle: %s\n" "$desc" "$file" "$needle"
  fi
}

assert_file_not_contains() {
  local desc="$1" needle="$2" file="$3"
  TOTAL=$((TOTAL + 1))
  if grep -qF -- "$needle" "$file" 2>/dev/null; then
    FAILED=$((FAILED + 1))
    printf "${RED}  FAIL${NC} %s\n    file: %s\n    unexpected: %s\n" "$desc" "$file" "$needle"
  else
    PASSED=$((PASSED + 1))
    printf "${GREEN}  PASS${NC} %s\n" "$desc"
  fi
}

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

PROJECT_DIR="$TMPDIR/demo"
STATE_DIR="$TMPDIR/state"
FAKE_BIN="$TMPDIR/bin"
FAKE_CAPTURE_DIR="$TMPDIR/fake-capture"
mkdir -p "$PROJECT_DIR/src" "$PROJECT_DIR/.github/workflows" "$PROJECT_DIR/Pods" "$STATE_DIR" "$FAKE_BIN" "$FAKE_CAPTURE_DIR"

cat > "$PROJECT_DIR/.env" <<'EOF'
OPENAI_API_KEY=sk-real-secret-value
EOF

cat > "$PROJECT_DIR/src/app.ts" <<'EOF'
const API_KEY = "supersecretapikey123456";
const query = "SELECT * FROM users WHERE id = " + userId;
element.innerHTML = userHtml;
EOF

cat > "$PROJECT_DIR/Dockerfile" <<'EOF'
FROM node:20
WORKDIR /app
COPY . .
CMD ["node", "server.js"]
EOF

cat > "$PROJECT_DIR/Pods/generated.cache" <<'EOF'
generated
EOF
chmod 666 "$PROJECT_DIR/Pods/generated.cache"

cat > "$PROJECT_DIR/context.md" <<'EOF'
## Project Summary
- Demo project
EOF

OUTPUT=$(SECURITY_SCAN_FORCE_GITLEAKS_STATUS=not-installed SECURITY_SCAN_FORCE_SEMGREP_STATUS=not-installed bash "$SCAN_SCRIPT" scan \
  --project-root "$PROJECT_DIR" \
  --state-dir "$STATE_DIR" \
  --context-file "$PROJECT_DIR/context.md" \
  --install-hints off)

echo ""
echo "=== security-scan.sh Tests ==="
echo ""

assert_contains "scan prints score" "Score:" "$OUTPUT"
assert_contains "scan prints top risks" "Top risks:" "$OUTPUT"
assert_file_contains "baseline file created" "\"score\":" "$STATE_DIR/security-baseline.json"
assert_file_contains "baseline records .env finding" "\"category\":\"env_secret\"" "$STATE_DIR/security-baseline.json"
assert_file_contains "baseline records hardcoded secret" "\"category\":\"hardcoded_secret\"" "$STATE_DIR/security-baseline.json"
assert_file_contains "baseline stores recommendations" "\"recommendations\":" "$STATE_DIR/security-baseline.json"
assert_file_contains "baseline recommends gitleaks" "\"tool\":\"gitleaks\"" "$STATE_DIR/security-baseline.json"
assert_file_contains "baseline recommends semgrep" "\"tool\":\"semgrep\"" "$STATE_DIR/security-baseline.json"
assert_file_contains "recommendation state file created" "\"source\":\"security-scan\"" "$STATE_DIR/state/security-tool-recommendations.json"
assert_file_contains "context.md updated with security block" "## Security Baseline" "$PROJECT_DIR/context.md"
assert_file_contains "context.md includes command hint" "/security scan" "$PROJECT_DIR/context.md"

cat > "$STATE_DIR/security-log.jsonl" <<'EOF'
{"v":2,"ts":"2026-04-14T09:00:00Z","type":"security","category":"file_scan","file":"src/app.ts","warn_count":2,"warnings":"[SEC-W01/HIGH] Hardcoded secret","action":"warned","session_pid":"111"}
{"v":2,"ts":"2026-04-14T09:05:00Z","type":"security","category":"secret_exposure","rule_id":"SEC-003","risk":"CRITICAL","command":"cat .env","action":"blocked","session_pid":"222"}
EOF

STATUS_OUTPUT=$(bash "$SCAN_SCRIPT" status \
  --project-root "$PROJECT_DIR" \
  --state-dir "$STATE_DIR" \
  --context-file "$PROJECT_DIR/context.md")

assert_contains "status reads existing baseline" "[Security] Current baseline" "$STATUS_OUTPUT"
assert_contains "status includes severity counts" "Critical:" "$STATUS_OUTPUT"
assert_contains "status includes recent activity summary" "Recent activity: blocked=1 | warned=1" "$STATUS_OUTPUT"
assert_contains "status includes recent blocked event" "secret_exposure | cat .env" "$STATUS_OUTPUT"
assert_contains "status replays pending recommendations" "Pending tool recommendations:" "$STATUS_OUTPUT"
assert_file_contains "status syncs context with recent activity" "Recent security activity: blocked=1 | warned=1 | latest=2026-04-14T09:05:00Z" "$PROJECT_DIR/context.md"

ACTIVE_OUTPUT=$(SECURITY_SCAN_FORCE_GITLEAKS_STATUS=not-installed SECURITY_SCAN_FORCE_SEMGREP_STATUS=not-installed bash "$SCAN_SCRIPT" scan \
  --project-root "$PROJECT_DIR" \
  --state-dir "$STATE_DIR" \
  --context-file "$PROJECT_DIR/context.md" \
  --install-hints active)

assert_contains "active scan prints install recommendations" "Recommended next tools:" "$ACTIVE_OUTPUT"
assert_contains "active scan prints gitleaks command" "brew install gitleaks" "$ACTIVE_OUTPUT"
assert_contains "active scan includes recent activity summary" "Recent activity: blocked=1 | warned=1" "$ACTIVE_OUTPUT"
assert_file_not_contains "world-writable scan skips Pods artifacts" "Pods/generated.cache" "$STATE_DIR/security-baseline.json"

INSTALL_OUTPUT=$(CLI_STORE_FORCE_PM=brew CLI_STORE_FORCE_STATUS_GITLEAKS=not-ready CLI_STORE_FORCE_STATUS_SEMGREP=not-ready bash "$SCAN_SCRIPT" install-tools \
  --project-root "$PROJECT_DIR" \
  --state-dir "$STATE_DIR" \
  --context-file "$PROJECT_DIR/context.md")

assert_contains "install-tools announces handoff" "Installing recommended tools via cli-store:" "$INSTALL_OUTPUT"
assert_contains "install-tools hands off gitleaks" "gitleaks" "$INSTALL_OUTPUT"
assert_contains "install-tools uses cli-store dry-run" "After install, rerun: /ai-symbiote:cli-store gitleaks" "$INSTALL_OUTPUT"

EXEC_INSTALL_OUTPUT=$(CLI_STORE_FORCE_PM=brew CLI_STORE_FORCE_STATUS_GITLEAKS=not-ready CLI_STORE_FORCE_STATUS_SEMGREP=not-ready CLI_STORE_FORCE_INSTALL_CMD_GITLEAKS="echo simulate-gitleaks-install" CLI_STORE_FORCE_INSTALL_CMD_SEMGREP="echo simulate-semgrep-install" CLI_STORE_FORCE_STATUS_AFTER_GITLEAKS=ready CLI_STORE_FORCE_STATUS_AFTER_SEMGREP=ready bash "$SCAN_SCRIPT" install-tools \
  --project-root "$PROJECT_DIR" \
  --state-dir "$STATE_DIR" \
  --context-file "$PROJECT_DIR/context.md" \
  --execute)

assert_contains "install-tools execute runs real handoff" "Installing Gitleaks..." "$EXEC_INSTALL_OUTPUT"
assert_contains "install-tools execute completes" "[Security] Installation handoff complete." "$EXEC_INSTALL_OUTPUT"

cat > "$FAKE_BIN/gitleaks" <<'EOF'
#!/bin/bash
set -e
args_file="${FAKE_CAPTURE_DIR:?}/gitleaks-args.txt"
config_copy="${FAKE_CAPTURE_DIR:?}/gitleaks-config.toml"
printf '%s\n' "$@" > "$args_file"
report_path=""
config_path=""
prev=""
for arg in "$@"; do
  if [ "$prev" = "--report-path" ]; then
    report_path="$arg"
  elif [ "$prev" = "--config" ]; then
    config_path="$arg"
  fi
  prev="$arg"
done
if [ -n "$config_path" ] && [ -f "$config_path" ]; then
  cp "$config_path" "$config_copy"
fi
sleep "${FAKE_GITLEAKS_SLEEP:-0}"
if [ -n "$report_path" ] && [ "${FAKE_GITLEAKS_WRITE_REPORT:-true}" = "true" ]; then
  printf '[]\n' > "$report_path"
fi
exit "${FAKE_GITLEAKS_EXIT_CODE:-0}"
EOF
chmod +x "$FAKE_BIN/gitleaks"

cat > "$FAKE_BIN/semgrep" <<'EOF'
#!/bin/bash
set -e
args_file="${FAKE_CAPTURE_DIR:?}/semgrep-args.txt"
printf '%s\n' "$@" > "$args_file"
report_path=""
prev=""
for arg in "$@"; do
  if [ "$prev" = "--output" ]; then
    report_path="$arg"
  fi
  prev="$arg"
done
sleep "${FAKE_SEMGREP_SLEEP:-0}"
if [ -n "$report_path" ]; then
  printf '{"results":[]}\n' > "$report_path"
fi
exit "${FAKE_SEMGREP_EXIT_CODE:-0}"
EOF
chmod +x "$FAKE_BIN/semgrep"

FAKE_OUTPUT=$(PATH="$FAKE_BIN:$PATH" FAKE_CAPTURE_DIR="$FAKE_CAPTURE_DIR" FAKE_GITLEAKS_SLEEP=2 FAKE_SEMGREP_SLEEP=2 SECURITY_SCAN_TIMEOUT_SECONDS=5 SECURITY_SCAN_HEARTBEAT_SECONDS=1 bash "$SCAN_SCRIPT" scan \
  --project-root "$PROJECT_DIR" \
  --state-dir "$STATE_DIR" \
  --context-file "$PROJECT_DIR/context.md" \
  --install-hints off 2>&1)

assert_contains "heartbeat prints gitleaks progress" "gitleaks scanning..." "$FAKE_OUTPUT"
assert_contains "heartbeat prints semgrep progress" "semgrep scanning..." "$FAKE_OUTPUT"
assert_file_contains "semgrep excludes Tuist" "--exclude" "$FAKE_CAPTURE_DIR/semgrep-args.txt"
assert_file_contains "semgrep excludes Tuist value" "Tuist" "$FAKE_CAPTURE_DIR/semgrep-args.txt"
assert_file_contains "semgrep excludes xcframework value" "*.xcframework" "$FAKE_CAPTURE_DIR/semgrep-args.txt"
assert_file_contains_regex "gitleaks temp config has Tuist allowlist" "Tuist" "$FAKE_CAPTURE_DIR/gitleaks-config.toml"
assert_file_contains_regex "gitleaks temp config has framework allowlist" "xcframework" "$FAKE_CAPTURE_DIR/gitleaks-config.toml"

TIMEOUT_OUTPUT=$(PATH="$FAKE_BIN:$PATH" FAKE_CAPTURE_DIR="$FAKE_CAPTURE_DIR" FAKE_GITLEAKS_SLEEP=3 FAKE_SEMGREP_SLEEP=0 SECURITY_SCAN_TIMEOUT_SECONDS=1 SECURITY_SCAN_HEARTBEAT_SECONDS=1 bash "$SCAN_SCRIPT" scan \
  --project-root "$PROJECT_DIR" \
  --state-dir "$STATE_DIR" \
  --context-file "$PROJECT_DIR/context.md" \
  --install-hints off 2>&1)

assert_contains "timeout scan still completes with summary" "[Security] Baseline scan complete" "$TIMEOUT_OUTPUT"
assert_file_contains "baseline records gitleaks timeout status" "\"gitleaks\": \"timeout\"" "$STATE_DIR/security-baseline.json"

echo ""
echo "=== Results ==="
printf "Passed: %d / %d\n" "$PASSED" "$TOTAL"
if [ "$FAILED" -gt 0 ]; then
  printf "${RED}Failed: %d${NC}\n" "$FAILED"
  exit 1
else
  printf "${GREEN}All tests passed!${NC}\n"
fi
