#!/bin/bash
# ai-symbiote security mode helper.
#
# Author: JunyoungJung
# Date: 2026-04-21
#
# Provides a single primitive, `is_hook_enabled "<name>"`, that every AI-
# restriction hook can use to early-exit when the user has disabled that hook
# through the project manifest.
#
# Data flow:
#   manifest.json (source of truth)
#     └─> ~/ai-symbiote/{slug}/state/security-mode.cache
#         (flat key=value snapshot, rebuilt when manifest mtime changes)
#         └─> is_hook_enabled "guardShell" → 0 (enabled) or 1 (disabled)
#
# The cache avoids re-parsing JSON on every hook fire (target <5ms total
# added to the PreToolUse/PostToolUse path).
#
# Security modes:
#   minimal  — every restrictive hook OFF
#   balanced — default, every restrictive hook ON
#   strict   — balanced + future tightening hooks (reserved; currently == balanced)
#   custom   — each hook ON/OFF from security.hooks.{name} toggles in manifest
#
# Schema contract (manifest.json):
#   "security": {
#     "mode": "balanced",
#     "hooks": {                 // only read when mode=="custom"
#       "guardShell":      true,
#       "securityGuard":   true,
#       "harnessLearn":    true,
#       "commentChecker":  true,
#       "verifyQueue":     true
#     }
#   }

# Load common helpers (get_state_dir, json_field, …) only if not already sourced.
if ! command -v get_state_dir >/dev/null 2>&1; then
  _SEC_MODE_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  # shellcheck source=common.sh
  source "$_SEC_MODE_LIB_DIR/common.sh"
fi

# Canonical list of gate-able hook names.
#
# This array is the ONLY source of truth. It is passed as argv to the embedded
# Python rebuild script so there is no parallel HOOKS constant to drift away.
# New hooks must be added here (and documented in the Schema contract comment
# above). Names are also the keys used by is_hook_enabled callers.
_SEC_MODE_HOOK_NAMES=(
  guardShell
  securityGuard
  harnessLearn
  commentChecker
  verifyQueue
)

# Return the absolute path to the security-mode cache for the current slug.
# The caller is responsible for ensuring the parent directory exists.
_sec_mode_cache_path() {
  local state_dir
  state_dir=$(get_state_dir 2>/dev/null) || return 1
  [ -z "$state_dir" ] && return 1
  mkdir -p "$state_dir/state" 2>/dev/null || true
  printf '%s/state/security-mode.cache' "$state_dir"
}

# Return the manifest.json path for the current slug, or empty string when
# the project has not been initialized yet.
_sec_mode_manifest_path() {
  local state_dir
  state_dir=$(get_state_dir 2>/dev/null) || return 1
  [ -z "$state_dir" ] && return 1
  printf '%s/manifest.json' "$state_dir"
}

# Build the cache file from the manifest.
#
# Writes simple `key=bool\n` lines so the read path is pure shell. The write
# is atomic: we stage to a tempfile alongside the cache and `mv` into place so
# a concurrent hook fire can never read a partial line.
#
# HOOK_NAMES are passed as argv to Python so there is a single source of
# truth; the Python script rejects any name it does not receive.
_sec_mode_rebuild_cache() {
  local manifest="$1"
  local cache_file="$2"

  # Tempfile next to the cache so the final `mv` is a rename within the same
  # filesystem (atomic on POSIX).
  local cache_dir
  cache_dir=$(dirname "$cache_file")
  mkdir -p "$cache_dir" 2>/dev/null || return 1
  local tmp_cache
  tmp_cache=$(mktemp "$cache_dir/security-mode.cache.XXXXXX" 2>/dev/null) || return 1

  if command -v python3 >/dev/null 2>&1 && [ -f "$manifest" ] && [ -s "$manifest" ]; then
    # Pass HOOK_NAMES as argv so Python and Bash share the exact same list.
    local cache_body
    cache_body=$(python3 - "$manifest" "${_SEC_MODE_HOOK_NAMES[@]}" <<'PY' 2>/dev/null
import json
import sys
from pathlib import Path

DEFAULT_MODE = "balanced"
VALID_MODES = {"minimal", "balanced", "strict", "custom"}


def preset_default(mode: str) -> bool:
    # Every preset except `minimal` enables all hooks today. `strict` is
    # reserved for future tightening hooks added to this helper.
    return mode != "minimal"


def main() -> int:
    manifest_path = Path(sys.argv[1])
    hook_names = sys.argv[2:]
    if not hook_names:
        return 1

    try:
        data = json.loads(manifest_path.read_text())
    except Exception:
        return 1

    security = data.get("security") or {}
    mode = security.get("mode") or DEFAULT_MODE
    if mode not in VALID_MODES:
        mode = DEFAULT_MODE

    per_hook = security.get("hooks") or {}

    lines = [f"mode={mode}"]
    for name in hook_names:
        if mode == "custom":
            value = per_hook.get(name)
            enabled = value if isinstance(value, bool) else True
        else:
            enabled = preset_default(mode)
        lines.append(f"{name}={'true' if enabled else 'false'}")

    sys.stdout.write("\n".join(lines) + "\n")
    return 0


sys.exit(main())
PY
)
    if [ -n "$cache_body" ]; then
      printf '%s' "$cache_body" > "$tmp_cache" 2>/dev/null || { rm -f "$tmp_cache"; return 1; }
      mv -f "$tmp_cache" "$cache_file" 2>/dev/null || { rm -f "$tmp_cache"; return 1; }
      return 0
    fi
  fi

  # Fallback (no python3, empty manifest, or parse failure): write balanced
  # defaults so the agent is not silently neutered by an empty cache that a
  # naive reader would treat as "disabled". Still atomic via the tempfile.
  {
    printf 'mode=balanced\n'
    for name in "${_SEC_MODE_HOOK_NAMES[@]}"; do
      printf '%s=true\n' "$name"
    done
  } > "$tmp_cache" 2>/dev/null || { rm -f "$tmp_cache"; return 1; }
  mv -f "$tmp_cache" "$cache_file" 2>/dev/null || { rm -f "$tmp_cache"; return 1; }
}

