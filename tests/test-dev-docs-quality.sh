#!/usr/bin/env bash
# Validate marker block content quality after SKILL.md workflow execution.
# Checks minimum line counts per section (conservative: ~50% of Success Criteria targets).
#
# This test is meaningful ONLY after the dev-docs SKILL.md workflow has run.
# Running after generate-dev-docs.sh (fallback) will produce expected failures.
#
# Usage: bash tests/test-dev-docs-quality.sh

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'
PASSED=0
FAILED=0
TOTAL=0

count_marker_lines() {
  local file="$1"
  local doc_id="$2"
  local section_id="$3"
  local start_marker="<!-- AI-SYMBIOTE:START ${doc_id}:${section_id} -->"
  local end_marker="<!-- AI-SYMBIOTE:END ${doc_id}:${section_id} -->"
  if ! grep -qF "$start_marker" "$file" 2>/dev/null; then
    echo 0
    return
  fi
  awk "/$start_marker/{found=1; next} /$end_marker/{found=0} found{count++} END{print count+0}" "$file"
}

assert_min_lines() {
  local desc="$1"
  local file="$2"
  local doc_id="$3"
  local section_id="$4"
  local min_lines="$5"
  TOTAL=$((TOTAL + 1))
  local actual
  actual=$(count_marker_lines "$file" "$doc_id" "$section_id")
  if [ "$actual" -ge "$min_lines" ] 2>/dev/null; then
    PASSED=$((PASSED + 1))
    printf "${GREEN}  PASS${NC} %s (actual: %s, min: %s)\n" "$desc" "$actual" "$min_lines"
  else
    FAILED=$((FAILED + 1))
    printf "${RED}  FAIL${NC} %s (actual: %s, min: %s)\n" "$desc" "$actual" "$min_lines"
  fi
}

echo "=== dev-docs quality validation ==="
echo ""

ARCH_FILE="$PROJECT_ROOT/docs/ARCHITECTURE.md"
FLOWS_FILE="$PROJECT_ROOT/docs/FLOWS.md"
ONBOARD_FILE="$PROJECT_ROOT/docs/ONBOARDING.md"
DEPS_FILE="$PROJECT_ROOT/docs/DEPENDENCIES.md"
CONV_FILE="$PROJECT_ROOT/docs/CONVENTIONS.md"

# ARCHITECTURE (targets: subsystems 15, build-flow 15 → min 50%: 7)
assert_min_lines "ARCHITECTURE subsystems" "$ARCH_FILE" architecture subsystems 7
assert_min_lines "ARCHITECTURE build-flow" "$ARCH_FILE" architecture build-flow 7

# FLOWS (targets: 10, 10, 8, 8 → min 50%: 5, 5, 4, 4)
assert_min_lines "FLOWS system-flow" "$FLOWS_FILE" flows system-flow 5
assert_min_lines "FLOWS data-flow" "$FLOWS_FILE" flows data-flow 5
assert_min_lines "FLOWS user-or-operator-flow" "$FLOWS_FILE" flows user-or-operator-flow 4
assert_min_lines "FLOWS operational-flow" "$FLOWS_FILE" flows operational-flow 4

# ONBOARDING (targets: 12, 10 → min 50%: 6, 5)
assert_min_lines "ONBOARDING read-order" "$ONBOARD_FILE" onboarding read-order 6
assert_min_lines "ONBOARDING common-tasks" "$ONBOARD_FILE" onboarding common-tasks 5

# DEPENDENCIES (target: 10 → min 50%: 5)
assert_min_lines "DEPENDENCIES runtime-dev-tools" "$DEPS_FILE" dependencies runtime-dev-tools 5

# CONVENTIONS (target: 10 → min 50%: 5)
assert_min_lines "CONVENTIONS editing-rules" "$CONV_FILE" conventions editing-rules 5

echo ""
echo "=== Results: $PASSED/$TOTAL passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
  echo ""
  echo "NOTE: This test validates SKILL.md workflow output quality."
  echo "Failures are expected if only generate-dev-docs.sh (fallback) was used."
  exit 1
fi
