#!/bin/bash
# Static validation tests for dev-docs skill contract.
#
# Usage: bash tests/test-dev-docs-skill.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL_FILE="$PROJECT_ROOT/shared/skills/dev-docs/SKILL.md"
README_FILE="$PROJECT_ROOT/README.md"
START_FILE="$PROJECT_ROOT/docs/00-시작하기.md"
OVERVIEW_FILE="$PROJECT_ROOT/docs/01-프로젝트-개요.md"
ARCH_FILE="$PROJECT_ROOT/docs/02-아키텍처.md"
BUILD_FILE="$PROJECT_ROOT/docs/03-빌드-및-실행.md"
FEATURES_FILE="$PROJECT_ROOT/docs/04-주요-기능.md"
CONV_FILE="$PROJECT_ROOT/docs/05-코딩-컨벤션.md"
TROUBLE_FILE="$PROJECT_ROOT/docs/06-문제해결-가이드.md"
OPS_FILE="$PROJECT_ROOT/docs/07-운영-흐름-및-배포.md"

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
echo "=== dev-docs Skill Validation ==="
echo ""

assert_contains "skill file exists" "name: dev-docs" "$SKILL_FILE"
assert_contains "skill is user-invocable" "user-invocable: true" "$SKILL_FILE"
assert_contains "skill keeps skill source in English" "skill source (\`SKILL.md\`, tests, helper contracts) stays in English" "$SKILL_FILE"
assert_contains "skill output follows user language" "generated docs must follow the user's language" "$SKILL_FILE"
assert_contains "skill prefers explicit language request first" "1. explicit user request about output language" "$SKILL_FILE"
assert_contains "skill uses conversation language next" "2. the current conversation language" "$SKILL_FILE"
assert_contains "skill fallback generator env var" "\`generate-dev-docs.sh\` may receive \`AI_SYMBIOTE_DOC_LANG=ko|en\`" "$SKILL_FILE"
assert_contains "skill localizes headings and prose" "headings, prose, tables, Mermaid labels, and fallback blocks must follow the resolved user language" "$SKILL_FILE"
assert_contains "skill keeps numbered filenames stable" "file paths and numbered filenames stay stable to match repo conventions" "$SKILL_FILE"
assert_contains "skill has numbered argument hint" "argument-hint: \"[all|readme|start|overview|architecture|build|features|conventions|troubleshooting|operations]\"" "$SKILL_FILE"
assert_contains "skill defines start doc path" "| \`start\` | \`docs/00-시작하기.md\` |" "$SKILL_FILE"
assert_contains "skill defines overview doc path" "| \`overview\` | \`docs/01-프로젝트-개요.md\` |" "$SKILL_FILE"
assert_contains "skill defines architecture doc path" "| \`architecture\` | \`docs/02-아키텍처.md\` |" "$SKILL_FILE"
assert_contains "skill defines build doc path" "| \`build\` | \`docs/03-빌드-및-실행.md\` |" "$SKILL_FILE"
assert_contains "skill defines features doc path" "| \`features\` | \`docs/04-주요-기능.md\` |" "$SKILL_FILE"
assert_contains "skill defines conventions doc path" "| \`conventions\` | \`docs/05-코딩-컨벤션.md\` |" "$SKILL_FILE"
assert_contains "skill defines troubleshooting doc path" "| \`troubleshooting\` | \`docs/06-문제해결-가이드.md\` |" "$SKILL_FILE"
assert_contains "skill defines operations doc path" "| \`operations\` | \`docs/07-운영-흐름-및-배포.md\` |" "$SKILL_FILE"
assert_contains "skill defines onboarding alias" "- \`onboarding\` -> \`start\`" "$SKILL_FILE"
assert_contains "skill defines dependencies alias" "- \`dependencies\` -> \`build\`" "$SKILL_FILE"
assert_contains "skill defines flows alias" "- \`flows\` -> \`operations\`" "$SKILL_FILE"
assert_contains "skill requires selective update isolation" "dev-docs operations" "$SKILL_FILE"
assert_contains "skill references fallback generator" "generate-dev-docs.sh" "$SKILL_FILE"
assert_contains "skill render localizes mermaid labels" "Labels must follow the resolved user language." "$SKILL_FILE"
assert_contains "skill render keeps filenames unchanged" "keep numbered doc file names and links unchanged even when the rendered language is English" "$SKILL_FILE"

assert_contains "README links start doc" "[docs/00-시작하기.md](docs/00-시작하기.md)" "$README_FILE"
assert_contains "README links overview doc" "[docs/01-프로젝트-개요.md](docs/01-프로젝트-개요.md)" "$README_FILE"
assert_contains "README links architecture doc" "[docs/02-아키텍처.md](docs/02-아키텍처.md)" "$README_FILE"
assert_contains "README links build doc" "[docs/03-빌드-및-실행.md](docs/03-빌드-및-실행.md)" "$README_FILE"
assert_contains "README links features doc" "[docs/04-주요-기능.md](docs/04-주요-기능.md)" "$README_FILE"
assert_contains "README links conventions doc" "[docs/05-코딩-컨벤션.md](docs/05-코딩-컨벤션.md)" "$README_FILE"
assert_contains "README links troubleshooting doc" "[docs/06-문제해결-가이드.md](docs/06-문제해결-가이드.md)" "$README_FILE"
assert_contains "README links operations doc" "[docs/07-운영-흐름-및-배포.md](docs/07-운영-흐름-및-배포.md)" "$README_FILE"
assert_contains "README docs-map marker exists" "<!-- AI-SYMBIOTE:START readme:docs-map -->" "$README_FILE"

assert_contains "start quick-start marker exists" "<!-- AI-SYMBIOTE:START start:quick-start -->" "$START_FILE"
assert_contains "overview project-summary marker exists" "<!-- AI-SYMBIOTE:START overview:project-summary -->" "$OVERVIEW_FILE"
assert_contains "architecture system-overview marker exists" "<!-- AI-SYMBIOTE:START architecture:system-overview -->" "$ARCH_FILE"
assert_contains "build toolchain marker exists" "<!-- AI-SYMBIOTE:START build:toolchain -->" "$BUILD_FILE"
assert_contains "features harness marker exists" "<!-- AI-SYMBIOTE:START features:harness-pillars -->" "$FEATURES_FILE"
assert_contains "conventions decision-tree marker exists" "<!-- AI-SYMBIOTE:START conventions:decision-tree -->" "$CONV_FILE"
assert_contains "troubleshooting diagnosis marker exists" "<!-- AI-SYMBIOTE:START troubleshooting:quick-diagnosis -->" "$TROUBLE_FILE"
assert_contains "operations request-flow marker exists" "<!-- AI-SYMBIOTE:START operations:request-flow -->" "$OPS_FILE"
assert_contains "operations uses mermaid" '```mermaid' "$OPS_FILE"

echo ""
echo "=== Summary ==="
printf "Total: %d  Passed: %d  Failed: %d\n" "$TOTAL" "$PASSED" "$FAILED"
echo ""

if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
