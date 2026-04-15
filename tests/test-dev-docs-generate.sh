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
mkdir -p "$TMPDIR/shared/harness-seeds"
mkdir -p "$TMPDIR/platforms/claude/overlay" "$TMPDIR/platforms/codex/overlay"
mkdir -p "$TMPDIR/scripts" "$TMPDIR/docs" "$TMPDIR/tests"
printf '0.0.0-test\n' > "$TMPDIR/VERSION"

cat > "$TMPDIR/README.md" <<'EOF'
# Temp Repo

Manual intro

## 개발자 문서

Manual docs note
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

touch "$TMPDIR/shared/hooks/scripts/setup-check.sh"
touch "$TMPDIR/shared/hooks/scripts/guard-shell.sh"
touch "$TMPDIR/shared/harness-seeds/generic.md"
touch "$TMPDIR/tests/test-smoke.sh"

cat > "$TMPDIR/docs/02-아키텍처.md" <<'EOF'
# 02. 아키텍처

Manual architecture note
EOF

bash "$GENERATOR" "$TMPDIR" all >/dev/null

assert_contains "README got docs marker" "<!-- AI-SYMBIOTE:START readme:docs-map -->" "$TMPDIR/README.md"
assert_contains "README links operations doc" "[docs/07-운영-흐름-및-배포.md](docs/07-운영-흐름-및-배포.md)" "$TMPDIR/README.md"
assert_contains "README keeps manual prose" "Manual intro" "$TMPDIR/README.md"

assert_contains "start doc created" "<!-- AI-SYMBIOTE:START start:quick-start -->" "$TMPDIR/docs/00-시작하기.md"
assert_contains "overview doc created" "<!-- AI-SYMBIOTE:START overview:project-summary -->" "$TMPDIR/docs/01-프로젝트-개요.md"
assert_contains "architecture marker created" "<!-- AI-SYMBIOTE:START architecture:subsystems -->" "$TMPDIR/docs/02-아키텍처.md"
assert_contains "architecture keeps manual prose" "Manual architecture note" "$TMPDIR/docs/02-아키텍처.md"
assert_contains "build doc created" "<!-- AI-SYMBIOTE:START build:toolchain -->" "$TMPDIR/docs/03-빌드-및-실행.md"
assert_contains "features doc created" "<!-- AI-SYMBIOTE:START features:harness-pillars -->" "$TMPDIR/docs/04-주요-기능.md"
assert_contains "conventions doc created" "<!-- AI-SYMBIOTE:START conventions:decision-tree -->" "$TMPDIR/docs/05-코딩-컨벤션.md"
assert_contains "troubleshooting doc created" "<!-- AI-SYMBIOTE:START troubleshooting:quick-diagnosis -->" "$TMPDIR/docs/06-문제해결-가이드.md"
assert_contains "operations doc created" "<!-- AI-SYMBIOTE:START operations:request-flow -->" "$TMPDIR/docs/07-운영-흐름-및-배포.md"
assert_contains "operations uses Mermaid" '```mermaid' "$TMPDIR/docs/07-운영-흐름-및-배포.md"

echo ""
echo "--- Selective update isolation: operations only ---"
ISO="$TMPDIR/isolation"
mkdir -p "$ISO/shared/skills/alpha" "$ISO/shared/hooks/scripts" "$ISO/shared/harness-seeds" "$ISO/platforms/claude/overlay" "$ISO/scripts" "$ISO/docs" "$ISO/tests"
printf '0.0.0-test\n' > "$ISO/VERSION"
cat > "$ISO/README.md" <<'EOF'
# Temp Repo
EOF
cat > "$ISO/docs/02-아키텍처.md" <<'EOF'
# 02. 아키텍처

