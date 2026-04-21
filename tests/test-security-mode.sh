#!/bin/bash
# Unit tests for shared/hooks/scripts/lib/security-mode.sh.
#
# Author: JunyoungJung
# Date: 2026-04-21
# Usage: bash tests/test-security-mode.sh
#
# Exercises every branch of is_hook_enabled + cache rebuild behavior:
#   - No manifest → fail open
#   - minimal mode → everything off
#   - balanced mode (default) → everything on
#   - custom mode → per-hook toggles, missing key fails open
#   - Stale cache → rebuilt on mtime change
#   - SYMBIOTE_SECURITY_FORCE override

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

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

TMPROOT=$(mktemp -d)
trap 'rm -rf "$TMPROOT"' EXIT

export SYMBIOTE_HOME="$TMPROOT/state"
mkdir -p "$SYMBIOTE_HOME"

# Set up a test slug dir the common.sh helper will resolve to.
export HARNESS_TEST_STATE_DIR="$SYMBIOTE_HOME/test-slug"
mkdir -p "$HARNESS_TEST_STATE_DIR/state"

LIB="$PROJECT_ROOT/shared/hooks/scripts/lib/security-mode.sh"

# Helper: runs is_hook_enabled in a subshell with a given manifest and returns
# "on"/"off" based on the exit code. Prints nothing else so the test output
# stays clean.
check_hook() {
  local manifest_json="$1"
  local hook_name="$2"

  # Fresh state dir per check so stale cache from the previous case can't
  # influence this one.
  rm -rf "$HARNESS_TEST_STATE_DIR"
  mkdir -p "$HARNESS_TEST_STATE_DIR/state"
  if [ -n "$manifest_json" ]; then
    printf '%s' "$manifest_json" > "$HARNESS_TEST_STATE_DIR/manifest.json"
  fi

  (
    # shellcheck source=/dev/null
    source "$LIB"
    if is_hook_enabled "$hook_name"; then
      printf 'on'
    else
      printf 'off'
    fi
  )
}

echo ""
echo "=== security-mode.sh is_hook_enabled ==="
echo ""

# --- Case 1: no manifest → fail open (enabled) ---
echo "--- Case 1: No manifest ⇒ fail open ---"
assert_eq "no manifest: verifyQueue enabled" "on" "$(check_hook '' verifyQueue)"
assert_eq "no manifest: guardShell enabled" "on" "$(check_hook '' guardShell)"

# --- Case 2: balanced (default) ---
echo ""
echo "--- Case 2: balanced preset ⇒ every hook on ---"
BAL='{"security":{"mode":"balanced"}}'
for h in guardShell securityGuard harnessLearn commentChecker verifyQueue; do
  assert_eq "balanced: $h on" "on" "$(check_hook "$BAL" "$h")"
done

# --- Case 3: minimal (opt-out everything) ---
echo ""
echo "--- Case 3: minimal preset ⇒ every hook off ---"
MIN='{"security":{"mode":"minimal"}}'
for h in guardShell securityGuard harnessLearn commentChecker verifyQueue; do
  assert_eq "minimal: $h off" "off" "$(check_hook "$MIN" "$h")"
done

# --- Case 4: strict → same as balanced today (reserved for future) ---
echo ""
echo "--- Case 4: strict preset ⇒ every hook on (alias of balanced today) ---"
STR='{"security":{"mode":"strict"}}'
for h in guardShell securityGuard harnessLearn commentChecker verifyQueue; do
  assert_eq "strict: $h on" "on" "$(check_hook "$STR" "$h")"
done

# --- Case 5: custom with partial toggles ---
echo ""
echo "--- Case 5: custom preset ⇒ explicit per-hook toggles ---"
CUS='{"security":{"mode":"custom","hooks":{"guardShell":false,"verifyQueue":false,"harnessLearn":true,"securityGuard":true,"commentChecker":true}}}'
assert_eq "custom: guardShell explicitly off"   "off" "$(check_hook "$CUS" guardShell)"
assert_eq "custom: verifyQueue explicitly off"  "off" "$(check_hook "$CUS" verifyQueue)"
assert_eq "custom: harnessLearn explicitly on"  "on"  "$(check_hook "$CUS" harnessLearn)"
assert_eq "custom: securityGuard explicitly on" "on"  "$(check_hook "$CUS" securityGuard)"
assert_eq "custom: commentChecker explicitly on" "on" "$(check_hook "$CUS" commentChecker)"

