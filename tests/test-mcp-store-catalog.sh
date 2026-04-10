#!/bin/bash
# Validation tests for mcp-store catalog.json.
#
# Author: JunyoungJung
# Date: 2026-04-10
#
# Usage: bash tests/test-mcp-store-catalog.sh
#
# Validates JSON syntax and required fields for every catalog entry.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CATALOG="$PROJECT_ROOT/shared/skills/mcp-store/catalog.json"

PASSED=0
FAILED=0
TOTAL=0

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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
echo "=== MCP Store Catalog Validation ==="
echo ""

# --- Test 1: JSON validity ---
echo "[Test Group] JSON Validity"
jq empty "$CATALOG" 2>/dev/null
assert_eq "catalog.json is valid JSON" "0" "$?"

# --- Test 2: Top-level structure ---
echo ""
echo "[Test Group] Top-level Structure"

HAS_SOURCE=$(jq 'has("_source")' "$CATALOG")
assert_eq "_source field exists" "true" "$HAS_SOURCE"

HAS_UPDATED=$(jq 'has("_updated")' "$CATALOG")
assert_eq "_updated field exists" "true" "$HAS_UPDATED"

HAS_STACKS=$(jq 'has("stacks")' "$CATALOG")
assert_eq "stacks section exists" "true" "$HAS_STACKS"

HAS_SERVICES=$(jq 'has("services")' "$CATALOG")
assert_eq "services section exists" "true" "$HAS_SERVICES"

HAS_DOMAINS=$(jq 'has("domains")' "$CATALOG")
assert_eq "domains section exists" "true" "$HAS_DOMAINS"

# --- Test 3: Required fields per entry ---
echo ""
echo "[Test Group] Required Fields Per Entry"

REQUIRED_FIELDS='["id","name","repo","transport","command","args","env","category","description"]'

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

# --- Test 4: Transport values ---
echo ""
echo "[Test Group] Transport Values"

INVALID_TRANSPORT=$(jq '
  [.stacks, .services, .domains] |
  map(to_entries[] | .value[] |
    select(.transport != "stdio" and .transport != "http" and .transport != "sse") |
    {id: .id, transport: .transport}
  ) | flatten
' "$CATALOG")

INVALID_COUNT=$(echo "$INVALID_TRANSPORT" | jq 'length')
if [ "$INVALID_COUNT" = "0" ]; then
  assert_eq "all transport values are valid (stdio|http|sse)" "0" "0"
else
  assert_eq "all transport values are valid" "0" "$INVALID_COUNT"
  echo "$INVALID_TRANSPORT" | jq -r '.[] | "      \(.id): invalid transport \(.transport)"'
fi

# --- Test 5: No empty id fields ---
echo ""
echo "[Test Group] ID Validity"

EMPTY_IDS=$(jq '
  [.stacks, .services, .domains] |
  map(to_entries[] | .value[] | select(.id == "" or .id == null)) |
  flatten | length
' "$CATALOG")
assert_eq "no entries with empty id" "0" "$EMPTY_IDS"

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

# --- Summary ---
echo ""
echo "=== Summary ==="
printf "Total: %d  ${GREEN}Passed: %d${NC}  ${RED}Failed: %d${NC}\n" "$TOTAL" "$PASSED" "$FAILED"
echo "Catalog entries: $ENTRY_COUNT"
echo ""

if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