Manual arch only
EOF
cat > "$ISO/scripts/build-all.sh" <<'EOF'
#!/usr/bin/env bash
echo build-all
EOF
touch "$ISO/shared/hooks/scripts/setup-check.sh"
touch "$ISO/shared/harness-seeds/generic.md"
bash "$GENERATOR" "$ISO" operations >/dev/null
assert_contains "operations-only creates operations doc" "<!-- AI-SYMBIOTE:START operations:request-flow -->" "$ISO/docs/07-운영-흐름-및-배포.md"
assert_contains "operations-only keeps architecture manual-only" "Manual arch only" "$ISO/docs/02-아키텍처.md"
if grep -qF -- "<!-- AI-SYMBIOTE:START architecture:subsystems -->" "$ISO/docs/02-아키텍처.md" 2>/dev/null; then
  TOTAL=$((TOTAL + 1))
  FAILED=$((FAILED + 1))
  printf "${RED}  FAIL${NC} operations-only should not inject architecture markers\n"
else
  TOTAL=$((TOTAL + 1))
  PASSED=$((PASSED + 1))
  printf "${GREEN}  PASS${NC} operations-only should not inject architecture markers\n"
fi

echo ""
echo "--- Selective update isolation: architecture only ---"
ISO_ARCH="$TMPDIR/isolation-architecture"
mkdir -p "$ISO_ARCH/shared/skills/alpha" "$ISO_ARCH/shared/hooks/scripts" "$ISO_ARCH/shared/harness-seeds" "$ISO_ARCH/platforms/claude/overlay" "$ISO_ARCH/platforms/codex/overlay" "$ISO_ARCH/scripts" "$ISO_ARCH/docs" "$ISO_ARCH/tests"
printf '0.0.0-test\n' > "$ISO_ARCH/VERSION"
cat > "$ISO_ARCH/README.md" <<'EOF'
# Temp Repo
EOF
cat > "$ISO_ARCH/docs/07-운영-흐름-및-배포.md" <<'EOF'
# 07. 운영 흐름 및 배포

Manual operations only
EOF
cat > "$ISO_ARCH/scripts/build-all.sh" <<'EOF'
#!/usr/bin/env bash
echo build-all
EOF
cat > "$ISO_ARCH/scripts/build-claude.sh" <<'EOF'
#!/usr/bin/env bash
echo build-claude
EOF
touch "$ISO_ARCH/shared/hooks/scripts/setup-check.sh"
touch "$ISO_ARCH/shared/harness-seeds/generic.md"
bash "$GENERATOR" "$ISO_ARCH" architecture >/dev/null
assert_contains "architecture-only creates architecture doc" "<!-- AI-SYMBIOTE:START architecture:subsystems -->" "$ISO_ARCH/docs/02-아키텍처.md"
assert_contains "architecture-only keeps operations manual-only" "Manual operations only" "$ISO_ARCH/docs/07-운영-흐름-및-배포.md"
if grep -qF -- "<!-- AI-SYMBIOTE:START operations:request-flow -->" "$ISO_ARCH/docs/07-운영-흐름-및-배포.md" 2>/dev/null; then
  TOTAL=$((TOTAL + 1))
  FAILED=$((FAILED + 1))
  printf "${RED}  FAIL${NC} architecture-only should not inject operations markers\n"
else
  TOTAL=$((TOTAL + 1))
  PASSED=$((PASSED + 1))
  printf "${GREEN}  PASS${NC} architecture-only should not inject operations markers\n"
fi

echo ""
echo "--- Low-confidence fallback ---"
FALLBACK="$TMPDIR/fallback"
mkdir -p "$FALLBACK/shared/skills/alpha" "$FALLBACK/shared/hooks/scripts" "$FALLBACK/docs"
printf '0.0.0-test\n' > "$FALLBACK/VERSION"
cat > "$FALLBACK/README.md" <<'EOF'
# Temp Repo
EOF
bash "$GENERATOR" "$FALLBACK" build operations >/dev/null
assert_contains "build fallback emitted" "### 확인 필요: 빌드 흐름" "$FALLBACK/docs/03-빌드-및-실행.md"
assert_contains "operations fallback emitted" "### 확인 필요: CI와 릴리즈 흐름" "$FALLBACK/docs/07-운영-흐름-및-배포.md"

