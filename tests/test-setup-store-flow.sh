#!/bin/bash
# Integration test for setup store execution flow.
#
# Usage: bash tests/test-setup-store-flow.sh
# Author: JunyoungJung
# Date: 2026-04-15

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RUNNER="$PROJECT_ROOT/shared/skills/setup/scripts/run-store-setup.sh"

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

TEST_REPO="$TMPDIR/test-repo"
STATE_DIR="$TMPDIR/state"
BOOTSTRAP_STATE_DIR="$TMPDIR/bootstrap-state"
GUIDED_STATE_DIR="$TMPDIR/guided-state"
DRY_RUN_STATE_DIR="$TMPDIR/dry-run-state"

mkdir -p "$TEST_REPO" "$STATE_DIR/state" "$BOOTSTRAP_STATE_DIR/state" "$GUIDED_STATE_DIR/state" "$DRY_RUN_STATE_DIR/state"

cat > "$TEST_REPO/package.json" <<'EOF'
{
  "name": "test-repo",
  "dependencies": {
    "@supabase/supabase-js": "^2.0.0",
    "react": "^19.0.0"
  }
}
EOF

cat > "$STATE_DIR/manifest.json" <<EOF
{
  "path": "$TEST_REPO",
  "project": {
    "languages": ["typescript"]
  },
  "stack": {
    "frameworks": ["react"],
    "packageManager": "npm"
  }
}
EOF

cat > "$GUIDED_STATE_DIR/manifest.json" <<EOF
{
  "path": "$TEST_REPO",
  "project": {
    "languages": ["typescript"]
  },
  "stack": {
    "frameworks": ["react"],
    "packageManager": "npm"
  },
  "plugins": {
    "vercel/react-best-practices": {
      "notes": "preserve me"
    }
  },
  "mcpServers": {
    "supabase": {
      "notes": "keep this"
    }
  }
}
EOF

cp "$STATE_DIR/manifest.json" "$DRY_RUN_STATE_DIR/manifest.json"

cat > "$STATE_DIR/state/cli-covered-mcps.json" <<'EOF'
{
  "coveredMcpIds": ["stale-mcp"],
  "generatedAt": "2026-04-15T00:00:00Z"
}
EOF

echo ""
echo "=== setup store flow Tests ==="
echo ""

OUTPUT=$(CLI_STORE_FORCE_STATUS_SUPABASE=ready bash "$RUNNER" --state-dir "$STATE_DIR" --project-root "$TEST_REPO")

assert_contains "runner starts store flow" "[Setup] Running store recommendations..." "$OUTPUT"
assert_contains "skill-store runs" "[Skill Store] Automatic skill recommendations:" "$OUTPUT"
assert_contains "cli-store runs" "[CLI Store] Automatic CLI recommendations:" "$OUTPUT"
assert_contains "mcp-store runs" "[MCP Store] Automatic MCP recommendations:" "$OUTPUT"
assert_contains "mcp-store reports CLI-covered entry" "covered by CLI" "$OUTPUT"

assert_file_contains "skill-store writes state file" "\"items\"" "$STATE_DIR/state/skill-store-recommendations.json"
assert_file_contains "cli-store writes covered MCP file" "\"supabase\"" "$STATE_DIR/state/cli-covered-mcps.json"
assert_file_contains "mcp-store writes state file" "\"covered\"" "$STATE_DIR/state/mcp-store-recommendations.json"

TOTAL=$((TOTAL + 1))
if grep -qF '"stale-mcp"' "$STATE_DIR/state/cli-covered-mcps.json" 2>/dev/null; then
  FAILED=$((FAILED + 1))
  printf "${RED}  FAIL${NC} stale covered MCP removed on auto refresh\n"
else
  PASSED=$((PASSED + 1))
  printf "${GREEN}  PASS${NC} stale covered MCP removed on auto refresh\n"
fi

BOOTSTRAP_OUTPUT=$(CLI_STORE_FORCE_STATUS_SUPABASE=ready bash "$RUNNER" --state-dir "$BOOTSTRAP_STATE_DIR" --project-root "$TEST_REPO")

assert_contains "runner bootstraps missing manifest" "[Setup] bootstrap manifest created:" "$BOOTSTRAP_OUTPUT"
assert_file_contains "bootstrap manifest created on first setup" "\"projectPath\": \"$TEST_REPO\"" "$BOOTSTRAP_STATE_DIR/manifest.json"
assert_file_contains "bootstrap flow still writes covered MCP file" "\"supabase\"" "$BOOTSTRAP_STATE_DIR/state/cli-covered-mcps.json"

