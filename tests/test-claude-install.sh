#!/bin/bash
# Regression test for Claude installer path guidance.
#
# Usage: bash tests/test-claude-install.sh
# Author: JunyoungJung
# Date: 2026-04-15

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

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

assert_not_contains() {
  local desc="$1" needle="$2" haystack="$3"
  TOTAL=$((TOTAL + 1))
  if echo "$haystack" | grep -qF "$needle" 2>/dev/null; then
    FAILED=$((FAILED + 1))
    printf "${RED}  FAIL${NC} %s\n    unexpected: %s\n" "$desc" "$needle"
  else
    PASSED=$((PASSED + 1))
    printf "${GREEN}  PASS${NC} %s\n" "$desc"
  fi
}

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

FIXTURE_ROOT="$TMPDIR/fixture-repo"
BUNDLE_ROOT="$TMPDIR/fixture-bundle"

rsync -a \
  --exclude '.git' \
  --exclude 'dist' \
  --exclude 'plugins' \
  "$PROJECT_ROOT/" "$FIXTURE_ROOT/"

echo ""
echo "=== Claude installer Tests ==="
echo ""

OUTPUT=$(CLAUDE_PLUGIN_BUNDLE_DIR="$BUNDLE_ROOT" bash "$FIXTURE_ROOT/platforms/claude/install.sh")

assert_contains "installer prints dynamic marketplace root" "Claude에서 /plugin marketplace add $FIXTURE_ROOT" "$OUTPUT"
assert_contains "installer prints bundle destination" "bundle: $BUNDLE_ROOT" "$OUTPUT"
assert_contains "installer prints marketplace root summary" "marketplace root: $FIXTURE_ROOT" "$OUTPUT"
assert_not_contains "installer no longer prints author machine path" "/Users/jimmy/Documents/GitHub/ai-symbiote" "$OUTPUT"

echo ""
echo "=== Results ==="
printf "Passed: %d / %d\n" "$PASSED" "$TOTAL"
if [ "$FAILED" -gt 0 ]; then
  printf "${RED}Failed: %d${NC}\n" "$FAILED"
  exit 1
else
  printf "${GREEN}All tests passed!${NC}\n"
fi
