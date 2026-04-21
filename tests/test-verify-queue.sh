#!/bin/bash
# Integration tests for verify-queue.sh (Write-time Verification Layer queue append).
#
# Verifies:
#   - JSON line format and field escaping
#   - Missing file_path handling
#   - tool_name -> trigger (lowercased)
#   - Project/branch/sha collection from git repo
#   - Fallback when not in a git repo (sha=uncommitted, branch=unknown)
#   - Always exits 0 with {"continue":true} (never blocks edit flow)
#
# Author: JunyoungJung
# Date: 2026-04-21
# Usage: bash tests/test-verify-queue.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK_SCRIPT="$PROJECT_ROOT/shared/hooks/scripts/verify-queue.sh"

PASSED=0
FAILED=0
TOTAL=0

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  TOTAL=$((TOTAL + 1))
  if [ "$expected" = "$actual" ]; then
    PASSED=$((PASSED + 1))
    printf "${GREEN}  PASS${NC} %s\n" "$desc"
  else
    FAILED=$((FAILED + 1))
    printf "${RED}  FAIL${NC} %s\n    expected: %s\n    actual:   %s\n" "$desc" "$expected" "$actual"
  fi
}

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
    printf "${RED}  FAIL${NC} %s (needle found but should not be)\n    needle: %s\n" "$desc" "$needle"
  else
    PASSED=$((PASSED + 1))
    printf "${GREEN}  PASS${NC} %s\n" "$desc"
  fi
}

TMPROOT=$(mktemp -d)
trap 'rm -rf "$TMPROOT"' EXIT

# Isolate $HOME so the hook writes to a temp queue, not the real user's queue.
export HOME="$TMPROOT/home"
mkdir -p "$HOME"

QUEUE_FILE="$HOME/.ai-symbiote/state/verify-queue.jsonl"

run_hook() {
  local input="$1"
  printf '%s' "$input" | bash "$HOOK_SCRIPT"
}

reset_queue() {
  rm -rf "$HOME/.ai-symbiote" 2>/dev/null || true
}

# ============================================================================
# Tests that need a git repo context
# ============================================================================

setup_git_repo() {
  local repo="$TMPROOT/repo"
  rm -rf "$repo"
  mkdir -p "$repo"
  (
    cd "$repo" || exit 1
    git init -q >/dev/null 2>&1
    git config user.email "test@example.com"
    git config user.name "Test"
    git checkout -q -b feat/test-branch 2>/dev/null || true
    echo "seed" > seed.txt
    git add seed.txt
    git commit -q -m "seed" >/dev/null 2>&1
  )
  printf '%s' "$repo"
}

echo ""
echo "=== verify-queue.sh Integration Tests ==="
echo ""

# --- Test 1: Happy path — Claude-style input with tool_input.file_path ---
echo "--- Test 1: Claude Write hook with tool_input.file_path ---"
REPO=$(setup_git_repo)
mkdir -p "$REPO/src"
reset_queue
INPUT='{"tool_name":"Write","tool_input":{"file_path":"'"$REPO"'/src/foo.ts"}}'
STDOUT=$(run_hook "$INPUT")

assert_eq "stdout is continue:true" '{"continue":true}' "$STDOUT"
assert_eq "queue file exists" "true" "$([ -f "$QUEUE_FILE" ] && echo true || echo false)"

QUEUE_LINE=$(cat "$QUEUE_FILE")
assert_contains "queue line has ts" '"ts":"' "$QUEUE_LINE"
assert_contains "queue line has project" '"project":"repo"' "$QUEUE_LINE"
assert_contains "queue line has branch" '"branch":"feat/test-branch"' "$QUEUE_LINE"
assert_contains "queue line has file path" '"file":"'"$REPO"'/src/foo.ts"' "$QUEUE_LINE"
assert_contains "queue line trigger lowercased" '"trigger":"write"' "$QUEUE_LINE"
assert_not_contains "trigger is not capitalized Write" '"trigger":"Write"' "$QUEUE_LINE"