# Compare two file mtimes. Returns 0 (true — stale) when the manifest is
# newer than the cache OR when the cache is missing. Uses `stat -f` on macOS
# / `stat -c` on Linux; falls back to "rebuild every time" if neither works.
_sec_mode_cache_stale() {
  local manifest="$1"
  local cache="$2"
  [ ! -f "$cache" ] && return 0
  [ ! -f "$manifest" ] && return 1  # no manifest ⇒ keep whatever the cache has

  local manifest_mtime cache_mtime
  manifest_mtime=$(stat -f '%m' "$manifest" 2>/dev/null || stat -c '%Y' "$manifest" 2>/dev/null || echo 0)
  cache_mtime=$(stat -f '%m' "$cache" 2>/dev/null || stat -c '%Y' "$cache" 2>/dev/null || echo 0)
  [ "$manifest_mtime" -gt "$cache_mtime" ] 2>/dev/null
}

# Check whether the given name is in the canonical hook list. Returns 0 when
# present, 1 otherwise. Used as a guard before consulting the cache so a
# caller passing a junk name cannot be disabled by a stray cache line.
_sec_mode_is_known_hook() {
  local name="$1"
  local n
  for n in "${_SEC_MODE_HOOK_NAMES[@]}"; do
    [ "$n" = "$name" ] && return 0
  done
  return 1
}

# Public API: is the named hook enabled for the current project?
#
# Exit codes:
#   0  enabled — caller should continue
#   1  disabled — caller should `exit 0` immediately (fire-and-forget)
#
# Behavior:
#   - No manifest / no slug resolvable ⇒ enabled (fail open — agent must not
#     be silently neutered when the project hasn't opted into ai-symbiote).
#   - Empty / unparseable manifest ⇒ enabled (rebuild writes balanced defaults).
#   - Cache missing or stale ⇒ rebuild from manifest, then read.
#   - Unknown hook name ⇒ enabled (fail open; names are validated against the
#     canonical list so a stray cache key cannot disable unrelated code).
is_hook_enabled() {
  local hook_name="$1"
  [ -z "$hook_name" ] && return 0

  # Test hook: allow forcing a specific outcome from a test harness without
  # touching the user's real manifest. Values: "on", "off". Any other value
  # is ignored.
  if [ -n "${SYMBIOTE_SECURITY_FORCE:-}" ]; then
    case "$SYMBIOTE_SECURITY_FORCE" in
      off) return 1 ;;
      on) return 0 ;;
    esac
  fi

  # Reject unknown names up front so a renamed hook or typo cannot be
  # disabled by a residual cache entry.
  _sec_mode_is_known_hook "$hook_name" || return 0

  local manifest cache
  manifest=$(_sec_mode_manifest_path) || return 0
  [ ! -f "$manifest" ] && return 0  # not yet initialized ⇒ fail open

  cache=$(_sec_mode_cache_path) || return 0
  [ -z "$cache" ] && return 0

  if _sec_mode_cache_stale "$manifest" "$cache"; then
    _sec_mode_rebuild_cache "$manifest" "$cache" || return 0
  fi

  # Exact field match via awk so hook names containing regex metacharacters
  # cannot match a different cache line (e.g. `guardShell` must not match
  # `myGuardShell=...`). awk compares $1 literally as a string.
  local value
  value=$(awk -F= -v k="$hook_name" '$1==k {print $2; exit}' "$cache" 2>/dev/null)
  case "$value" in
    false) return 1 ;;
    true|'') return 0 ;;  # missing key ⇒ fail open
    *) return 0 ;;
  esac
}

# Print the current mode for diagnostics. Used by `/security mode` with no
# args and by setup-check's SessionStart summary.
get_security_mode() {
  local manifest cache
  manifest=$(_sec_mode_manifest_path) || { printf 'balanced'; return 0; }
  cache=$(_sec_mode_cache_path) || { printf 'balanced'; return 0; }
  if [ -f "$manifest" ] && _sec_mode_cache_stale "$manifest" "$cache"; then
    _sec_mode_rebuild_cache "$manifest" "$cache" 2>/dev/null || true
  fi
  if [ -f "$cache" ]; then
    local mode
    mode=$(awk -F= '$1=="mode" {print $2; exit}' "$cache" 2>/dev/null)
    [ -n "$mode" ] && { printf '%s' "$mode"; return 0; }
  fi
  printf 'balanced'
}
