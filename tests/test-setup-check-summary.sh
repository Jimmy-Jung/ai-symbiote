#!/bin/bash
# Integration tests for setup-check.sh 3-Tier Lazy Context injection.
#
# Tests the tiered harness-rules injection:
#   - Seed rules ([Seed #...]) are always injected (Tier 1)
#   - Auto-generated Harness rules ([Harness #...]) are deferred with a file pointer
#   - Synapse routing is injected as a compact 1-line keyword map
#
# Usage: bash tests/test-setup-check-summary.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

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
  if echo "$haystack" | grep -qF "$needle" 2>/dev/null; then
    PASSED=$((PASSED + 1))
    printf "${GREEN}  PASS${NC} %s\n" "$desc"
  else
    FAILED=$((FAILED + 1))
    printf "${RED}  FAIL${NC} %s (needle not found)\n    needle: %s\n" "$desc" "$needle"
  fi
}

assert_not_contains() {
  local desc="$1" needle="$2" haystack="$3"
  TOTAL=$((TOTAL + 1))
  if echo "$haystack" | grep -qF "$needle" 2>/dev/null; then
    FAILED=$((FAILED + 1))
    printf "${RED}  FAIL${NC} %s (needle found but should not be)\n    needle: %s\n" "$desc" "$needle"
  else
    PASSED=$((PASSED + 1))
    printf "${GREEN}  PASS${NC} %s\n" "$desc"
  fi
}

# Setup temp state directory
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

setup_state() {
  local state_dir="$TMPDIR/test-state"
  rm -rf "$state_dir"
  mkdir -p "$state_dir"
  # Create minimal manifest so Synapse routing activates
  echo '{"projectPath":"/tmp/test","slug":"test"}' > "$state_dir/manifest.json"
  echo "$state_dir"
}