# Schema v2: repo_root (absolute path) for multi-repo disambiguation.
# Hook stores the git-canonical path; macOS /tmp → /private/tmp symlink means
# we must resolve with `pwd -P` before comparing.
REPO_CANON=$(cd "$REPO" && pwd -P)
assert_contains "queue line has repo_root (schema v2)" '"repo_root":"'"$REPO_CANON"'"' "$QUEUE_LINE"

# Schema v2: base_sha (pre-edit HEAD) for diff contract. Must match HEAD at
# queue-append time, NOT whatever HEAD resolves to later when /verify runs.
BASE_SHA_IN_QUEUE=$(printf '%s' "$QUEUE_LINE" | sed -n 's/.*"base_sha":"\([^"]*\)".*/\1/p')
REPO_HEAD=$(cd "$REPO" && git rev-parse --short HEAD)
assert_eq "base_sha captures HEAD at edit time" "$REPO_HEAD" "$BASE_SHA_IN_QUEUE"

# Legacy sha field mirrors base_sha for backward compat (pre-0.11 consumers)
SHA_IN_QUEUE=$(printf '%s' "$QUEUE_LINE" | sed -n 's/.*"sha":"\([^"]*\)".*/\1/p')
assert_eq "legacy sha field mirrors base_sha" "$BASE_SHA_IN_QUEUE" "$SHA_IN_QUEUE"

# --- Test 2: Edit trigger lowercase ---
echo ""
echo "--- Test 2: Edit tool trigger lowercase ---"
reset_queue
mkdir -p "$REPO/src"
INPUT='{"tool_name":"Edit","tool_input":{"file_path":"'"$REPO"'/src/bar.ts"}}'
run_hook "$INPUT" >/dev/null
QUEUE_LINE=$(cat "$QUEUE_FILE")
assert_contains "Edit becomes edit" '"trigger":"edit"' "$QUEUE_LINE"

# --- Test 3: Missing file_path — hook returns continue but appends nothing ---
echo ""
echo "--- Test 3: Missing file_path skips queue append ---"
reset_queue
INPUT='{"tool_name":"Read","tool_input":{}}'
STDOUT=$(run_hook "$INPUT")
assert_eq "stdout is continue:true" '{"continue":true}' "$STDOUT"
assert_eq "queue file NOT created" "false" "$([ -f "$QUEUE_FILE" ] && echo true || echo false)"

# --- Test 4: Legacy flat file_path (top-level, no tool_input wrapper) ---
echo ""
echo "--- Test 4: Flat file_path at top level still works ---"
reset_queue
mkdir -p "$REPO/src"
INPUT='{"file_path":"'"$REPO"'/src/baz.ts","tool_name":"Write"}'
run_hook "$INPUT" >/dev/null
assert_eq "queue file created" "true" "$([ -f "$QUEUE_FILE" ] && echo true || echo false)"
assert_contains "flat file_path captured" '"file":"'"$REPO"'/src/baz.ts"' "$(cat "$QUEUE_FILE")"

# --- Test 5: File path with spaces and special chars — JSON escaped ---
echo ""
echo "--- Test 5: File path with quotes is escaped ---"
reset_queue
SPECIAL_DIR="$REPO/src with space"
mkdir -p "$SPECIAL_DIR"
# Path with a literal double-quote (unusual but possible)
WEIRD_PATH="$SPECIAL_DIR/he said \"hi\".ts"
# Build input with embedded quotes escaped in JSON
INPUT='{"tool_name":"Write","tool_input":{"file_path":"'"$(printf '%s' "$WEIRD_PATH" | sed 's/"/\\"/g')"'"}}'
run_hook "$INPUT" >/dev/null
assert_eq "queue file created despite special chars" "true" "$([ -f "$QUEUE_FILE" ] && echo true || echo false)"

