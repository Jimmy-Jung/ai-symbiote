#!/bin/bash
# Integration tests for setup-check.sh Verify queue pending notification.
#
# Verifies:
#   - Pending count matches current project+branch only (not other projects)
#   - Zero pending = no notification
#   - Missing queue file = no notification
#   - N>0 pending = "[Verify] N pending verification(s) for {project}/{branch}" line
#
# The setup-check script reads ~/.ai-symbiote/state/verify-queue.jsonl; the test
# isolates $HOME so we don't touch the user's real queue.
#
# Author: JunyoungJung
# Date: 2026-04-21
# Usage: bash tests/test-setup-check-verify.sh

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
  if printf '%s' "$haystack" | grep -qF "$needle"; then
    PASSED=$((PASSED + 1))
    printf "${GREEN}  PASS${NC} %s\n" "$desc"
  else
    FAILED=$((FAILED + 1))
    printf "${RED}  FAIL${NC} %s (needle not found)\n    needle: %s\n    actual: %s\n" "$desc" "$needle" "$haystack"
  fi
}

assert_not_contains() {
  local desc="$1" needle="$2" haystack="$3"
  TOTAL=$((TOTAL + 1))
  if printf '%s' "$haystack" | grep -qF "$needle"; then
    FAILED=$((FAILED + 1))
    printf "${RED}  FAIL${NC} %s (needle present but should not be)\n" "$desc"
  else
    PASSED=$((PASSED + 1))
    printf "${GREEN}  PASS${NC} %s\n" "$desc"
  fi
}

TMPROOT=$(mktemp -d)
trap 'rm -rf "$TMPROOT"' EXIT

export HOME="$TMPROOT/home"
mkdir -p "$HOME"
QUEUE_FILE="$HOME/.ai-symbiote/state/verify-queue.jsonl"

# Isolate SYMBIOTE_HOME so setup-check doesn't inject unrelated context parts.
export SYMBIOTE_HOME="$TMPROOT/symbiote-state"
mkdir -p "$SYMBIOTE_HOME"

# Prepare a temp git repo — setup-check derives project/branch via git commands
setup_git_repo() {
  local repo="$TMPROOT/myproj"
  rm -rf "$repo"
  mkdir -p "$repo"
  (
    cd "$repo" || exit 1
    git init -q
    git config user.email test@example.com
    git config user.name Test
    git checkout -q -b feat/xyz 2>/dev/null || true
    echo seed > seed.txt
    git add seed.txt
    git commit -q -m seed
  )
  printf '%s' "$repo"
}

run_setup_check() {
  local cwd="$1"
  (
    cd "$cwd" || exit 1
    echo '{}' | bash "$PROJECT_ROOT/shared/hooks/scripts/setup-check.sh" 2>/dev/null
  )
}

echo ""
echo "=== setup-check.sh Verify Queue Pending Tests ==="
echo ""

REPO=$(setup_git_repo)

# --- Test 1: No queue file → no notification ---
echo "--- Test 1: No queue file → no verify notification ---"
rm -f "$QUEUE_FILE"
OUTPUT=$(run_setup_check "$REPO")
assert_not_contains "no Verify line when queue file missing" "[Verify]" "$OUTPUT"

# --- Test 2: Empty queue → no notification ---
echo ""
echo "--- Test 2: Empty queue file → no notification ---"
mkdir -p "$(dirname "$QUEUE_FILE")"
: > "$QUEUE_FILE"
OUTPUT=$(run_setup_check "$REPO")
assert_not_contains "no Verify line when queue empty" "[Verify]" "$OUTPUT"

# --- Test 3: Three entries for current project/branch ---
echo ""
echo "--- Test 3: Three pending entries for current project/branch ---"
cat > "$QUEUE_FILE" <<EOF
{"ts":"2026-04-21T00:00:00Z","project":"myproj","branch":"feat/xyz","sha":"abc","file":"a.ts","trigger":"write"}
{"ts":"2026-04-21T00:00:01Z","project":"myproj","branch":"feat/xyz","sha":"abc","file":"b.ts","trigger":"edit"}
{"ts":"2026-04-21T00:00:02Z","project":"myproj","branch":"feat/xyz","sha":"abc","file":"c.ts","trigger":"write"}
EOF
OUTPUT=$(run_setup_check "$REPO")
assert_contains "Verify line present" "[Verify]" "$OUTPUT"
assert_contains "count is 3" "3 pending" "$OUTPUT"
assert_contains "project/branch label" "myproj/feat/xyz" "$OUTPUT"

# --- Test 4: Filter by project — entries from other projects not counted ---
echo ""
echo "--- Test 4: Other-project entries are filtered out ---"
cat > "$QUEUE_FILE" <<EOF
{"ts":"2026-04-21T00:00:00Z","project":"myproj","branch":"feat/xyz","sha":"abc","file":"a.ts","trigger":"write"}
{"ts":"2026-04-21T00:00:01Z","project":"other","branch":"feat/xyz","sha":"def","file":"x.ts","trigger":"write"}
{"ts":"2026-04-21T00:00:02Z","project":"another","branch":"main","sha":"ghi","file":"y.ts","trigger":"edit"}
EOF
OUTPUT=$(run_setup_check "$REPO")
assert_contains "Verify line present" "[Verify]" "$OUTPUT"
assert_contains "count is 1 (only myproj counted)" "1 pending" "$OUTPUT"
assert_not_contains "no count of 3 (other projects leaked)" "3 pending" "$OUTPUT"

# --- Test 5: Filter by branch — entries from other branches not counted ---
echo ""
echo "--- Test 5: Other-branch entries filtered out ---"
cat > "$QUEUE_FILE" <<EOF
{"ts":"2026-04-21T00:00:00Z","project":"myproj","branch":"feat/xyz","sha":"abc","file":"a.ts","trigger":"write"}
{"ts":"2026-04-21T00:00:01Z","project":"myproj","branch":"main","sha":"def","file":"x.ts","trigger":"write"}
{"ts":"2026-04-21T00:00:02Z","project":"myproj","branch":"feat/other","sha":"ghi","file":"y.ts","trigger":"edit"}
EOF
OUTPUT=$(run_setup_check "$REPO")
assert_contains "count is 1 (only feat/xyz counted)" "1 pending" "$OUTPUT"

echo ""
echo "=== Results ==="
printf "Passed: %d / %d\n" "$PASSED" "$TOTAL"
if [ "$FAILED" -gt 0 ]; then
  printf "${RED}Failed: %d${NC}\n" "$FAILED"
  exit 1
else
  printf "${GREEN}All tests passed!${NC}\n"
fi
