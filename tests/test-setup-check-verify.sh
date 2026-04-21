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

# --- Test 6: Schema v2 repo_root filtering — same basename, different paths ---
echo ""
echo "--- Test 6: repo_root disambiguates same-name repos ---"
REPO_CANON=$(cd "$REPO" && pwd -P)
OTHER_PATH="/tmp/elsewhere/myproj"  # same basename, different path
cat > "$QUEUE_FILE" <<EOF
{"ts":"2026-04-21T00:00:00Z","project":"myproj","repo_root":"$REPO_CANON","branch":"feat/xyz","base_sha":"abc","sha":"abc","file":"a.ts","trigger":"write"}
{"ts":"2026-04-21T00:00:01Z","project":"myproj","repo_root":"$OTHER_PATH","branch":"feat/xyz","base_sha":"def","sha":"def","file":"x.ts","trigger":"write"}
{"ts":"2026-04-21T00:00:02Z","project":"myproj","repo_root":"$OTHER_PATH","branch":"feat/xyz","base_sha":"ghi","sha":"ghi","file":"y.ts","trigger":"edit"}
EOF
OUTPUT=$(run_setup_check "$REPO")
assert_contains "count is 1 (only current repo_root counted)" "1 pending" "$OUTPUT"
assert_not_contains "other-path entries NOT leaked (expected 1 not 3)" "3 pending" "$OUTPUT"

# --- Test 7: Schema v1 legacy entries (no repo_root) still match via project+branch ---
echo ""
echo "--- Test 7: Legacy v1 entries without repo_root still match ---"
cat > "$QUEUE_FILE" <<EOF
{"ts":"2026-04-21T00:00:00Z","project":"myproj","branch":"feat/xyz","sha":"legacy1","file":"a.ts","trigger":"write"}
{"ts":"2026-04-21T00:00:01Z","project":"myproj","branch":"feat/xyz","sha":"legacy2","file":"b.ts","trigger":"edit"}
EOF
OUTPUT=$(run_setup_check "$REPO")
assert_contains "legacy v1 entries counted via project+branch" "2 pending" "$OUTPUT"

# --- Test 8: Mixed v1 + v2 entries count correctly ---
echo ""
echo "--- Test 8: Mixed schema (v1 legacy + v2 new) counts both ---"
REPO_CANON=$(cd "$REPO" && pwd -P)
cat > "$QUEUE_FILE" <<EOF
{"ts":"2026-04-21T00:00:00Z","project":"myproj","branch":"feat/xyz","sha":"legacy","file":"old.ts","trigger":"write"}
{"ts":"2026-04-21T00:00:01Z","project":"myproj","repo_root":"$REPO_CANON","branch":"feat/xyz","base_sha":"new","sha":"new","file":"fresh.ts","trigger":"write"}
EOF
OUTPUT=$(run_setup_check "$REPO")
assert_contains "1 v1 + 1 v2 == 2 pending" "2 pending" "$OUTPUT"

# --- Test 9: Non-git cwd → no verify notification (guard branch) ---
echo ""
echo "--- Test 9: setup-check from non-git cwd skips verify section ---"
# Populate queue so the notification WOULD fire if the guard fails
REPO_CANON=$(cd "$REPO" && pwd -P)
cat > "$QUEUE_FILE" <<EOF
{"ts":"2026-04-21T00:00:00Z","project":"myproj","repo_root":"$REPO_CANON","branch":"feat/xyz","base_sha":"abc","sha":"abc","file":"a.ts","trigger":"write"}
EOF
NONGIT_DIR="$TMPROOT/not-a-repo"
mkdir -p "$NONGIT_DIR"
OUTPUT=$(run_setup_check "$NONGIT_DIR")
assert_not_contains "non-git cwd: no [Verify] line" "[Verify]" "$OUTPUT"

