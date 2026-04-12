#!/bin/bash
# Static validation tests for dev-docs skill contract.
#
# Usage: bash tests/test-dev-docs-skill.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL_FILE="$PROJECT_ROOT/shared/skills/dev-docs/SKILL.md"
README_FILE="$PROJECT_ROOT/README.md"
ARCH_FILE="$PROJECT_ROOT/docs/ARCHITECTURE.md"
CONV_FILE="$PROJECT_ROOT/docs/CONVENTIONS.md"
ONBOARD_FILE="$PROJECT_ROOT/docs/ONBOARDING.md"
DEPS_FILE="$PROJECT_ROOT/docs/DEPENDENCIES.md"
FLOWS_FILE="$PROJECT_ROOT/docs/FLOWS.md"

PASSED=0
FAILED=0
TOTAL=0

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

assert_contains() {
  local desc="$1" needle="$2" file="$3"
  TOTAL=$((TOTAL + 1))
  if grep -qF "$needle" "$file" 2>/dev/null; then
    PASSED=$((PASSED + 1))
    printf "${GREEN}  PASS${NC} %s\n" "$desc"
  else
    FAILED=$((FAILED + 1))
    printf "${RED}  FAIL${NC} %s\n    missing: %s\n    file: %s\n" "$desc" "$needle" "$file"
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

echo ""
echo "=== dev-docs Skill Validation ==="
echo ""

assert_contains "skill file exists" "name: dev-docs" "$SKILL_FILE"
assert_contains "skill is user-invocable" "user-invocable: true" "$SKILL_FILE"
assert_contains "skill has argument hint" "argument-hint: \"[all|readme|architecture|conventions|onboarding|dependencies|flows]\"" "$SKILL_FILE"
assert_contains "skill defines marker contract" "<!-- AI-SYMBIOTE:START <doc-id>:<section-id> -->" "$SKILL_FILE"
assert_contains "skill defines confidence fallback" "## Confidence-Based Fallback" "$SKILL_FILE"
assert_contains "skill documents simple evidence gates" "build flow diagrams require \`scripts/build-*.sh\`" "$SKILL_FILE"
assert_contains "skill defines internal pipeline" "## Internal Pipeline" "$SKILL_FILE"
assert_contains "skill defines scan phase" "### 1. Scan" "$SKILL_FILE"
assert_contains "skill defines model phase" "### 2. Model" "$SKILL_FILE"
assert_contains "skill defines render phase" "### 3. Render / Update" "$SKILL_FILE"
assert_contains "skill references updater helper" "scripts/update-doc-section.sh" "$SKILL_FILE"
assert_contains "skill references generator helper" "scripts/generate-dev-docs.sh" "$SKILL_FILE"
assert_contains "skill covers README doc target" "| \`readme\` | \`README.md\` |" "$SKILL_FILE"
assert_contains "skill covers architecture doc target" "| \`architecture\` | \`docs/ARCHITECTURE.md\` |" "$SKILL_FILE"
assert_contains "skill covers conventions doc target" "| \`conventions\` | \`docs/CONVENTIONS.md\` |" "$SKILL_FILE"
assert_contains "skill covers onboarding doc target" "| \`onboarding\` | \`docs/ONBOARDING.md\` |" "$SKILL_FILE"
assert_contains "skill covers dependencies doc target" "| \`dependencies\` | \`docs/DEPENDENCIES.md\` |" "$SKILL_FILE"
assert_contains "skill covers flows doc target" "| \`flows\` | \`docs/FLOWS.md\` |" "$SKILL_FILE"
assert_contains "skill requires fixture regression tests" "fixture/golden regression test" "$SKILL_FILE"
assert_contains "skill requires selective update isolation tests" "selective update isolation test" "$SKILL_FILE"
assert_contains "skill requires updater integration tests" "updater integration test" "$SKILL_FILE"
assert_contains "skill requires generator smoke test" "generator integration smoke test" "$SKILL_FILE"
assert_contains "skill requires selective update isolation tests in spec" "selective update isolation test for \`flows\` and \`architecture\`" "$SKILL_FILE"
assert_contains "skill requires low-confidence fallback tests in spec" "low-confidence fallback test that emits \`확인 필요\`" "$SKILL_FILE"

SKILL_COUNT=$(find "$PROJECT_ROOT/shared/skills" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
assert_eq "README skill count matches directory count" "27" "$SKILL_COUNT"
assert_contains "README skill count updated" "## 스킬 목록 (27개)" "$README_FILE"
assert_contains "README utility table lists dev-docs" "| \`dev-docs\` | 코드 기준으로 README/docs 문서를 Mermaid 중심으로 생성·갱신 |" "$README_FILE"
assert_contains "README tree skill count updated" "│   ├── skills/                #   27개 스킬" "$README_FILE"
assert_contains "ARCHITECTURE skill count updated" "27개 스킬 정의" "$ARCH_FILE"
assert_contains "README links conventions doc" "[docs/CONVENTIONS.md](docs/CONVENTIONS.md)" "$README_FILE"
assert_contains "README links onboarding doc" "[docs/ONBOARDING.md](docs/ONBOARDING.md)" "$README_FILE"
assert_contains "README links dependencies doc" "[docs/DEPENDENCIES.md](docs/DEPENDENCIES.md)" "$README_FILE"
assert_contains "README links flows doc" "[docs/FLOWS.md](docs/FLOWS.md)" "$README_FILE"
assert_contains "README docs-map marker start exists" "<!-- AI-SYMBIOTE:START readme:docs-map -->" "$README_FILE"
assert_contains "README docs-map marker end exists" "<!-- AI-SYMBIOTE:END readme:docs-map -->" "$README_FILE"
assert_contains "ARCHITECTURE subsystems marker exists" "<!-- AI-SYMBIOTE:START architecture:subsystems -->" "$ARCH_FILE"
assert_contains "ARCHITECTURE build-flow marker exists" "<!-- AI-SYMBIOTE:START architecture:build-flow -->" "$ARCH_FILE"

assert_contains "CONVENTIONS has marker" "<!-- AI-SYMBIOTE:START conventions:decision-tree -->" "$CONV_FILE"
assert_contains "ONBOARDING has marker" "<!-- AI-SYMBIOTE:START onboarding:first-day-path -->" "$ONBOARD_FILE"
assert_contains "DEPENDENCIES has marker" "<!-- AI-SYMBIOTE:START dependencies:dependency-map -->" "$DEPS_FILE"
assert_contains "FLOWS has marker" "<!-- AI-SYMBIOTE:START flows:system-flow -->" "$FLOWS_FILE"
assert_contains "CONVENTIONS uses mermaid" '```mermaid' "$CONV_FILE"
assert_contains "ONBOARDING uses mermaid" '```mermaid' "$ONBOARD_FILE"
assert_contains "DEPENDENCIES uses mermaid" '```mermaid' "$DEPS_FILE"
assert_contains "FLOWS uses mermaid" '```mermaid' "$FLOWS_FILE"

echo ""
echo "=== Summary ==="
printf "Total: %d  Passed: %d  Failed: %d\n" "$TOTAL" "$PASSED" "$FAILED"
echo ""

if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