# Run the harness-rules + synapse section of setup-check.sh with overridden state dir
run_setup_check() {
  local state_dir="$1"
  SYMBIOTE_HOME="$TMPDIR" \
  CLAUDE_PROJECT_DIR="/tmp/test" \
  echo '{}' | bash -c "
    get_project_slug() { echo 'test-state'; }
    get_state_root() { echo '$TMPDIR'; }
    source '$PROJECT_ROOT/shared/hooks/scripts/lib/common.sh'
    get_state_dir() { echo '$state_dir'; }
    export -f get_state_dir get_state_root get_project_slug json_field json_nested_field json_escape

    STATE_DIR='$state_dir'
    CONTEXT_PARTS=()

    # Harness rules: Tier 1 Seed + deferred Harness pointer
    if [ -f \"\$STATE_DIR/harness-rules.md\" ]; then
      RULES_CONTENT=\$(cat \"\$STATE_DIR/harness-rules.md\" 2>/dev/null)
      if [ -n \"\$RULES_CONTENT\" ]; then
        SEED_RULES=\$(grep '^\[Seed #' \"\$STATE_DIR/harness-rules.md\" 2>/dev/null)
        HARNESS_COUNT=\$(grep -c '^\[Harness #' \"\$STATE_DIR/harness-rules.md\" 2>/dev/null) || HARNESS_COUNT=0

        if [ -n \"\$SEED_RULES\" ]; then
          CONTEXT_PARTS+=(\"\$SEED_RULES\")
        fi
        if [ \"\$HARNESS_COUNT\" -gt 0 ]; then
          CONTEXT_PARTS+=(\"\${HARNESS_COUNT} auto-generated rules active. Read \$STATE_DIR/harness-rules.md before editing files.\")
        fi

        RULES_LINES=\$(echo \"\$RULES_CONTENT\" | wc -l | tr -d ' ')
        if [ \"\$RULES_LINES\" -gt 300 ]; then
          CONTEXT_PARTS+=(\"[GC_WARNING]\")
        fi
      fi
    fi

    # Synapse compact routing
    if [ -f \"\$STATE_DIR/manifest.json\" ]; then
      CONTEXT_PARTS+=('[Synapse] Keywords: \"until done/keep going\"->auto, \"deep analysis\"->analyze, \"code review\"->review, \"plan\"->plan, \"commit\"->git-commit. Medium+ tasks: form Scout/Architect/Builder/Inspector team.')
    fi

    for part in \"\${CONTEXT_PARTS[@]}\"; do
      echo \"\$part\"
    done
  " 2>/dev/null
}

echo ""
echo "=== setup-check.sh 3-Tier Lazy Context Tests ==="
echo ""

# --- Harness Rules Tests ---

# Test 1: Seed rules injected, Harness rules deferred
echo "--- Test 1: Seed rules injected, Harness rules deferred ---"
STATE=$(setup_state)
cat > "$STATE/harness-rules.md" <<'EOF'
[Seed #G1] Always read the target file before editing
[Seed #G2] When an edit fails with "not unique", include more context
[Seed #S1] Never add @MainActor to a protocol without checking
[Harness #1] Read Fastfile content before editing (auto-generated 2026-04-14)
[Harness #2] Run build/test after each edit batch (auto-generated 2026-04-14)
EOF
OUTPUT=$(run_setup_check "$STATE")
assert_contains "Seed G1 is injected" "[Seed #G1]" "$OUTPUT"
assert_contains "Seed G2 is injected" "[Seed #G2]" "$OUTPUT"
assert_contains "Seed S1 is injected" "[Seed #S1]" "$OUTPUT"
assert_not_contains "Harness #1 not directly injected" "[Harness #1]" "$OUTPUT"
assert_not_contains "Harness #2 not directly injected" "[Harness #2]" "$OUTPUT"
assert_contains "Harness pointer with count" "2 auto-generated rules active" "$OUTPUT"
assert_contains "Harness pointer has Read instruction" "Read" "$OUTPUT"

# Test 2: Only Harness rules (no Seeds) → pointer only
echo ""
echo "--- Test 2: Only Harness rules (no Seeds) → pointer only ---"
STATE=$(setup_state)
cat > "$STATE/harness-rules.md" <<'EOF'
[Harness #1] Read Fastfile before editing (auto-generated 2026-04-14)
[Harness #2] Run build after changes (auto-generated 2026-04-14)
[Harness #3] Check imports (auto-generated 2026-04-14)
EOF
OUTPUT=$(run_setup_check "$STATE")
assert_not_contains "No Seed in output" "[Seed #" "$OUTPUT"
assert_contains "Harness pointer with count 3" "3 auto-generated rules active" "$OUTPUT"

# Test 3: Only Seed rules (no Harness) → seeds injected, no pointer
echo ""
echo "--- Test 3: Only Seed rules → seeds injected, no pointer ---"
STATE=$(setup_state)
cat > "$STATE/harness-rules.md" <<'EOF'
[Seed #G1] Always read the target file before editing
[Seed #G2] When an edit fails, include more context
EOF
OUTPUT=$(run_setup_check "$STATE")
assert_contains "Seed G1 is injected" "[Seed #G1]" "$OUTPUT"
assert_contains "Seed G2 is injected" "[Seed #G2]" "$OUTPUT"
assert_not_contains "No harness pointer" "auto-generated rules active" "$OUTPUT"

# Test 4: Empty rules file → no output
echo ""
echo "--- Test 4: Empty rules file ---"
STATE=$(setup_state)
touch "$STATE/harness-rules.md"
OUTPUT=$(run_setup_check "$STATE")
assert_not_contains "Empty rules: no Seed output" "[Seed #" "$OUTPUT"
assert_not_contains "Empty rules: no Harness pointer" "auto-generated" "$OUTPUT"

# Test 5: No rules file → no output
echo ""
echo "--- Test 5: No rules file ---"
STATE=$(setup_state)
OUTPUT=$(run_setup_check "$STATE")
assert_not_contains "No file: no Seed output" "[Seed #" "$OUTPUT"
assert_not_contains "No file: no Harness pointer" "auto-generated" "$OUTPUT"

# Test 6: 300+ lines → GC warning
echo ""
echo "--- Test 6: 300+ lines → GC warning ---"
STATE=$(setup_state)
{
  echo "[Seed #G1] Always read the target file before editing"
  for i in $(seq 1 310); do
    printf '[Harness #%d] Test rule %d (auto-generated 2026-04-12)\n' "$i" "$i"
  done
} > "$STATE/harness-rules.md"
OUTPUT=$(run_setup_check "$STATE")
assert_contains "310 rules: GC warning present" "[GC_WARNING]" "$OUTPUT"
assert_contains "Seed still injected with many rules" "[Seed #G1]" "$OUTPUT"

# --- Synapse Routing Tests ---

# Test 7: Synapse compact routing injected when manifest exists
echo ""
echo "--- Test 7: Synapse compact routing ---"
STATE=$(setup_state)
touch "$STATE/harness-rules.md"
OUTPUT=$(run_setup_check "$STATE")
assert_contains "Synapse compact present" "[Synapse]" "$OUTPUT"
assert_contains "Synapse has keyword mapping" "auto" "$OUTPUT"
assert_contains "Synapse has team composition" "Scout/Architect/Builder/Inspector" "$OUTPUT"

# Test 8: Old Synapse full block is NOT present
echo ""
echo "--- Test 8: Old Synapse full block absent ---"
STATE=$(setup_state)
touch "$STATE/harness-rules.md"
OUTPUT=$(run_setup_check "$STATE")
assert_not_contains "No old Synapse header" "[Synapse Orchestrator]" "$OUTPUT"
assert_not_contains "No Mode Detection section" "## Mode Detection" "$OUTPUT"
assert_not_contains "No Team-based Execution section" "## Team-based Execution" "$OUTPUT"

echo ""
echo "=== Results ==="
printf "Passed: %d / %d\n" "$PASSED" "$TOTAL"
if [ "$FAILED" -gt 0 ]; then
  printf "${RED}Failed: %d${NC}\n" "$FAILED"
  exit 1
else
  printf "${GREEN}All tests passed!${NC}\n"
fi