cp "$DRY_RUN_STATE_DIR/manifest.json" "$TMPDIR/dry-run-before.json"
DRY_RUN_OUTPUT=$(CLI_STORE_FORCE_STATUS_GH=not-ready CLI_STORE_FORCE_STATUS_SUPABASE=ready bash "$RUNNER" --state-dir "$DRY_RUN_STATE_DIR" --project-root "$TEST_REPO" --mode dry-run)

assert_contains "dry-run still prints guided summary" "[Setup] Guided setup summary:" "$DRY_RUN_OUTPUT"
assert_contains "dry-run summary keeps ready CLI counts" "1 already ready" "$DRY_RUN_OUTPUT"
assert_contains "dry-run summary keeps CLI-covered MCP counts" "1 covered by CLI" "$DRY_RUN_OUTPUT"
TOTAL=$((TOTAL + 1))
if cmp -s "$DRY_RUN_STATE_DIR/manifest.json" "$TMPDIR/dry-run-before.json"; then
  PASSED=$((PASSED + 1))
  printf "${GREEN}  PASS${NC} dry-run keeps manifest byte-identical\n"
else
  FAILED=$((FAILED + 1))
  printf "${RED}  FAIL${NC} dry-run keeps manifest byte-identical\n"
fi
TOTAL=$((TOTAL + 1))
if [ -f "$DRY_RUN_STATE_DIR/state/setup-store-summary.json" ] || [ -f "$DRY_RUN_STATE_DIR/state/cli-store-recommendations.json" ] || [ -f "$DRY_RUN_STATE_DIR/state/skill-store-recommendations.json" ] || [ -f "$DRY_RUN_STATE_DIR/state/mcp-store-recommendations.json" ]; then
  FAILED=$((FAILED + 1))
  printf "${RED}  FAIL${NC} dry-run does not write state artifacts\n"
else
  PASSED=$((PASSED + 1))
  printf "${GREEN}  PASS${NC} dry-run does not write state artifacts\n"
fi

GUIDED_OUTPUT=$( \
  SETUP_STORE_SKILLS_CHOICE=vercel/react-best-practices \
  SETUP_STORE_CLI_CHOICE=all \
  SETUP_STORE_MCP_CHOICE=supabase \
  CLI_STORE_FORCE_STATUS_SUPABASE=not-ready \
  CLI_STORE_FORCE_INSTALL_CMD_SUPABASE="echo simulated-install-supabase" \
  CLI_STORE_FORCE_STATUS_AFTER_SUPABASE=ready \
  bash "$RUNNER" --state-dir "$GUIDED_STATE_DIR" --project-root "$TEST_REPO" --mode guided \
)

assert_contains "guided mode prints selection summary" "[Setup] Selection summary:" "$GUIDED_OUTPUT"
assert_contains "guided mode applies selected skill" "[Skill Store] React Best Practices recorded for installation sync." "$GUIDED_OUTPUT"
assert_contains "guided mode installs selected CLI" "[CLI Store] Installing Supabase CLI..." "$GUIDED_OUTPUT"
assert_contains "guided mode applies selected MCP" "[MCP Store] Supabase recorded in manifest." "$GUIDED_OUTPUT"
assert_file_contains "guided mode records setup selections" "\"setupSelections\"" "$GUIDED_STATE_DIR/manifest.json"
assert_file_contains "guided mode records selected CLI choice" "\"choice\": \"all\"" "$GUIDED_STATE_DIR/state/setup-store-preferences.json"
assert_file_contains "guided mode records selected MCP ids" "\"supabase\"" "$GUIDED_STATE_DIR/state/setup-store-preferences.json"
assert_file_contains "guided mode writes plugins section" "\"plugins\"" "$GUIDED_STATE_DIR/manifest.json"
assert_file_contains "guided mode writes selected skill repo" "\"vercel/react-best-practices\"" "$GUIDED_STATE_DIR/manifest.json"
assert_file_contains "guided mode preserves plugin details" "\"notes\": \"preserve me\"" "$GUIDED_STATE_DIR/manifest.json"
assert_file_contains "guided mode writes mcpServers section" "\"mcpServers\"" "$GUIDED_STATE_DIR/manifest.json"
assert_file_contains "guided mode writes selected mcp id" "\"supabase\"" "$GUIDED_STATE_DIR/manifest.json"
assert_file_contains "guided mode preserves mcp details" "\"notes\": \"keep this\"" "$GUIDED_STATE_DIR/manifest.json"

echo ""
echo "=== Results ==="
printf "Passed: %d / %d\n" "$PASSED" "$TOTAL"
if [ "$FAILED" -gt 0 ]; then
  printf "${RED}Failed: %d${NC}\n" "$FAILED"
  exit 1
else
  printf "${GREEN}All tests passed!${NC}\n"
fi
