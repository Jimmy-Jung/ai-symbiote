#!/bin/bash
# Integration tests for setup/evolve manifest security config helpers.
#
# Usage: bash tests/test-manifest-security-config.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SETUP_HELPER="$PROJECT_ROOT/shared/skills/setup/scripts/manifest-defaults.sh"
EVOLVE_HELPER="$PROJECT_ROOT/shared/skills/evolve/scripts/manifest-merge.sh"

PASSED=0
FAILED=0
TOTAL=0

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

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

MANIFEST_PATH="$TMPDIR/manifest.json"
PATCH_PATH="$TMPDIR/patch.json"

cat > "$MANIFEST_PATH" <<'EOF'
{
  "projectPath": "/tmp/test-project",
  "agentPlatforms": ["claude"],
  "project": { "name": "demo" }
}
EOF

echo ""
echo "=== manifest security config Tests ==="
echo ""

bash "$SETUP_HELPER" --manifest "$MANIFEST_PATH" >/dev/null
assert_file_contains "setup helper adds codex platform" "\"codex\"" "$MANIFEST_PATH"
assert_file_contains "setup helper adds security block" "\"security\"" "$MANIFEST_PATH"
assert_file_contains "setup helper sets sessionSummaryLevel auto" "\"sessionSummaryLevel\": \"auto\"" "$MANIFEST_PATH"

cat > "$PATCH_PATH" <<'EOF'
{
  "stack": { "frameworks": ["react"] },
  "project": { "type": "web-app" }
}
EOF

bash "$EVOLVE_HELPER" --manifest "$MANIFEST_PATH" --patch "$PATCH_PATH" >/dev/null
assert_file_contains "evolve helper merges new stack fields" "\"frameworks\": [" "$MANIFEST_PATH"
assert_file_contains "evolve helper preserves security sessionSummaryLevel" "\"sessionSummaryLevel\": \"auto\"" "$MANIFEST_PATH"
assert_file_contains "evolve helper preserves both agent platforms" "\"claude\"" "$MANIFEST_PATH"
assert_file_contains "evolve helper preserves both agent platforms codex" "\"codex\"" "$MANIFEST_PATH"

cat > "$PATCH_PATH" <<'EOF'
{
  "security": { "sessionSummaryLevel": "verbose" }
}
EOF

bash "$EVOLVE_HELPER" --manifest "$MANIFEST_PATH" --patch "$PATCH_PATH" >/dev/null
assert_file_contains "evolve helper allows explicit override" "\"sessionSummaryLevel\": \"verbose\"" "$MANIFEST_PATH"

echo ""
echo "=== Results ==="
printf "Passed: %d / %d\n" "$PASSED" "$TOTAL"
if [ "$FAILED" -gt 0 ]; then
  printf "${RED}Failed: %d${NC}\n" "$FAILED"
  exit 1
else
  printf "${GREEN}All tests passed!${NC}\n"
fi