# --- Case 6: custom with MISSING key ⇒ fail open ---
echo ""
echo "--- Case 6: custom with missing key ⇒ fail open (on) ---"
CUS_MIN='{"security":{"mode":"custom","hooks":{"guardShell":false}}}'
assert_eq "custom missing key: verifyQueue on" "on" "$(check_hook "$CUS_MIN" verifyQueue)"

# --- Case 7: unknown mode ⇒ fail open ---
echo ""
echo "--- Case 7: unknown mode string ⇒ fail open (on) ---"
BOGUS='{"security":{"mode":"ultra-strict-plus"}}'
assert_eq "bogus mode: guardShell on" "on" "$(check_hook "$BOGUS" guardShell)"

# --- Case 8: unknown hook name ⇒ fail open ---
echo ""
echo "--- Case 8: unknown hook name ⇒ fail open (on) ---"
assert_eq "unknown hook name: on" "on" "$(check_hook "$MIN" definitelyNotARealHook)"

# --- Case 9: SYMBIOTE_SECURITY_FORCE override ---
echo ""
echo "--- Case 9: SYMBIOTE_SECURITY_FORCE override ---"
FORCE_OFF=$(
  rm -rf "$HARNESS_TEST_STATE_DIR" && mkdir -p "$HARNESS_TEST_STATE_DIR/state"
  printf '%s' "$BAL" > "$HARNESS_TEST_STATE_DIR/manifest.json"
  (
    source "$LIB"
    SYMBIOTE_SECURITY_FORCE=off is_hook_enabled guardShell && printf on || printf off
  )
)
assert_eq "FORCE=off overrides balanced" "off" "$FORCE_OFF"
FORCE_ON=$(
  rm -rf "$HARNESS_TEST_STATE_DIR" && mkdir -p "$HARNESS_TEST_STATE_DIR/state"
  printf '%s' "$MIN" > "$HARNESS_TEST_STATE_DIR/manifest.json"
  (
    source "$LIB"
    SYMBIOTE_SECURITY_FORCE=on is_hook_enabled guardShell && printf on || printf off
  )
)
assert_eq "FORCE=on overrides minimal" "on" "$FORCE_ON"

# --- Case 10: cache rebuild on manifest mtime change ---
echo ""
echo "--- Case 10: cache rebuild when manifest mtime bumps ---"
rm -rf "$HARNESS_TEST_STATE_DIR" && mkdir -p "$HARNESS_TEST_STATE_DIR/state"
printf '%s' "$BAL" > "$HARNESS_TEST_STATE_DIR/manifest.json"
# Age the manifest so the cache we produce below is guaranteed newer.
touch -t 202004010000 "$HARNESS_TEST_STATE_DIR/manifest.json"
BEFORE=$(
  source "$LIB"
  is_hook_enabled guardShell && printf on || printf off
)
assert_eq "initial (balanced): on" "on" "$BEFORE"

# Now flip to minimal and bump mtime — the cache should rebuild.
# Sleep 1s so the new manifest mtime is strictly greater than the cache's.
# stat(1) mtime is second-precision on most filesystems, so writing manifest
# and cache within the same second would be ambiguous.
sleep 1
printf '%s' "$MIN" > "$HARNESS_TEST_STATE_DIR/manifest.json"
touch "$HARNESS_TEST_STATE_DIR/manifest.json"
AFTER=$(
  source "$LIB"
  is_hook_enabled guardShell && printf on || printf off
)
assert_eq "after switch to minimal: off (cache rebuilt)" "off" "$AFTER"

# --- Case 11: get_security_mode diagnostic ---
echo ""
echo "--- Case 11: get_security_mode ---"
rm -rf "$HARNESS_TEST_STATE_DIR" && mkdir -p "$HARNESS_TEST_STATE_DIR/state"
printf '%s' "$MIN" > "$HARNESS_TEST_STATE_DIR/manifest.json"
MODE_OUT=$(
  source "$LIB"
  get_security_mode
)
assert_eq "get_security_mode reads minimal" "minimal" "$MODE_OUT"

# --- Case 12: empty manifest file ⇒ fail open (balanced defaults) ---
# Regression for /verify reviewer R1-Q2 concern: if manifest is empty/0-byte
# (partial write, corruption), do not leave a residual disabled cache in place.
echo ""
echo "--- Case 12: Empty manifest ⇒ balanced defaults ---"
rm -rf "$HARNESS_TEST_STATE_DIR" && mkdir -p "$HARNESS_TEST_STATE_DIR/state"
: > "$HARNESS_TEST_STATE_DIR/manifest.json"  # 0-byte manifest
CASE12_RESULT=$(
  source "$LIB"
  if is_hook_enabled guardShell; then printf "on"; else printf "off"; fi
)
assert_eq "empty manifest: guardShell on (fallback)" "on" "$CASE12_RESULT"

