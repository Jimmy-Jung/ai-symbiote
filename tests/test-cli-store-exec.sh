#!/bin/bash
# Integration tests for cli-store executor.
#
# Usage: bash tests/test-cli-store-exec.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CLI_STORE_SCRIPT="$PROJECT_ROOT/shared/skills/cli-store/scripts/cli-store.sh"

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
mkdir -p "$STATE_DIR/state"

cat > "$STATE_DIR/manifest.json" <<'EOF'
{
  "cliTools": {
    "semgrep": {
      "cmd": "semgrep",
      "usage": "inactive",
      "reason": "custom detail"
    }
  },
  "project": { "languages": ["typescript"] },
  "stack": { "frameworks": ["react"] }
}
EOF

echo ""
echo "=== cli-store.sh Tests ==="
echo ""

DRY_RUN_OUTPUT=$(CLI_STORE_STATE_DIR="$STATE_DIR" CLI_STORE_FORCE_PM=brew CLI_STORE_FORCE_STATUS_GITLEAKS=not-ready bash "$CLI_STORE_SCRIPT" --dry-run gitleaks)
assert_contains "dry-run reports installable tool" "Gitleaks is installable" "$DRY_RUN_OUTPUT"
assert_contains "dry-run prints brew command" "brew install gitleaks" "$DRY_RUN_OUTPUT"

READY_OUTPUT=$(CLI_STORE_STATE_DIR="$STATE_DIR" CLI_STORE_FORCE_STATUS_SEMGREP=ready bash "$CLI_STORE_SCRIPT" semgrep)
assert_contains "ready tool acknowledged" "Semgrep CLI is already ready." "$READY_OUTPUT"
assert_file_contains "manifest cliTools updated" "\"semgrep\"" "$STATE_DIR/manifest.json"
assert_file_contains "existing cli detail preserved usage" "\"usage\": \"inactive\"" "$STATE_DIR/manifest.json"
assert_file_contains "existing cli detail preserved reason" "\"reason\": \"custom detail\"" "$STATE_DIR/manifest.json"
assert_file_contains "covered MCP file updated" "\"semgrep\"" "$STATE_DIR/state/cli-covered-mcps.json"

EXEC_OUTPUT=$(CLI_STORE_STATE_DIR="$STATE_DIR" CLI_STORE_FORCE_PM=brew CLI_STORE_FORCE_STATUS_GITLEAKS=not-ready CLI_STORE_FORCE_INSTALL_CMD_GITLEAKS="echo simulated-install-gitleaks" CLI_STORE_FORCE_STATUS_AFTER_GITLEAKS=ready bash "$CLI_STORE_SCRIPT" gitleaks)
assert_contains "execute mode runs install path" "Installing Gitleaks..." "$EXEC_OUTPUT"
assert_contains "execute mode reaches ready state" "Gitleaks installed and ready." "$EXEC_OUTPUT"

AUTO_OUTPUT=$(CLI_STORE_STATE_DIR="$STATE_DIR" bash "$CLI_STORE_SCRIPT" --auto)
assert_contains "auto mode prints recommendation header" "Automatic CLI recommendations:" "$AUTO_OUTPUT"

echo ""
echo "=== Results ==="
printf "Passed: %d / %d\n" "$PASSED" "$TOTAL"
if [ "$FAILED" -gt 0 ]; then
  printf "${RED}Failed: %d${NC}\n" "$FAILED"
  exit 1
else
  printf "${GREEN}All tests passed!${NC}\n"
fi
