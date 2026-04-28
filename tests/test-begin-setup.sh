#!/bin/bash
# Integration tests for setup entrypoint.
#
# Usage: bash tests/test-begin-setup.sh
#
# Author: JunyoungJung
# Date: 2026-04-15

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SETUP_ENTRY="$PROJECT_ROOT/shared/skills/setup/scripts/begin-setup.sh"

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

assert_file_exists() {
  local desc="$1" path="$2"
  TOTAL=$((TOTAL + 1))
  if [ -e "$path" ]; then
    PASSED=$((PASSED + 1))
    printf "${GREEN}  PASS${NC} %s\n" "$desc"
  else
    FAILED=$((FAILED + 1))
    printf "${RED}  FAIL${NC} %s\n    path: %s\n" "$desc" "$path"
  fi
}

assert_file_not_exists() {
  local desc="$1" path="$2"
  TOTAL=$((TOTAL + 1))
  if [ ! -e "$path" ]; then
    PASSED=$((PASSED + 1))
    printf "${GREEN}  PASS${NC} %s\n" "$desc"
  else
    FAILED=$((FAILED + 1))
    printf "${RED}  FAIL${NC} %s\n    unexpected path: %s\n" "$desc" "$path"
  fi
}

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

TEST_REPO="$TMPDIR/repo"
PLAN_STATE_DIR="$TMPDIR/plan-state"
APPROVE_STATE_DIR="$TMPDIR/approve-state"
OPT_IN_STATE_DIR="$TMPDIR/opt-in-state"

mkdir -p "$TEST_REPO" "$PLAN_STATE_DIR" "$APPROVE_STATE_DIR" "$OPT_IN_STATE_DIR"
cat > "$TEST_REPO/package.json" <<'EOF'
{
  "name": "setup-entry-test",
  "dependencies": {
    "@supabase/supabase-js": "^2.0.0",
    "react": "^19.0.0"
  }
}
EOF

echo ""
echo "=== begin-setup.sh Tests ==="
echo ""

PLAN_OUTPUT=$(bash "$SETUP_ENTRY" --project-root "$TEST_REPO" --state-dir "$PLAN_STATE_DIR")
assert_contains "plan mode prints setup plan" "[Setup Plan]" "$PLAN_OUTPUT"
assert_contains "plan mode prints rerun hint" "[Setup] Re-run with --approve to execute this plan." "$PLAN_OUTPUT"

APPROVE_OUTPUT=$( \
  SETUP_STORE_MODE=fast \
  CLI_STORE_FORCE_STATUS_SUPABASE=ready \
  bash "$SETUP_ENTRY" --project-root "$TEST_REPO" --state-dir "$APPROVE_STATE_DIR" --approve \
)

assert_contains "approve mode acknowledges execution" "[Setup] Approval received. Executing setup..." "$APPROVE_OUTPUT"
assert_contains "approve mode completes" "[Setup] setup execution complete." "$APPROVE_OUTPUT"
assert_contains "approve mode skips project agent config by default" "[Setup] skipped project agent config (.claude/, .codex/, .gitignore). Re-run with --project-agent-config to create it." "$APPROVE_OUTPUT"
assert_file_not_exists "approve mode does not create claude settings by default" "$TEST_REPO/.claude/settings.json"
assert_file_not_exists "approve mode does not create codex config by default" "$TEST_REPO/.codex/config.toml"
assert_file_not_exists "approve mode does not create gitignore by default" "$TEST_REPO/.gitignore"
assert_file_exists "approve mode creates tracked-since file" "$APPROVE_STATE_DIR/usage-data/.tracked-since"
assert_file_exists "approve mode creates manifest" "$APPROVE_STATE_DIR/manifest.json"

OPT_IN_OUTPUT=$( \
  SETUP_STORE_MODE=fast \
  CLI_STORE_FORCE_STATUS_SUPABASE=ready \
  bash "$SETUP_ENTRY" --project-root "$TEST_REPO" --state-dir "$OPT_IN_STATE_DIR" --project-agent-config --approve \
)

assert_contains "opt-in mode acknowledges execution" "[Setup] Approval received. Executing setup..." "$OPT_IN_OUTPUT"
assert_file_exists "opt-in mode creates claude settings" "$TEST_REPO/.claude/settings.json"
assert_file_exists "opt-in mode creates codex config" "$TEST_REPO/.codex/config.toml"
assert_file_exists "opt-in mode creates gitignore" "$TEST_REPO/.gitignore"
assert_file_exists "opt-in mode creates tracked-since file" "$OPT_IN_STATE_DIR/usage-data/.tracked-since"

echo ""
echo "=== Results ==="
printf "Passed: %d / %d\n" "$PASSED" "$TOTAL"
if [ "$FAILED" -gt 0 ]; then
  printf "${RED}Failed: %d${NC}\n" "$FAILED"
  exit 1
else
  printf "${GREEN}All tests passed!${NC}\n"
fi
