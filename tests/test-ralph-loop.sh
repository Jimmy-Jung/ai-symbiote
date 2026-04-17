#!/bin/bash
# Integration tests for the Codex-compatible Ralph loop runner.
#
# Usage: bash tests/test-ralph-loop.sh
# Author: JunyoungJung
# Date: 2026-04-17

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RUNNER="$PROJECT_ROOT/shared/skills/ralph/scripts/ralph-loop.sh"

PASSED=0
FAILED=0
TOTAL=0

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  TOTAL=$((TOTAL + 1))
  if echo "$haystack" | grep -qF -- "$needle" 2>/dev/null; then
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
  if grep -qF -- "$needle" "$file" 2>/dev/null; then
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
mkdir -p "$TEST_REPO" "$STATE_DIR/ralph"

git init "$TEST_REPO" >/dev/null 2>&1

cat > "$STATE_DIR/ralph/prd.json" <<'EOF'
{
  "project": "Demo Project",
  "branchName": "ralph/task-status",
  "description": "Task status workflow",
  "userStories": [
    {
      "id": "US-001",
      "title": "Add status field",
      "description": "As a user, I want task status support.",
      "acceptanceCriteria": ["Typecheck passes"],
      "priority": 1,
      "passes": false,
      "notes": ""
    }
  ]
}
EOF

echo ""
echo "=== ralph-loop.sh Tests ==="
echo ""

HELP_OUTPUT=$(bash "$RUNNER" --help)
assert_contains "help prints usage" "Usage: ralph-loop.sh" "$HELP_OUTPUT"
assert_contains "help lists prepare-only" "--prepare-only" "$HELP_OUTPUT"

PREP_OUTPUT=$(bash "$RUNNER" --project-root "$TEST_REPO" --state-dir "$STATE_DIR" --prepare-only --max-iterations 5)
assert_contains "prepare-only reports workspace" "[Ralph] Prepared workspace:" "$PREP_OUTPUT"
assert_file_contains "prepare-only writes progress file" "# Ralph Progress Log" "$STATE_DIR/ralph/progress.txt"
assert_file_contains "prepare-only writes codebase patterns section" "## Codebase Patterns" "$STATE_DIR/ralph/progress.txt"
assert_file_contains "prepare-only writes last branch" "ralph/task-status" "$STATE_DIR/ralph/.last-branch"
assert_file_contains "prepare-only writes task state" "phase: prepared" "$STATE_DIR/state/ralph-task-status/ralph-state.md"
assert_file_contains "prepare-only marks task inactive" "active: false" "$STATE_DIR/state/ralph-task-status/ralph-state.md"
assert_file_contains "prepare-only writes notepad project" "project: Demo Project" "$STATE_DIR/state/ralph-task-status/notepad.md"
assert_file_contains "prepare-only writes prd snapshot" "ralph/task-status" "$STATE_DIR/ralph/.last-prd.json"

PREP_WITH_MISSING_TOOL_OUTPUT=$(bash "$RUNNER" --project-root "$TEST_REPO" --state-dir "$STATE_DIR" --prepare-only --tool amp)
assert_contains "prepare-only skips tool availability check" "[Ralph] Prepared workspace:" "$PREP_WITH_MISSING_TOOL_OUTPUT"

cat > "$STATE_DIR/ralph/progress.txt" <<'EOF'
# Ralph Progress Log

## Codebase Patterns
- Old pattern

Started: 2026-04-17T00:00:00Z
---
EOF

echo "ralph/old-feature" > "$STATE_DIR/ralph/.last-branch"

mkdir -p "$STATE_DIR/state/ralph-old-feature"
cat > "$STATE_DIR/state/ralph-old-feature/ralph-state.md" <<'EOF'
# Ralph State

- active: false
- iteration: 3
- maxIterations: 10
- phase: complete
- step: 3
- taskDescription: Old feature workflow
- completionLevel: 100
- startedAt: 2026-04-17T00:00:00Z
- tool: codex
- branchName: ralph/old-feature
EOF

cat > "$STATE_DIR/ralph/.last-prd.json" <<'EOF'
{
  "project": "Demo Project",
  "branchName": "ralph/old-feature",
  "description": "Old feature workflow",
  "userStories": [
    {
      "id": "US-001",
      "title": "Old story",
      "description": "As a user, I want the old feature.",
      "acceptanceCriteria": ["Typecheck passes"],
      "priority": 1,
      "passes": true,
      "notes": ""
    }
  ]
}
EOF

cat > "$STATE_DIR/ralph/prd.json" <<'EOF'
{
  "project": "Demo Project",
  "branchName": "ralph/new-feature",
  "description": "New feature workflow",
  "userStories": []
}
EOF

ARCHIVE_OUTPUT=$(bash "$RUNNER" --project-root "$TEST_REPO" --state-dir "$STATE_DIR" --prepare-only)
assert_contains "archive path still prepares workspace" "[Ralph] Prepared workspace:" "$ARCHIVE_OUTPUT"

TOTAL=$((TOTAL + 1))
if find "$STATE_DIR/ralph/archive" -mindepth 1 -maxdepth 1 -type d | grep -q . 2>/dev/null; then
  PASSED=$((PASSED + 1))
  printf "${GREEN}  PASS${NC} branch change archives previous run\n"
else
  FAILED=$((FAILED + 1))
  printf "${RED}  FAIL${NC} branch change archives previous run\n"
fi

TOTAL=$((TOTAL + 1))
if find "$STATE_DIR/ralph/archive" -type f -name 'progress.txt' | xargs grep -qF "Old pattern" 2>/dev/null; then
  PASSED=$((PASSED + 1))
  printf "${GREEN}  PASS${NC} archive preserves previous progress content\n"
else
  FAILED=$((FAILED + 1))
  printf "${RED}  FAIL${NC} archive preserves previous progress content\n"
fi

ARCHIVE_DIR=$(find "$STATE_DIR/ralph/archive" -mindepth 1 -maxdepth 1 -type d | head -1)
assert_file_contains "archive preserves previous prd branch" "\"branchName\": \"ralph/old-feature\"" "$ARCHIVE_DIR/prd.json"
assert_file_contains "archive preserves previous story title" "\"title\": \"Old story\"" "$ARCHIVE_DIR/prd.json"
assert_file_contains "archive preserves previous state branch" "branchName: ralph/old-feature" "$ARCHIVE_DIR/ralph-state.md"

assert_file_contains "new branch becomes current branch" "ralph/new-feature" "$STATE_DIR/ralph/.last-branch"
assert_file_contains "new branch task state folder created" "branchName: ralph/new-feature" "$STATE_DIR/state/ralph-new-feature/ralph-state.md"

echo ""
echo "=== Results ==="
printf "Passed: %d / %d\n" "$PASSED" "$TOTAL"
if [ "$FAILED" -gt 0 ]; then
  printf "${RED}Failed: %d${NC}\n" "$FAILED"
  exit 1
else
  printf "${GREEN}All tests passed!${NC}\n"
fi
