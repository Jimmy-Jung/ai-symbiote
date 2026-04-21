#!/usr/bin/env bash
# /security mode — show or change the AI-restriction hook preset.
#
# Author: JunyoungJung
# Date: 2026-04-21
#
# Read/write end of the toggle machinery introduced in v0.12. The runtime
# read path lives in shared/hooks/scripts/lib/security-mode.sh; this script
# is the UI layer that the security skill exposes to the user.
#
# Usage:
#   security-mode.sh --state-dir DIR                     # show current mode + per-hook status
#   security-mode.sh --state-dir DIR --action MODE       # switch to preset MODE
#   security-mode.sh --state-dir DIR --action custom --hooks JSON
#                                                        # apply per-hook toggles
#
# Modes: minimal | balanced | strict | custom
#
# On any change the script:
#   1. Writes the new mode (+hooks) into manifest.json via security-mode-apply.sh
#   2. Removes the state/security-mode.cache so the next hook fire rebuilds
#      cleanly (avoids a subtle mtime race where the manifest and cache end
#      up with the same second-precision mtime).
#   3. Prints a human-readable summary of the new effective state.

set -euo pipefail

STATE_DIR=""
ACTION=""
HOOKS_JSON=""

while [ $# -gt 0 ]; do
  case "$1" in
    --state-dir)
      STATE_DIR="${2:-}"
      shift 2
      ;;
    --action)
      ACTION="${2:-}"
      shift 2
      ;;
    --hooks)
      HOOKS_JSON="${2:-}"
      shift 2
      ;;
    -h|--help)
      sed -n '1,30p' "$0"
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [ -z "$STATE_DIR" ]; then
  echo "Usage: security-mode.sh --state-dir DIR [--action MODE] [--hooks JSON]" >&2
  exit 1
fi

MANIFEST="$STATE_DIR/manifest.json"
CACHE_FILE="$STATE_DIR/state/security-mode.cache"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# The apply helper lives in the setup skill because it is shared between
# first-time setup and subsequent reconfigurations.
APPLY_SCRIPT="$SCRIPT_DIR/../../setup/scripts/security-mode-apply.sh"

if [ ! -f "$MANIFEST" ]; then
  cat <<EOF >&2
[Security] manifest.json not found: $MANIFEST

The security mode is stored in the project manifest. Run the setup skill
first to create it, or create a minimal one manually:

  mkdir -p "$STATE_DIR"
  echo '{}' > "$MANIFEST"
  /ai-symbiote:security mode $([ -n "$ACTION" ] && echo "$ACTION")
EOF
  exit 1
fi

# Current state helper --------------------------------------------------------

show_status() {
  local current_mode
  if command -v python3 >/dev/null 2>&1; then
    current_mode=$(python3 - "$MANIFEST" <<'PY' 2>/dev/null || echo ""
import json
import sys
from pathlib import Path

try:
    data = json.loads(Path(sys.argv[1]).read_text())
except Exception:
    sys.exit(0)

security = data.get("security") or {}
print(security.get("mode") or "balanced")
PY
)
  fi
  : "${current_mode:=balanced}"

  echo "[Security] current mode: $current_mode"
  echo ""
  echo "Effective hook status:"
  if [ -f "$CACHE_FILE" ]; then
    while IFS='=' read -r key val; do
      [ "$key" = "mode" ] && continue
      [ -z "$key" ] && continue
      printf "  %-16s  %s\n" "$key" "$val"
    done < "$CACHE_FILE"
  else
    echo "  (cache not yet built; will be populated on next hook fire)"
  fi
  echo ""
  echo "Change with:"
  echo "  /ai-symbiote:security mode minimal     # every AI-restriction hook off"
  echo "  /ai-symbiote:security mode balanced    # default, every hook on"
  echo "  /ai-symbiote:security mode strict      # reserved; currently == balanced"
  echo "  /ai-symbiote:security mode custom      # then edit manifest.json security.hooks.*"
  echo ""
  echo "Or call this script directly with --hooks JSON to pre-fill toggles:"
  echo "  security-mode.sh --state-dir $STATE_DIR \\"
  echo "    --action custom --hooks '{\"guardShell\":false,\"verifyQueue\":true}'"
}

# No --action ⇒ just show status and exit.
if [ -z "$ACTION" ]; then
  show_status
  exit 0
fi

# Validate the requested mode.
case "$ACTION" in
  minimal|balanced|strict|custom) ;;
  *)
    echo "[Security] invalid mode '$ACTION'" >&2
    echo "Must be one of: minimal, balanced, strict, custom" >&2
    exit 1
    ;;
esac

if [ ! -f "$APPLY_SCRIPT" ]; then
  echo "[Security] apply helper not found: $APPLY_SCRIPT" >&2
  exit 1
fi

# Delegate the actual write to the apply helper so both /setup and
# /security mode share the same manifest-mutation path.
APPLY_ARGS=(--manifest "$MANIFEST" --mode "$ACTION")
if [ -n "$HOOKS_JSON" ]; then
  APPLY_ARGS+=(--hooks "$HOOKS_JSON")
fi

bash "$APPLY_SCRIPT" "${APPLY_ARGS[@]}"

# Evict the cache so the very next hook fire rebuilds from the updated
# manifest. Rebuild is cheap (~5ms) and this avoids any mtime-precision
# edge cases where manifest and cache end up in the same second.
rm -f "$CACHE_FILE" 2>/dev/null || true

echo ""
show_status