echo ""
echo "--- Explicit English fallback mode ---"
ENGLISH="$TMPDIR/english-fallback"
mkdir -p "$ENGLISH/shared/skills/alpha" "$ENGLISH/shared/hooks/scripts" "$ENGLISH/docs"
printf '0.0.0-test\n' > "$ENGLISH/VERSION"
cat > "$ENGLISH/README.md" <<'EOF'
# Temp Repo
EOF
AI_SYMBIOTE_DOC_LANG=en bash "$GENERATOR" "$ENGLISH" readme build operations >/dev/null
assert_contains "english readme intro emitted" "README is the hub. The numbered docs are the real onboarding path." "$ENGLISH/README.md"
assert_contains "english build fallback emitted" "### Needs verification: 빌드 흐름" "$ENGLISH/docs/03-빌드-및-실행.md"
assert_contains "english operations fallback emitted" "- Check next: related scripts, overlays, existing docs" "$ENGLISH/docs/07-운영-흐름-및-배포.md"

echo ""
echo "--- Explicit English full-doc mode ---"
ENGLISH_FULL="$TMPDIR/english-full"
mkdir -p "$ENGLISH_FULL/shared/skills/alpha" "$ENGLISH_FULL/shared/skills/beta"
mkdir -p "$ENGLISH_FULL/shared/hooks/scripts" "$ENGLISH_FULL/shared/harness-seeds"
mkdir -p "$ENGLISH_FULL/platforms/claude/overlay" "$ENGLISH_FULL/platforms/codex/overlay"
mkdir -p "$ENGLISH_FULL/scripts" "$ENGLISH_FULL/docs" "$ENGLISH_FULL/tests"
printf '0.0.0-test\n' > "$ENGLISH_FULL/VERSION"
cat > "$ENGLISH_FULL/README.md" <<'EOF'
# Temp Repo
EOF
cat > "$ENGLISH_FULL/scripts/build-all.sh" <<'EOF'
#!/usr/bin/env bash
echo build-all
EOF
cat > "$ENGLISH_FULL/scripts/build-claude.sh" <<'EOF'
#!/usr/bin/env bash
echo build-claude
EOF
cat > "$ENGLISH_FULL/scripts/build-codex.sh" <<'EOF'
#!/usr/bin/env bash
echo build-codex
EOF
touch "$ENGLISH_FULL/shared/hooks/scripts/setup-check.sh"
touch "$ENGLISH_FULL/shared/hooks/scripts/guard-shell.sh"
touch "$ENGLISH_FULL/shared/harness-seeds/generic.md"
touch "$ENGLISH_FULL/tests/test-smoke.sh"
AI_SYMBIOTE_DOC_LANG=en bash "$GENERATOR" "$ENGLISH_FULL" all >/dev/null
assert_contains "english start title emitted" "# 00. Getting Started" "$ENGLISH_FULL/docs/00-시작하기.md"
assert_contains "english start heading emitted" "## Quick Start" "$ENGLISH_FULL/docs/00-시작하기.md"
assert_contains "english overview heading emitted" "## At a Glance" "$ENGLISH_FULL/docs/01-프로젝트-개요.md"
assert_contains "english architecture heading emitted" "## System Overview" "$ENGLISH_FULL/docs/02-아키텍처.md"
assert_contains "english build heading emitted" "## Required Tools" "$ENGLISH_FULL/docs/03-빌드-및-실행.md"
assert_contains "english features heading emitted" "## Harness Pillars" "$ENGLISH_FULL/docs/04-주요-기능.md"
assert_contains "english conventions heading emitted" "## Editing Rules" "$ENGLISH_FULL/docs/05-코딩-컨벤션.md"
assert_contains "english troubleshooting heading emitted" "## Quick Diagnosis" "$ENGLISH_FULL/docs/06-문제해결-가이드.md"
assert_contains "english operations heading emitted" "## Request Flow" "$ENGLISH_FULL/docs/07-운영-흐름-및-배포.md"

echo ""
echo "=== Summary ==="
printf "Total: %d  Passed: %d  Failed: %d\n" "$TOTAL" "$PASSED" "$FAILED"
echo ""

if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
