#!/bin/bash
# Integration tests for dev-docs generator.
#
# Usage: bash tests/test-dev-docs-generate.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GENERATOR="$PROJECT_ROOT/shared/skills/dev-docs/scripts/generate-dev-docs.sh"

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
    printf "${RED}  FAIL${NC} %s\n    missing: %s\n    file: %s\n" "$desc" "$needle" "$file"
  fi
}

echo ""
echo "=== dev-docs Generator Tests ==="
echo ""

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/shared/skills/alpha" "$TMPDIR/shared/skills/beta"
mkdir -p "$TMPDIR/shared/hooks/scripts"
mkdir -p "$TMPDIR/platforms/claude/overlay" "$TMPDIR/platforms/codex/overlay"
mkdir -p "$TMPDIR/scripts" "$TMPDIR/docs"

cat > "$TMPDIR/README.md" <<'EOF'
# Temp Repo

Manual intro

## 개발자 문서

Manual docs note
EOF

cat > "$TMPDIR/docs/ARCHITECTURE.md" <<'EOF'
# Architecture

## Core

Manual architecture note

## Build Flow

Manual build note
EOF

cat > "$TMPDIR/scripts/build-all.sh" <<'EOF'
#!/usr/bin/env bash
echo build-all
EOF

cat > "$TMPDIR/scripts/build-claude.sh" <<'EOF'
#!/usr/bin/env bash
echo build-claude
EOF

cat > "$TMPDIR/scripts/build-codex.sh" <<'EOF'
#!/usr/bin/env bash
echo build-codex
EOF

cat > "$TMPDIR/docs/MESSENGER.md" <<'EOF'
# Messenger
EOF

touch "$TMPDIR/shared/hooks/scripts/setup-check.sh"
touch "$TMPDIR/shared/hooks/scripts/guard-shell.sh"

bash "$GENERATOR" "$TMPDIR" all >/dev/null

assert_contains "README got docs marker" "<!-- AI-SYMBIOTE:START readme:docs-map -->" "$TMPDIR/README.md"
assert_contains "README links flows doc" "[docs/FLOWS.md](docs/FLOWS.md)" "$TMPDIR/README.md"
assert_contains "README keeps manual prose" "Manual intro" "$TMPDIR/README.md"

assert_contains "ARCHITECTURE got subsystems marker" "<!-- AI-SYMBIOTE:START architecture:subsystems -->" "$TMPDIR/docs/ARCHITECTURE.md"
assert_contains "ARCHITECTURE reflects skill count" "2개 스킬 정의" "$TMPDIR/docs/ARCHITECTURE.md"
assert_contains "ARCHITECTURE keeps manual prose" "Manual architecture note" "$TMPDIR/docs/ARCHITECTURE.md"

assert_contains "CONVENTIONS created" "<!-- AI-SYMBIOTE:START conventions:decision-tree -->" "$TMPDIR/docs/CONVENTIONS.md"
assert_contains "ONBOARDING created" "<!-- AI-SYMBIOTE:START onboarding:first-day-path -->" "$TMPDIR/docs/ONBOARDING.md"
assert_contains "DEPENDENCIES created" "<!-- AI-SYMBIOTE:START dependencies:dependency-map -->" "$TMPDIR/docs/DEPENDENCIES.md"
assert_contains "FLOWS created" "<!-- AI-SYMBIOTE:START flows:system-flow -->" "$TMPDIR/docs/FLOWS.md"
assert_contains "FLOWS uses Mermaid" '```mermaid' "$TMPDIR/docs/FLOWS.md"

# selective update isolation: flows only should not touch architecture markers
echo ""
echo "--- Selective update isolation: flows only ---"
ISO="$TMPDIR/isolation"
mkdir -p "$ISO/shared/skills/alpha" "$ISO/shared/hooks/scripts" "$ISO/platforms/claude/overlay" "$ISO/scripts" "$ISO/docs"
cat > "$ISO/README.md" <<'EOF'
# Temp Repo
EOF
cat > "$ISO/docs/ARCHITECTURE.md" <<'EOF'
# Architecture

Manual arch only
EOF
cat > "$ISO/scripts/build-all.sh" <<'EOF'
#!/usr/bin/env bash
echo build-all
EOF
bash "$GENERATOR" "$ISO" flows >/dev/null
assert_contains "flows-only creates flows doc" "<!-- AI-SYMBIOTE:START flows:system-flow -->" "$ISO/docs/FLOWS.md"
assert_contains "flows-only keeps architecture manual-only" "Manual arch only" "$ISO/docs/ARCHITECTURE.md"
if grep -qF -- "<!-- AI-SYMBIOTE:START architecture:subsystems -->" "$ISO/docs/ARCHITECTURE.md" 2>/dev/null; then
  TOTAL=$((TOTAL + 1))
  FAILED=$((FAILED + 1))
  printf "${RED}  FAIL${NC} flows-only should not inject architecture markers\n"
else
  TOTAL=$((TOTAL + 1))
  PASSED=$((PASSED + 1))
  printf "${GREEN}  PASS${NC} flows-only should not inject architecture markers\n"
fi

# low-confidence fallback: no build scripts, no overlays
echo ""
echo "--- Low-confidence fallback ---"
FALLBACK="$TMPDIR/fallback"
mkdir -p "$FALLBACK/shared/skills/alpha" "$FALLBACK/shared/hooks/scripts" "$FALLBACK/docs"
cat > "$FALLBACK/README.md" <<'EOF'
# Temp Repo
EOF
bash "$GENERATOR" "$FALLBACK" architecture flows >/dev/null
assert_contains "architecture fallback emitted" "### 확인 필요: 빌드 흐름" "$FALLBACK/docs/ARCHITECTURE.md"
assert_contains "flows fallback emitted" "### 확인 필요: 사용자 / 운영자 흐름" "$FALLBACK/docs/FLOWS.md"

echo ""
echo "=== Summary ==="
printf "Total: %d  Passed: %d  Failed: %d\n" "$TOTAL" "$PASSED" "$FAILED"
echo ""

if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
