#!/bin/bash
# Integration tests for dev-docs marker block updater.
#
# Usage: bash tests/test-dev-docs-updater.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
UPDATER="$PROJECT_ROOT/shared/skills/dev-docs/scripts/update-doc-section.sh"

PASSED=0
FAILED=0
TOTAL=0

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

assert_contains() {
  local desc="$1" needle="$2" file="$3"
  TOTAL=$((TOTAL + 1))
  if grep -qF -- "$needle" "$file" 2>/dev/null; then
    PASSED=$((PASSED + 1))
    printf "${GREEN}  PASS${NC} %s\n" "$desc"
  else
    FAILED=$((FAILED + 1))
    printf "${RED}  FAIL${NC} %s\n    missing: %s\n" "$desc" "$needle"
  fi
}

assert_not_contains() {
  local desc="$1" needle="$2" file="$3"
  TOTAL=$((TOTAL + 1))
  if grep -qF -- "$needle" "$file" 2>/dev/null; then
    FAILED=$((FAILED + 1))
    printf "${RED}  FAIL${NC} %s\n    unexpected: %s\n" "$desc" "$needle"
  else
    PASSED=$((PASSED + 1))
    printf "${GREEN}  PASS${NC} %s\n" "$desc"
  fi
}

echo ""
echo "=== dev-docs Updater Tests ==="
echo ""

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

write_content() {
  local file="$1"
  shift
  printf '%s\n' "$@" > "$file"
}

# Test 1: create file with heading + marker block
echo "--- Test 1: create missing file ---"
TARGET="$TMPDIR/create.md"
CONTENT="$TMPDIR/content-1.md"
write_content "$CONTENT" "- generated line" "- second line"
bash "$UPDATER" "$TARGET" readme docs-map "## 개발자 문서" "$CONTENT"
assert_contains "missing file gets heading" "## 개발자 문서" "$TARGET"
assert_contains "missing file gets start marker" "<!-- AI-SYMBIOTE:START readme:docs-map -->" "$TARGET"
assert_contains "missing file gets content" "- generated line" "$TARGET"

# Test 2: replace existing marker block and preserve manual prose
echo ""
echo "--- Test 2: replace existing block in place ---"
TARGET="$TMPDIR/replace.md"
cat > "$TARGET" <<'EOF'
# Title

Manual intro

## 개발자 문서

<!-- AI-SYMBIOTE:START readme:docs-map -->
old generated line
<!-- AI-SYMBIOTE:END readme:docs-map -->

Manual outro
EOF
CONTENT="$TMPDIR/content-2.md"
write_content "$CONTENT" "new generated line"
bash "$UPDATER" "$TARGET" readme docs-map "## 개발자 문서" "$CONTENT"
assert_contains "manual intro preserved" "Manual intro" "$TARGET"
assert_contains "manual outro preserved" "Manual outro" "$TARGET"
assert_contains "new content inserted" "new generated line" "$TARGET"
assert_not_contains "old generated content removed" "old generated line" "$TARGET"

# Test 3: insert under existing heading when marker is missing
echo ""
echo "--- Test 3: insert after heading ---"
TARGET="$TMPDIR/insert.md"
cat > "$TARGET" <<'EOF'
# Title

## 개발자 문서

Manual body
EOF
CONTENT="$TMPDIR/content-3.md"
write_content "$CONTENT" "inserted line"
bash "$UPDATER" "$TARGET" readme docs-map "## 개발자 문서" "$CONTENT"
assert_contains "marker inserted after heading" "<!-- AI-SYMBIOTE:START readme:docs-map -->" "$TARGET"
assert_contains "inserted content present" "inserted line" "$TARGET"
assert_contains "manual body preserved" "Manual body" "$TARGET"

# Test 4: append heading and block if heading is missing
echo ""
echo "--- Test 4: append when heading missing ---"
TARGET="$TMPDIR/append.md"
cat > "$TARGET" <<'EOF'
# Title

Manual only
EOF
CONTENT="$TMPDIR/content-4.md"
write_content "$CONTENT" "appended line"
bash "$UPDATER" "$TARGET" dependencies dependency-map "## 의존성 맵" "$CONTENT"
assert_contains "missing heading appended" "## 의존성 맵" "$TARGET"
assert_contains "appended marker present" "<!-- AI-SYMBIOTE:START dependencies:dependency-map -->" "$TARGET"
assert_contains "appended content present" "appended line" "$TARGET"

echo ""
echo "=== Summary ==="
printf "Total: %d  Passed: %d  Failed: %d\n" "$TOTAL" "$PASSED" "$FAILED"
echo ""

if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
