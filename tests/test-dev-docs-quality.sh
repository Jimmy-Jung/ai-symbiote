#!/usr/bin/env bash
# Validate marker block content quality after dev-docs generation.
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

README_FILE="$PROJECT_ROOT/README.md"
START_FILE="$PROJECT_ROOT/docs/00-시작하기.md"
OVERVIEW_FILE="$PROJECT_ROOT/docs/01-프로젝트-개요.md"
ARCH_FILE="$PROJECT_ROOT/docs/02-아키텍처.md"
BUILD_FILE="$PROJECT_ROOT/docs/03-빌드-및-실행.md"
FEATURES_FILE="$PROJECT_ROOT/docs/04-주요-기능.md"
CONV_FILE="$PROJECT_ROOT/docs/05-코딩-컨벤션.md"
TROUBLE_FILE="$PROJECT_ROOT/docs/06-문제해결-가이드.md"
OPS_FILE="$PROJECT_ROOT/docs/07-운영-흐름-및-배포.md"

assert_min_lines "README overview" "$README_FILE" readme overview 4
assert_min_lines "README quick-start" "$README_FILE" readme quick-start 4
assert_min_lines "START quick-start" "$START_FILE" start quick-start 4
assert_min_lines "OVERVIEW project-summary" "$OVERVIEW_FILE" overview project-summary 4
assert_min_lines "ARCHITECTURE system-overview" "$ARCH_FILE" architecture system-overview 4
assert_min_lines "BUILD toolchain" "$BUILD_FILE" build toolchain 4
assert_min_lines "FEATURES harness-pillars" "$FEATURES_FILE" features harness-pillars 4
assert_min_lines "CONVENTIONS editing-rules" "$CONV_FILE" conventions editing-rules 4
assert_min_lines "TROUBLESHOOTING common-failures" "$TROUBLE_FILE" troubleshooting common-failures 4
assert_min_lines "OPERATIONS request-flow" "$OPS_FILE" operations request-flow 4
assert_min_lines "OPERATIONS data-flow" "$OPS_FILE" operations data-flow 4

echo ""
echo "=== Results: $PASSED/$TOTAL passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