# --- Test 10: jq-unavailable grep fallback matches jq path results ---
echo ""
echo "--- Test 10: grep fallback (no jq) produces same counts ---"
# Shadow jq via a temp PATH so the fallback branch runs. Pre-check: a jq
# binary must exist on the original PATH to make the comparison meaningful;
# otherwise both paths hit the else branch and the test is vacuous.
if command -v jq >/dev/null 2>&1; then
  REPO_CANON=$(cd "$REPO" && pwd -P)
  # Mixed v1/v2 fixture identical to Test 8 so we can compare counts
  cat > "$QUEUE_FILE" <<EOF
{"ts":"2026-04-21T00:00:00Z","project":"myproj","branch":"feat/xyz","sha":"legacy","file":"old.ts","trigger":"write"}
{"ts":"2026-04-21T00:00:01Z","project":"myproj","repo_root":"$REPO_CANON","branch":"feat/xyz","base_sha":"new","sha":"new","file":"fresh.ts","trigger":"write"}
{"ts":"2026-04-21T00:00:02Z","project":"myproj","repo_root":"/some/other/repo","branch":"feat/xyz","base_sha":"x","sha":"x","file":"outsider.ts","trigger":"write"}
EOF
  # Shadow PATH to exclude jq
  NOJQ_DIR="$TMPROOT/nojq-bin"
  mkdir -p "$NOJQ_DIR"
  # Point to a PATH that has only coreutils (copy essentials)
  for bin in bash sh grep sed awk cat ls cd pwd printf wc tr basename dirname git env date mktemp mkdir rm touch head tail sort cut; do
    if command -v "$bin" >/dev/null 2>&1; then
      ln -sf "$(command -v "$bin")" "$NOJQ_DIR/$bin" 2>/dev/null || true
    fi
  done
  # Run setup-check with the jq-less PATH
  OUTPUT=$(
    cd "$REPO" || exit 1
    PATH="$NOJQ_DIR" echo '{}' | PATH="$NOJQ_DIR" bash "$PROJECT_ROOT/shared/hooks/scripts/setup-check.sh" 2>/dev/null
  )
  # Mixed v1 + v2-same-repo = 2, and the v2-other-repo entry must be excluded
  assert_contains "grep fallback: 2 pending (v1 + current-repo v2)" "2 pending" "$OUTPUT"
  assert_not_contains "grep fallback: other repo NOT leaked (expected 2 not 3)" "3 pending" "$OUTPUT"
else
  TOTAL=$((TOTAL + 1))
  PASSED=$((PASSED + 1))
  printf "${GREEN}  SKIP${NC} jq not installed on this host — grep fallback vacuously covers all queue reads\n"
fi

# --- Test 11: grep fallback counts correctly when v1 has zero matches ---
# Regression for Codex/Claude adversarial finding: `grep -c ... || echo 0`
# previously produced "0\n0" and silently broke the arithmetic, suppressing
# the [Verify] notification in the steady-state case (v2-only queue, no jq).
echo ""
echo "--- Test 11: grep fallback survives zero-match counts ---"
if command -v jq >/dev/null 2>&1; then
  REPO_CANON=$(cd "$REPO" && pwd -P)
  # Only v2 entries, no v1 → V1 grep path must return 0 cleanly
  cat > "$QUEUE_FILE" <<EOF
{"ts":"2026-04-21T00:00:00Z","project":"myproj","repo_root":"$REPO_CANON","branch":"feat/xyz","base_sha":"a","sha":"a","file":"a.ts","trigger":"write"}
{"ts":"2026-04-21T00:00:01Z","project":"myproj","repo_root":"$REPO_CANON","branch":"feat/xyz","base_sha":"b","sha":"b","file":"b.ts","trigger":"edit"}
EOF
  NOJQ_DIR="$TMPROOT/nojq-bin-11"
  mkdir -p "$NOJQ_DIR"
  for bin in bash sh grep sed awk cat ls cd pwd printf wc tr basename dirname git env date mktemp mkdir rm touch head tail sort cut; do
    if command -v "$bin" >/dev/null 2>&1; then
      ln -sf "$(command -v "$bin")" "$NOJQ_DIR/$bin" 2>/dev/null || true
    fi
  done
  OUTPUT=$(
    cd "$REPO" || exit 1
    PATH="$NOJQ_DIR" echo '{}' | PATH="$NOJQ_DIR" bash "$PROJECT_ROOT/shared/hooks/scripts/setup-check.sh" 2>/dev/null
  )
  assert_contains "zero-v1 case: notification NOT suppressed" "[Verify]" "$OUTPUT"
  assert_contains "zero-v1 case: count is 2" "2 pending" "$OUTPUT"

  # Mirror: v1-only (no v2) should also count cleanly without suppression
  cat > "$QUEUE_FILE" <<EOF
{"ts":"2026-04-21T00:00:00Z","project":"myproj","branch":"feat/xyz","sha":"legacy1","file":"a.ts","trigger":"write"}
{"ts":"2026-04-21T00:00:01Z","project":"myproj","branch":"feat/xyz","sha":"legacy2","file":"b.ts","trigger":"edit"}
EOF
  OUTPUT=$(
    cd "$REPO" || exit 1
    PATH="$NOJQ_DIR" echo '{}' | PATH="$NOJQ_DIR" bash "$PROJECT_ROOT/shared/hooks/scripts/setup-check.sh" 2>/dev/null
  )
  assert_contains "zero-v2 case: notification NOT suppressed" "[Verify]" "$OUTPUT"
  assert_contains "zero-v2 case: count is 2" "2 pending" "$OUTPUT"
else
  TOTAL=$((TOTAL + 1))
  PASSED=$((PASSED + 1))
  printf "${GREEN}  SKIP${NC} jq not installed — grep fallback arithmetic vacuously covered\n"
fi

echo ""
echo "=== Results ==="
printf "Passed: %d / %d\n" "$PASSED" "$TOTAL"
if [ "$FAILED" -gt 0 ]; then
  printf "${RED}Failed: %d${NC}\n" "$FAILED"
  exit 1
else
  printf "${GREEN}All tests passed!${NC}\n"
fi
