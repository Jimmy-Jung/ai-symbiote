#!/usr/bin/env bash
# ai-symbiote setup: write user-chosen security mode into manifest.json.
#
# Author: JunyoungJung
# Date: 2026-04-21
#
# Called by the setup guided flow (Step 4.6) and by `/security mode` to
# persist a mode + optional per-hook toggles into the project manifest.
#
# Usage:
#   security-mode-apply.sh --manifest PATH --mode MODE [--hooks JSON]
#
# Arguments:
#   --manifest PATH  Absolute path to the project's manifest.json
#   --mode MODE      One of: minimal | balanced | strict | custom
#   --hooks JSON     (optional, required when --mode=custom)
#                    JSON object: {"guardShell":true,"securityGuard":false,...}
#                    Any omitted hook defaults to true (fail open).
#
# Exit codes:
#   0  manifest updated (or no change needed)
#   1  argument error / manifest missing / invalid mode / parse error

set -euo pipefail

MANIFEST_PATH=""
MODE=""
HOOKS_JSON=""

while [ $# -gt 0 ]; do
  case "$1" in
    --manifest)
      MANIFEST_PATH="${2:-}"
      shift 2
      ;;
    --mode)
      MODE="${2:-}"
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
      echo "Usage: security-mode-apply.sh --manifest PATH --mode MODE [--hooks JSON]" >&2
      exit 1
      ;;
  esac
done

if [ -z "$MANIFEST_PATH" ] || [ -z "$MODE" ]; then
  echo "Usage: security-mode-apply.sh --manifest PATH --mode MODE [--hooks JSON]" >&2
  exit 1
fi

if [ ! -f "$MANIFEST_PATH" ]; then
  echo "[Security] manifest.json not found: $MANIFEST_PATH" >&2
  exit 1
fi

case "$MODE" in
  minimal|balanced|strict|custom) ;;
  *)
    echo "[Security] invalid mode '$MODE' (must be minimal|balanced|strict|custom)" >&2
    exit 1
    ;;
esac

if [ "$MODE" = "custom" ] && [ -z "$HOOKS_JSON" ]; then
  # Allow empty --hooks for custom; we treat that as "all on" (= balanced
  # behavior). This keeps the CLI forgiving for `/security mode custom`
  # without forcing the user to hand-edit JSON.
  HOOKS_JSON='{}'
fi

python3 - "$MANIFEST_PATH" "$MODE" "${HOOKS_JSON:-}" <<'PY'
import json
import sys
from pathlib import Path

manifest_path = Path(sys.argv[1])
mode = sys.argv[2]
hooks_json = sys.argv[3] if len(sys.argv) > 3 else ""

HOOK_NAMES = (
    "guardShell",
    "securityGuard",
    "harnessLearn",
    "commentChecker",
    "verifyQueue",
)

try:
    data = json.loads(manifest_path.read_text())
except Exception as exc:  # noqa: BLE001
    print(f"[Security] failed to parse manifest: {exc}", file=sys.stderr)
    sys.exit(1)

security = data.get("security")
if not isinstance(security, dict):
    security = {}
security["mode"] = mode

hooks_block = security.get("hooks")
if not isinstance(hooks_block, dict):
    hooks_block = {}

if mode == "custom" and hooks_json:
    try:
        user_hooks = json.loads(hooks_json)
    except Exception as exc:  # noqa: BLE001
        print(f"[Security] failed to parse --hooks JSON: {exc}", file=sys.stderr)
        sys.exit(1)
    if not isinstance(user_hooks, dict):
        print("[Security] --hooks must be a JSON object", file=sys.stderr)
        sys.exit(1)
    # Accept only known hook names with boolean values; ignore everything
    # else so a typo can't silently disable the real hook or introduce an
    # unknown switch that later reader won't understand.
    for name, value in user_hooks.items():
        if name in HOOK_NAMES and isinstance(value, bool):
            hooks_block[name] = value

# Always normalize the block so every known hook is present with a boolean.
# Missing values become True (fail open), matching is_hook_enabled behavior.
for name in HOOK_NAMES:
    if not isinstance(hooks_block.get(name), bool):
        hooks_block[name] = True
security["hooks"] = hooks_block
# Ensure sessionSummaryLevel stays present so downstream consumers are happy.
security.setdefault("sessionSummaryLevel", "auto")
data["security"] = security

manifest_path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
print(f"[Security] mode set to {mode}")
PY