# --- Case 13: atomic cache write (no partial cache file on concurrent read) ---
# Regression for /verify reviewer R3-Q2: verify the cache path never exists
# as a partial file during rebuild. We cannot race the write reliably in
# pure bash, so we check the lighter invariant: the final cache is whole,
# matches the expected key set, and the rebuild succeeds.
echo ""
echo "--- Case 13: Cache write is atomic + complete ---"
rm -rf "$HARNESS_TEST_STATE_DIR" && mkdir -p "$HARNESS_TEST_STATE_DIR/state"
printf '%s' "$BAL" > "$HARNESS_TEST_STATE_DIR/manifest.json"
(
  source "$LIB"
  is_hook_enabled guardShell >/dev/null
)
CACHE_PATH="$HARNESS_TEST_STATE_DIR/state/security-mode.cache"
CACHE_KEYS=$(awk -F= '{print $1}' "$CACHE_PATH" | tr '\n' ',' | sed 's/,$//')
assert_eq "cache has all 6 expected keys" "mode,guardShell,securityGuard,harnessLearn,commentChecker,verifyQueue" "$CACHE_KEYS"
# Ensure no tempfile leaked alongside the cache
LEAKED=$(find "$HARNESS_TEST_STATE_DIR/state" -name 'security-mode.cache.*' 2>/dev/null | wc -l | tr -d ' ')
assert_eq "no leaked tempfile beside cache" "0" "$LEAKED"

# --- Case 14: hook name with regex metacharacter is rejected as unknown ---
# Regression for /verify reviewer R3-Q3: an attacker-controlled or typo hook
# name containing regex metacharacters must not accidentally match a
# different cache line.
echo ""
echo "--- Case 14: regex-unsafe hook name ⇒ treated as unknown (fail open) ---"
rm -rf "$HARNESS_TEST_STATE_DIR" && mkdir -p "$HARNESS_TEST_STATE_DIR/state"
printf '%s' "$MIN" > "$HARNESS_TEST_STATE_DIR/manifest.json"
for evil in 'guardShell|verifyQueue' 'guardShell.*' '.*' 'guardShell='; do
  CASE14_RESULT=$(
    source "$LIB"
    if is_hook_enabled "$evil"; then printf "on"; else printf "off"; fi
  )
  assert_eq "regex-unsafe '$evil' ⇒ fail open" "on" "$CASE14_RESULT"
done

# --- Case 15: single-source-of-truth for hook names ---
# Regression for /verify reviewer R2-Q1: the list of hook names must be
# defined once (bash array) and passed into the Python rebuild. A cache
# rebuilt from a manifest with a custom mode must reflect exactly the bash
# array's set of names, nothing more, nothing less.
echo ""
echo "--- Case 15: hook list single source of truth ---"
set +e
rm -rf "$HARNESS_TEST_STATE_DIR"
mkdir -p "$HARNESS_TEST_STATE_DIR/state"
# Custom manifest with bogus extra hook name — rebuild must ignore it
BOGUS_HOOKS='{"security":{"mode":"custom","hooks":{"guardShell":false,"attackerAdded":true}}}'
printf '%s' "$BOGUS_HOOKS" > "$HARNESS_TEST_STATE_DIR/manifest.json"
(
  source "$LIB"
  is_hook_enabled guardShell >/dev/null
)
CACHE_PATH="$HARNESS_TEST_STATE_DIR/state/security-mode.cache"
# Use awk for counting (never leaks a secondary "0" into stdout the way
# `grep -c ... || echo 0` can) to avoid the same arithmetic bug that bit
# setup-check.sh.
HAS_ATTACKER=$(awk -F= '$1=="attackerAdded"' "$CACHE_PATH" 2>/dev/null | wc -l | tr -d ' ')
HAS_ATTACKER=${HAS_ATTACKER:-0}
assert_eq "attackerAdded is NOT written to cache" "0" "$HAS_ATTACKER"
KEYS_COUNT=$(awk -F= '$1!="mode" {print $1}' "$CACHE_PATH" 2>/dev/null | sort -u | wc -l | tr -d ' ')
KEYS_COUNT=${KEYS_COUNT:-0}
assert_eq "exactly 5 canonical hooks in cache" "5" "$KEYS_COUNT"
set -e

echo ""
echo "=== Results ==="
printf "Passed: %d / %d\n" "$PASSED" "$TOTAL"
if [ "$FAILED" -gt 0 ]; then
  printf "${RED}Failed: %d${NC}\n" "$FAILED"
  exit 1
else
  printf "${GREEN}All tests passed!${NC}\n"
fi
