#!/usr/bin/env bash
# ai-symbiote evolve manifest merge helper.
#
# Author: JunyoungJung
# Date: 2026-04-15

set -euo pipefail

MANIFEST_PATH=""
PATCH_PATH=""

while [ $# -gt 0 ]; do
  case "$1" in
    --manifest)
      MANIFEST_PATH="${2:-}"
      shift 2
      ;;
    --patch)
      PATCH_PATH="${2:-}"
      shift 2
      ;;
    *)
      echo "Usage: manifest-merge.sh --manifest PATH --patch PATH" >&2
      exit 1
      ;;
  esac
done

if [ -z "$MANIFEST_PATH" ] || [ -z "$PATCH_PATH" ]; then
  echo "Usage: manifest-merge.sh --manifest PATH --patch PATH" >&2
  exit 1
fi

if [ ! -f "$MANIFEST_PATH" ] || [ ! -f "$PATCH_PATH" ]; then
  echo "[Evolve] manifest or patch file not found." >&2
  exit 1
fi

python3 - "$MANIFEST_PATH" "$PATCH_PATH" <<'PY'
import json
import sys
from pathlib import Path

manifest_path = Path(sys.argv[1])
patch_path = Path(sys.argv[2])

base = json.loads(manifest_path.read_text())
patch = json.loads(patch_path.read_text())


def deep_merge(current, incoming):
    if not isinstance(current, dict) or not isinstance(incoming, dict):
        return incoming
    merged = dict(current)
    for key, value in incoming.items():
        if key in merged and isinstance(merged[key], dict) and isinstance(value, dict):
            merged[key] = deep_merge(merged[key], value)
        else:
            merged[key] = value
    return merged


result = deep_merge(base, patch)

existing_platforms = base.get("agentPlatforms")
incoming_platforms = result.get("agentPlatforms")
platforms = []
for source in (existing_platforms, incoming_platforms, ["claude", "codex"]):
    if not isinstance(source, list):
        continue
    for platform in source:
        if platform not in platforms:
            platforms.append(platform)
result["agentPlatforms"] = platforms

base_security = base.get("security")
result_security = result.get("security")
if not isinstance(result_security, dict):
    result_security = {}
if isinstance(base_security, dict) and "sessionSummaryLevel" in base_security and "sessionSummaryLevel" not in result_security:
    result_security["sessionSummaryLevel"] = base_security["sessionSummaryLevel"]
result_security.setdefault("sessionSummaryLevel", "auto")
result["security"] = result_security

manifest_path.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n")
print(f"[Evolve] manifest merged: {manifest_path}")
PY
