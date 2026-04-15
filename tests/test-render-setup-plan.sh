#!/bin/bash
# Integration tests for setup plan renderer.
#
# Usage: bash tests/test-render-setup-plan.sh
#
# Author: JunyoungJung
# Date: 2026-04-15

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RENDER_SCRIPT="$PROJECT_ROOT/shared/skills/setup/scripts/render-setup-plan.sh"

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

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

STATE_DIR="$TMPDIR/state"
mkdir -p "$STATE_DIR/state"
cat > "$STATE_DIR/manifest.json" <<'EOF'
{
  "projectPath": "/tmp/test-project"
}
EOF

echo ""
echo "=== render-setup-plan.sh Tests ==="
echo ""

OUTPUT=$(bash "$RENDER_SCRIPT" \
  --project-root "/tmp/test-project" \
  --state-dir "$STATE_DIR" \
  --platform "claude-cli, codex" \
  --optional-item "messenger bridge setup")

assert_contains "prints setup plan header" "[Setup Plan]" "$OUTPUT"
assert_contains "renders project root" "Project root: /tmp/test-project" "$OUTPUT"
assert_contains "renders missing state summary" "Missing state: context.md, usage-data/" "$OUTPUT"
assert_contains "renders platform summary" "Platform hints: claude-cli, codex" "$OUTPUT"
assert_contains "renders custom optional item" "messenger bridge setup" "$OUTPUT"
assert_contains "keeps approval line" "Reply with approval before execution." "$OUTPUT"

echo ""
echo "=== Results ==="
printf "Passed: %d / %d\n" "$PASSED" "$TOTAL"
if [ "$FAILED" -gt 0 ]; then
  printf "${RED}Failed: %d${NC}\n" "$FAILED"
  exit 1
else
  printf "${GREEN}All tests passed!${NC}\n"
fi