# The result line should keep the path escaped so the JSONL stays parseable
# Validate that each line is valid JSON (use python3 for portability)
VALIDATION=$(python3 -c "
import json, sys
lines = open('$QUEUE_FILE').read().splitlines()
for ln in lines:
    json.loads(ln)
print('OK')
" 2>&1 || echo "INVALID")
assert_eq "every queue line is parseable JSON" "OK" "$VALIDATION"

# --- Test 6: Multiple appends accumulate ---
echo ""
echo "--- Test 6: Multiple appends accumulate in same file ---"
reset_queue
# Files under $REPO root (which exists) so dirname resolves correctly
run_hook '{"tool_name":"Write","tool_input":{"file_path":"'"$REPO"'/a.ts"}}' >/dev/null
run_hook '{"tool_name":"Edit","tool_input":{"file_path":"'"$REPO"'/b.ts"}}' >/dev/null
run_hook '{"tool_name":"Write","tool_input":{"file_path":"'"$REPO"'/c.ts"}}' >/dev/null
LINE_COUNT=$(wc -l < "$QUEUE_FILE" | tr -d ' ')
assert_eq "three appends produce three lines" "3" "$LINE_COUNT"

# --- Test 7: Non-git directory — sha=uncommitted, branch fallback ---
echo ""
echo "--- Test 7: File outside git repo yields sane fallback ---"
reset_queue
NONGIT_DIR="$TMPROOT/nongit"
mkdir -p "$NONGIT_DIR"
INPUT='{"tool_name":"Write","tool_input":{"file_path":"'"$NONGIT_DIR"'/orphan.ts"}}'
# Change cwd so the hook's git fallback also cannot find a repo.
(
  cd "$NONGIT_DIR"
  run_hook "$INPUT" >/dev/null
)
QUEUE_LINE=$(cat "$QUEUE_FILE")
# Either "sha":"uncommitted" or it falls back to any git repo reachable from $FILE_DIR.
# We care that the hook did NOT crash and DID produce a line.
assert_eq "non-git still produces queue line" "1" "$(wc -l < "$QUEUE_FILE" | tr -d ' ')"
# And the line must be valid JSON regardless of how branch/sha resolved.
VALIDATION=$(python3 -c "
import json
json.loads(open('$QUEUE_FILE').read().splitlines()[0])
print('OK')
" 2>&1 || echo "INVALID")
assert_eq "non-git queue line valid JSON" "OK" "$VALIDATION"

# --- Test 8: Empty stdin — must not crash ---
echo ""
echo "--- Test 8: Empty stdin returns continue:true ---"
reset_queue
STDOUT=$(printf '' | bash "$HOOK_SCRIPT")
assert_eq "empty stdin returns continue" '{"continue":true}' "$STDOUT"
assert_eq "empty stdin creates no queue line" "false" "$([ -f "$QUEUE_FILE" ] && echo true || echo false)"

# --- Test 9 (renumbered to 10): base_sha is pre-edit HEAD, unaffected by later commits ---
echo ""
echo "--- Test 9: base_sha captures pre-edit HEAD, not moving HEAD ---"
reset_queue
mkdir -p "$REPO/src"
# Record HEAD at edit time
HEAD_AT_EDIT=$(cd "$REPO" && git rev-parse --short HEAD)
run_hook '{"tool_name":"Write","tool_input":{"file_path":"'"$REPO"'/src/moving.ts"}}' >/dev/null
# Now create a new commit so HEAD moves
(
  cd "$REPO"
  echo "later change" > another.txt
  git add another.txt
  git commit -q -m "later-commit"
)
NEW_HEAD=$(cd "$REPO" && git rev-parse --short HEAD)
# base_sha in the queue entry must still be HEAD_AT_EDIT, not NEW_HEAD
QUEUE_LINE=$(cat "$QUEUE_FILE")
BASE_SHA_IN_QUEUE=$(printf '%s' "$QUEUE_LINE" | sed -n 's/.*"base_sha":"\([^"]*\)".*/\1/p')
assert_eq "HEAD moved between edit and inspection" "1" "$([ "$HEAD_AT_EDIT" != "$NEW_HEAD" ] && echo 1 || echo 0)"
assert_eq "base_sha stays at pre-edit HEAD" "$HEAD_AT_EDIT" "$BASE_SHA_IN_QUEUE"
assert_not_contains "base_sha is NOT the new HEAD" "\"base_sha\":\"$NEW_HEAD\"" "$QUEUE_LINE"

# --- Test 10: Same-basename repos in different paths do not share queue identity ---
echo ""
echo "--- Test 10: Multi-repo disambiguation via repo_root ---"
reset_queue
# Repo #1 already exists at $REPO. Build a second repo with the SAME basename
# but in a different parent directory.
REPO_BASENAME=$(basename "$REPO")
TWIN_PARENT="$TMPROOT/other-workspace"
mkdir -p "$TWIN_PARENT"
TWIN_REPO="$TWIN_PARENT/$REPO_BASENAME"
mkdir -p "$TWIN_REPO"
(
  cd "$TWIN_REPO" || exit 1
  git init -q
  git config user.email twin@example.com
  git config user.name Twin
  git checkout -q -b feat/test-branch 2>/dev/null || true
  echo twin > seed.txt
  git add seed.txt
  git commit -q -m twin-seed
)
mkdir -p "$TWIN_REPO/src"

# Append one entry from each repo
run_hook '{"tool_name":"Write","tool_input":{"file_path":"'"$REPO"'/src/from-original.ts"}}' >/dev/null
run_hook '{"tool_name":"Write","tool_input":{"file_path":"'"$TWIN_REPO"'/src/from-twin.ts"}}' >/dev/null

# Both entries coexist
LINE_COUNT=$(wc -l < "$QUEUE_FILE" | tr -d ' ')
assert_eq "both twin repos contribute one entry each" "2" "$LINE_COUNT"

# Each entry's repo_root must point to the correct absolute path.
# On macOS, /tmp is a symlink to /private/tmp and `git rev-parse --show-toplevel`
# returns the canonical (symlink-resolved) path. Resolve both sides to compare.
REPO_CANON=$(cd "$REPO" && pwd -P)
TWIN_REPO_CANON=$(cd "$TWIN_REPO" && pwd -P)
ORIG_ENTRY=$(grep "\"repo_root\":\"$REPO_CANON\"" "$QUEUE_FILE")
TWIN_ENTRY=$(grep "\"repo_root\":\"$TWIN_REPO_CANON\"" "$QUEUE_FILE")
assert_contains "original entry has original repo_root" "\"repo_root\":\"$REPO_CANON\"" "$ORIG_ENTRY"
assert_contains "twin entry has twin repo_root" "\"repo_root\":\"$TWIN_REPO_CANON\"" "$TWIN_ENTRY"
assert_not_contains "original entry does NOT carry twin path" "\"repo_root\":\"$TWIN_REPO_CANON\"" "$ORIG_ENTRY"
assert_not_contains "twin entry does NOT carry original path" "\"repo_root\":\"$REPO_CANON\"" "$TWIN_ENTRY"
# Basename (project) collides, by design — disambiguation must come from repo_root
assert_contains "original entry project is basename" "\"project\":\"$REPO_BASENAME\"" "$ORIG_ENTRY"
assert_contains "twin entry project is same basename" "\"project\":\"$REPO_BASENAME\"" "$TWIN_ENTRY"

# --- Test 11: Exit code is always 0 (never blocks agent) ---
echo ""
echo "--- Test 11: Exit code is 0 even with malformed JSON ---"
reset_queue
set +e
printf 'not json at all' | bash "$HOOK_SCRIPT" >/dev/null 2>&1
EXIT_CODE=$?
set -e
assert_eq "malformed input exits 0 (never blocks)" "0" "$EXIT_CODE"

echo ""
echo "=== Results ==="
printf "Passed: %d / %d\n" "$PASSED" "$TOTAL"
if [ "$FAILED" -gt 0 ]; then
  printf "${RED}Failed: %d${NC}\n" "$FAILED"
  exit 1
else
  printf "${GREEN}All tests passed!${NC}\n"
fi
