#!/bin/bash
# Validation tests for cli-store catalog.json.
#
# Author: JunyoungJung
# Date: 2026-04-12
#
# Usage: bash tests/test-cli-store-catalog.sh
#
# Validates JSON syntax and required fields for every catalog entry.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CATALOG="$PROJECT_ROOT/shared/skills/cli-store/catalog.json"

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

assert_true() {
  local desc="$1" result="$2"
  TOTAL=$((TOTAL + 1))
  if [ "$result" = "true" ] || [ "$result" = "0" ]; then
    PASSED=$((PASSED + 1))
    printf "${GREEN}  PASS${NC} %s\n" "$desc"
  else
    FAILED=$((FAILED + 1))
    printf "${RED}  FAIL${NC} %s\n" "$desc"
  fi
}

# Check jq is available
if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required but not installed. Install with: brew install jq"
  exit 1
fi

echo ""
echo "=== CLI Store Catalog Validation ==="
echo ""

# --- Test 1: JSON validity ---
echo "[Test Group] JSON Validity"
jq empty "$CATALOG" 2>/dev/null
assert_eq "catalog.json is valid JSON" "0" "$?"

# --- Test 2: Top-level structure ---
echo ""
echo "[Test Group] Top-level Structure"

HAS_STACKS=$(jq 'has("stacks")' "$CATALOG")
assert_eq "stacks section exists" "true" "$HAS_STACKS"

HAS_SERVICES=$(jq 'has("services")' "$CATALOG")
assert_eq "services section exists" "true" "$HAS_SERVICES"

HAS_DOMAINS=$(jq 'has("domains")' "$CATALOG")
assert_eq "domains section exists" "true" "$HAS_DOMAINS"

# --- Test 3: Required fields per entry ---
echo ""
echo "[Test Group] Required Fields Per Entry"

REQUIRED_FIELDS='["id","name","cmd","checkCmd","installCmd","mcpEquivalent","category","description"]'

# Collect all entries from stacks, services, domains
ENTRY_COUNT=$(jq '[.stacks[], .services[], .domains[] | .[]] | length' "$CATALOG")
assert_true "catalog has entries (count: $ENTRY_COUNT)" "$([ "$ENTRY_COUNT" -gt 0 ] && echo true || echo false)"

# Check each entry has all required fields
MISSING=$(jq --argjson req "$REQUIRED_FIELDS" '
  [.stacks, .services, .domains] |
  map(to_entries[] | .key as $section | .value[] |
    ($req - (keys)) as $missing |
    if ($missing | length) > 0 then
      {section: $section, id: (.id // "UNKNOWN"), missing: $missing}
    else empty end
  )
' "$CATALOG")

MISSING_COUNT=$(echo "$MISSING" | jq 'length')
if [ "$MISSING_COUNT" = "0" ]; then
  assert_eq "all entries have required fields" "0" "0"
else
  assert_eq "all entries have required fields" "0" "$MISSING_COUNT"
  echo "    Missing fields:"
  echo "$MISSING" | jq -r '.[] | "      \(.section)/\(.id): missing \(.missing | join(", "))"'
fi

# --- Test 4: installCmd has at least one method ---
echo ""
echo "[Test Group] Install Commands"

EMPTY_INSTALL=$(jq '
  [.stacks, .services, .domains] |
  map(to_entries[] | .value[] | select((.installCmd | length) == 0)) |
  flatten | length
' "$CATALOG")
assert_eq "all entries have at least one install method" "0" "$EMPTY_INSTALL"

# --- Test 5: No empty id or cmd fields ---
echo ""
echo "[Test Group] ID and Cmd Validity"

EMPTY_IDS=$(jq '
  [.stacks, .services, .domains] |
  map(to_entries[] | .value[] | select(.id == "" or .id == null)) |
  flatten | length
' "$CATALOG")
assert_eq "no entries with empty id" "0" "$EMPTY_IDS"

EMPTY_CMDS=$(jq '
  [.stacks, .services, .domains] |
  map(to_entries[] | .value[] | select(.cmd == "" or .cmd == null)) |
  flatten | length
' "$CATALOG")
assert_eq "no entries with empty cmd" "0" "$EMPTY_CMDS"

# --- Test 6: No duplicate ids within same section ---
echo ""
echo "[Test Group] ID Uniqueness (per section)"

DUPES=$(jq '
  [.stacks, .services, .domains] |
  map(to_entries[] |
    .key as $section |
    [.value[].id] | group_by(.) | map(select(length > 1) | {section: $section, id: .[0], count: length})
  ) | flatten
' "$CATALOG")

DUPE_COUNT=$(echo "$DUPES" | jq 'length')
if [ "$DUPE_COUNT" = "0" ]; then
  assert_eq "no duplicate ids within sections" "0" "0"
else
  assert_eq "no duplicate ids within sections" "0" "$DUPE_COUNT"
  echo "$DUPES" | jq -r '.[] | "      \(.section): id \(.id) appears \(.count) times"'
fi

# --- Test 7: mcpEquivalent values are strings or null ---
echo ""
echo "[Test Group] mcpEquivalent Values"

INVALID_MCP=$(jq '
  [.stacks, .services, .domains] |
  map(to_entries[] | .value[] |
    select(.mcpEquivalent != null and (.mcpEquivalent | type) != "string") |
    {id: .id, mcpEquivalent: .mcpEquivalent}
  ) | flatten
' "$CATALOG")

INVALID_MCP_COUNT=$(echo "$INVALID_MCP" | jq 'length')
assert_eq "mcpEquivalent values are string or null" "0" "$INVALID_MCP_COUNT"

# --- Summary ---
echo ""
echo "=== Summary ==="
printf "Total: %d  ${GREEN}Passed: %d${NC}  ${RED}Failed: %d${NC}\n" "$TOTAL" "$PASSED" "$FAILED"
echo "Catalog entries: $ENTRY_COUNT"
echo ""

if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
