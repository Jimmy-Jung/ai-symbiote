#!/bin/bash
# Tests for manifest-defaults.sh.
#
# Usage: bash tests/test-manifest-defaults.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DEFAULTS_SCRIPT="$PROJECT_ROOT/shared/skills/setup/scripts/manifest-defaults.sh"

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
    printf "${RED}  FAIL${NC} %s\n    expected to contain: %s\n    actual: %s\n" "$desc" "$needle" "$haystack"
  fi
}

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

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

echo ""
echo "=== manifest-defaults.sh Tests ==="
echo ""

echo "--- Test 1: adds missing agentPlatforms ---"
cat > "$TMPDIR/manifest.json" <<'JSON'
{"project": {"languages": ["typescript"]}}
JSON
bash "$DEFAULTS_SCRIPT" --manifest "$TMPDIR/manifest.json" >/dev/null
PLATFORMS=$(python3 -c "import json; print(json.loads(open('$TMPDIR/manifest.json').read()).get('agentPlatforms', []))")
assert_contains "claude in agentPlatforms" "claude" "$PLATFORMS"
assert_contains "codex in agentPlatforms" "codex" "$PLATFORMS"
assert_contains "cursor in agentPlatforms" "cursor" "$PLATFORMS"

echo ""
echo "--- Test 2: preserves existing agentPlatforms ---"
cat > "$TMPDIR/manifest2.json" <<'JSON'
{"agentPlatforms": ["claude"]}
JSON
bash "$DEFAULTS_SCRIPT" --manifest "$TMPDIR/manifest2.json" >/dev/null
PLATFORMS2=$(python3 -c "import json; d=json.loads(open('$TMPDIR/manifest2.json').read()); print(len(d['agentPlatforms']))")
assert_eq "agentPlatforms has 3 entries" "3" "$PLATFORMS2"

echo ""
echo "--- Test 3: adds missing security.sessionSummaryLevel ---"
cat > "$TMPDIR/manifest3.json" <<'JSON'
{"project": {}}
JSON
bash "$DEFAULTS_SCRIPT" --manifest "$TMPDIR/manifest3.json" >/dev/null
LEVEL=$(python3 -c "import json; print(json.loads(open('$TMPDIR/manifest3.json').read())['security']['sessionSummaryLevel'])")
assert_eq "sessionSummaryLevel defaults to auto" "auto" "$LEVEL"

echo ""
echo "--- Test 4: preserves existing security settings ---"
cat > "$TMPDIR/manifest4.json" <<'JSON'
{"security": {"sessionSummaryLevel": "verbose", "extra": true}}
JSON
bash "$DEFAULTS_SCRIPT" --manifest "$TMPDIR/manifest4.json" >/dev/null
LEVEL2=$(python3 -c "import json; print(json.loads(open('$TMPDIR/manifest4.json').read())['security']['sessionSummaryLevel'])")
EXTRA=$(python3 -c "import json; print(json.loads(open('$TMPDIR/manifest4.json').read())['security']['extra'])")
assert_eq "preserves existing sessionSummaryLevel" "verbose" "$LEVEL2"
assert_eq "preserves extra security fields" "True" "$EXTRA"

echo ""
echo "--- Test 5: rejects non-list agentPlatforms ---"
cat > "$TMPDIR/manifest5.json" <<'JSON'
{"agentPlatforms": "invalid"}
JSON
bash "$DEFAULTS_SCRIPT" --manifest "$TMPDIR/manifest5.json" >/dev/null
PLATFORMS5=$(python3 -c "import json; d=json.loads(open('$TMPDIR/manifest5.json').read()); print(type(d['agentPlatforms']).__name__)")
assert_eq "invalid agentPlatforms replaced with list" "list" "$PLATFORMS5"

echo ""
echo "--- Test 6: rejects non-dict security ---"
cat > "$TMPDIR/manifest6.json" <<'JSON'
{"security": "invalid"}
JSON
bash "$DEFAULTS_SCRIPT" --manifest "$TMPDIR/manifest6.json" >/dev/null
SEC_TYPE=$(python3 -c "import json; d=json.loads(open('$TMPDIR/manifest6.json').read()); print(type(d['security']).__name__)")
assert_eq "invalid security replaced with dict" "dict" "$SEC_TYPE"

echo ""
echo "--- Test 7: fails on missing file ---"
if bash "$DEFAULTS_SCRIPT" --manifest "$TMPDIR/nonexistent.json" 2>/dev/null; then
  TOTAL=$((TOTAL + 1))
  FAILED=$((FAILED + 1))
  printf "${RED}  FAIL${NC} exits non-zero for missing file\n"
else
  TOTAL=$((TOTAL + 1))
  PASSED=$((PASSED + 1))
  printf "${GREEN}  PASS${NC} exits non-zero for missing file\n"
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
