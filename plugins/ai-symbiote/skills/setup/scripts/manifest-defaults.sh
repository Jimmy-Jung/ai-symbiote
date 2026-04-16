#!/usr/bin/env bash
# ai-symbiote setup manifest defaults helper.
#
# Author: JunyoungJung
# Date: 2026-04-15

set -euo pipefail

MANIFEST_PATH=""

while [ $# -gt 0 ]; do
  case "$1" in
    --manifest)
      MANIFEST_PATH="${2:-}"
      shift 2
      ;;
    *)
      echo "Usage: manifest-defaults.sh --manifest PATH" >&2
      exit 1
      ;;
  esac
done

if [ -z "$MANIFEST_PATH" ]; then
  echo "Usage: manifest-defaults.sh --manifest PATH" >&2
  exit 1
fi

if [ ! -f "$MANIFEST_PATH" ]; then
  echo "[Setup] manifest.json not found: $MANIFEST_PATH" >&2
  exit 1
fi

python3 - "$MANIFEST_PATH" <<'PY'
import json
import sys
from pathlib import Path

manifest_path = Path(sys.argv[1])
data = json.loads(manifest_path.read_text())

agent_platforms = data.get("agentPlatforms")
if not isinstance(agent_platforms, list):
    agent_platforms = []
for platform in ("claude", "codex", "cursor"):
    if platform not in agent_platforms:
        agent_platforms.append(platform)
data["agentPlatforms"] = agent_platforms

security = data.get("security")
if not isinstance(security, dict):
    security = {}
security.setdefault("sessionSummaryLevel", "auto")
data["security"] = security

manifest_path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
print(f"[Setup] manifest defaults ensured: {manifest_path}")
PY
