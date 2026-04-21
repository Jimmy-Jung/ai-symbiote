#!/bin/bash
# Regression tests for guard-shell.sh destructive rm matching.
#
# Author: JunyoungJung
# Date: 2026-04-21

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GUARD_SCRIPT="$PROJECT_ROOT/shared/hooks/scripts/guard-shell.sh"

# shellcheck source=../shared/hooks/scripts/lib/common.sh
source "$PROJECT_ROOT/shared/hooks/scripts/lib/common.sh"

PASSED=0
FAILED=0
TOTAL=0

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

assert_blocked() {
  local desc="$1" output="$2"
  TOTAL=$((TOTAL + 1))
  if printf '%s' "$output" | grep -qF "Deleting system or home directory is blocked"; then
    PASSED=$((PASSED + 1))
    printf "${GREEN}  PASS${NC} %s\n" "$desc"
  else
    FAILED=$((FAILED + 1))
    printf "${RED}  FAIL${NC} %s (expected destructive rm block)\n    output: %s\n" "$desc" "$output"
  fi
}

assert_allowed() {
  local desc="$1" output="$2"
  TOTAL=$((TOTAL + 1))
  if [ -z "$output" ]; then
    PASSED=$((PASSED + 1))
    printf "${GREEN}  PASS${NC} %s\n" "$desc"
  else
    FAILED=$((FAILED + 1))
    printf "${RED}  FAIL${NC} %s (expected empty output)\n    output: %s\n" "$desc" "$output"
  fi
}

TEST_STATE=$(mktemp -d)
trap 'rm -rf "$TEST_STATE"' EXIT
mkdir -p "$TEST_STATE/state"
cat > "$TEST_STATE/manifest.json" <<'JSON'
{"projectPath":"/tmp/guard-shell-test","security":{"mode":"balanced"}}
JSON

run_guard() {
  local command="$1"
  local escaped
  escaped=$(json_escape "$command")
  printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$escaped" \
    | HARNESS_TEST_STATE_DIR="$TEST_STATE" CLAUDE_PROJECT_DIR="/tmp/guard-shell-test" \
      bash "$GUARD_SCRIPT" 2>&1 || true
}

echo ""
printf "${YELLOW}=== Guard Shell rm Tests ===${NC}\n"

printf "\n${YELLOW}Test 1: dangerous root/system targets are blocked${NC}\n"
assert_blocked "blocks root directory" "$(run_guard "rm -rf /")"
assert_blocked "blocks root glob" "$(run_guard "rm -rf /*")"
assert_blocked "blocks system directory" "$(run_guard "rm -fr /etc")"
assert_blocked "blocks chained destructive rm" "$(run_guard "cd /tmp && rm -rf /System")"
assert_blocked "blocks HOME variable" "$(run_guard "rm --recursive --force \$HOME")"

printf "\n${YELLOW}Test 2: safe cleanup paths are allowed${NC}\n"
assert_allowed "allows /tmp cleanup" "$(run_guard "rm -rf /tmp/verify-diffs")"
assert_allowed "allows /var/tmp cleanup" "$(run_guard "rm -rf /var/tmp/symbiote-cache")"
assert_allowed "allows macOS TMPDIR cleanup" "$(run_guard "rm -rf /var/folders/ab/cd/T/symbiote-cache")"
assert_allowed "allows project subdirectory cleanup" "$(run_guard "rm -rf /Users/jimmy/Documents/GitHub/ai-symbiote/build")"

printf "\n${YELLOW}Test 3: documentation and issue body examples are allowed${NC}\n"
assert_allowed "allows quoted /tmp example in gh body" "$(run_guard "gh issue create --body \"example: rm -rf /tmp/foo\"")"
assert_allowed "allows quoted root example in gh body" "$(run_guard "gh issue create --body \"example: rm -rf /\"")"
assert_allowed "allows echoed root example" "$(run_guard "echo \"example: rm -rf /\"")"

echo ""
printf "${YELLOW}=== Results ===${NC}\n"
printf "Total: %d  Passed: ${GREEN}%d${NC}  Failed: ${RED}%d${NC}\n" "$TOTAL" "$PASSED" "$FAILED"

if [ "$FAILED" -gt 0 ]; then
  exit 1
fi

printf "${GREEN}All tests passed!${NC}\n"
