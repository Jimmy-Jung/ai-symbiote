#!/bin/bash
# Integration tests for pre-compact.sh PreCompact hook.
#
# Usage: bash tests/test-pre-compact.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PRE_COMPACT_SCRIPT="$PROJECT_ROOT/shared/hooks/scripts/pre-compact.sh"

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
  local desc="$1" needle="$2" file_path="$3"
  TOTAL=$((TOTAL + 1))
  if grep -qF "$needle" "$file_path" 2>/dev/null; then
    PASSED=$((PASSED + 1))
    printf "${GREEN}  PASS${NC} %s\n" "$desc"
  else
    FAILED=$((FAILED + 1))
    printf "${RED}  FAIL${NC} %s\n    needle: %s\n    file: %s\n" "$desc" "$needle" "$file_path"
  fi
}

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

STATE_DIR="$TMPDIR/state"
mkdir -p "$STATE_DIR/state"

# Create minimal manifest.json
cat > "$STATE_DIR/manifest.json" <<'EOF'
{
  "projectPath": "/tmp/test-project",
  "project": { "name": "demo", "type": "app", "languages": ["typescript"] },
  "stack": { "packageManager": "npm", "frameworks": ["react"] }
}
EOF

# Create context.md
cat > "$STATE_DIR/context.md" <<'EOF'
## Project Summary
- Demo project for testing
- Uses TypeScript and React
- Built with npm
- Has comprehensive tests
EOF

# Create harness-rules.md with Seed rules
cat > "$STATE_DIR/harness-rules.md" <<'EOF'
[Seed #1] Never delete package-lock.json without approval
[Seed #2] Always run tests before committing
[Harness #10] Check imports before editing src/app.ts (auto-generated 2026-04-15)
EOF

echo ""
echo "=== pre-compact.sh PreCompact Hook Tests ==="
echo ""

# --- Test 1: Full context injection ---
echo "--- Test: Full context injection ---"
OUTPUT=$(HARNESS_TEST_STATE_DIR="$STATE_DIR" bash "$PRE_COMPACT_SCRIPT")

assert_contains "returns continue json" '"continue":true' "$OUTPUT"
assert_contains "injects Symbiote Manifest" "[Symbiote Manifest]" "$OUTPUT"
assert_contains "manifest contains project name" "project: demo" "$OUTPUT"
assert_contains "injects Symbiote Context" "[Symbiote Context]" "$OUTPUT"
assert_contains "context has file pointer" "Full details: Read" "$OUTPUT"
assert_contains "injects Seed rules" "[Seed #" "$OUTPUT"
assert_contains "seed rule 1 present" "Never delete package-lock.json" "$OUTPUT"
assert_contains "seed rule 2 present" "Always run tests before committing" "$OUTPUT"
assert_contains "injects Synapse keywords" "[Synapse]" "$OUTPUT"
assert_contains "synapse has keyword routing" "Keywords:" "$OUTPUT"
assert_file_contains "records compaction event" '"type":"compaction"' "$STATE_DIR/harness-log.jsonl"

# --- Test 2: Missing files handled gracefully ---
echo ""
echo "--- Test: Graceful handling of missing files ---"
EMPTY_STATE="$TMPDIR/empty-state"
mkdir -p "$EMPTY_STATE"

EMPTY_OUTPUT=$(HARNESS_TEST_STATE_DIR="$EMPTY_STATE" bash "$PRE_COMPACT_SCRIPT")

assert_contains "empty state returns continue" '"continue":true' "$EMPTY_OUTPUT"
TOTAL=$((TOTAL + 1))
if echo "$EMPTY_OUTPUT" | grep -qF "[Symbiote Manifest]" 2>/dev/null; then
  FAILED=$((FAILED + 1))
  printf "${RED}  FAIL${NC} empty state omits manifest\n"
else
  PASSED=$((PASSED + 1))
  printf "${GREEN}  PASS${NC} empty state omits manifest\n"
fi

# --- Test 3: Cursor protocol ---
echo ""
echo "--- Test: Cursor protocol ---"
CURSOR_OUTPUT=$(HARNESS_TEST_STATE_DIR="$STATE_DIR" CURSOR_PLUGIN_ROOT="/tmp/cursor-plugin" bash "$PRE_COMPACT_SCRIPT")

assert_contains "cursor returns permission allow" '"permission":"allow"' "$CURSOR_OUTPUT"
assert_contains "cursor returns additional_context" '"additional_context":"' "$CURSOR_OUTPUT"
assert_contains "cursor returns agent_message" '"agent_message":"' "$CURSOR_OUTPUT"

# --- Test 4: Active Ralph loop ---
echo ""
echo "--- Test: Active Ralph loop ---"
mkdir -p "$STATE_DIR/state/my-task"
cat > "$STATE_DIR/state/my-task/ralph-state.md" <<'EOF'
active: true
phase: build
step: 3
EOF

RALPH_OUTPUT=$(HARNESS_TEST_STATE_DIR="$STATE_DIR" bash "$PRE_COMPACT_SCRIPT")
assert_contains "includes active ralph loop" "Ralph Loop 'my-task' active" "$RALPH_OUTPUT"
assert_contains "includes ralph phase" "phase: build" "$RALPH_OUTPUT"
assert_contains "includes ralph step" "step: 3" "$RALPH_OUTPUT"

# Clean up ralph state for other tests
rm -rf "$STATE_DIR/state/my-task"

echo ""
echo "=== Results ==="
printf "Passed: %d / %d\n" "$PASSED" "$TOTAL"
if [ "$FAILED" -gt 0 ]; then
  printf "${RED}Failed: %d${NC}\n" "$FAILED"
  exit 1
else
  printf "${GREEN}All tests passed!${NC}\n"
fi
