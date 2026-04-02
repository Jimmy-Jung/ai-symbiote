#!/usr/bin/env bash
# ai-symbiote Codex local installer
# Author: JunyoungJung
# Date: 2026-04-02

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PLUGIN_NAME="ai-symbiote"
DIST_BUNDLE_NAME="codex-symbiote"
TARGET_PLUGINS_DIR="${CODEX_HOME_PLUGINS_DIR:-$HOME/plugins}"
TARGET_PLUGIN_DIR="$TARGET_PLUGINS_DIR/$PLUGIN_NAME"
AGENTS_DIR="${CODEX_AGENTS_DIR:-$HOME/.agents/plugins}"
MARKETPLACE_PATH="${CODEX_MARKETPLACE_PATH:-$AGENTS_DIR/marketplace.json}"
DEFAULT_MARKETPLACE_NAME="${CODEX_MARKETPLACE_NAME:-jimmy-local}"
DEFAULT_DISPLAY_NAME="${CODEX_MARKETPLACE_DISPLAY_NAME:-Jimmy Local Plugins}"
CODEX_CONFIG_PATH="${CODEX_CONFIG_PATH:-$HOME/.codex/config.toml}"
CODEX_CACHE_ROOT="${CODEX_CACHE_ROOT:-$HOME/.codex/plugins/cache}"
CODEX_TMP_ROOT="${CODEX_TMP_ROOT:-$HOME/.codex/.tmp/plugins}"
CODEX_TMP_PLUGIN_DIR="$CODEX_TMP_ROOT/plugins/$PLUGIN_NAME"
CODEX_TMP_MARKETPLACE_PATH="$CODEX_TMP_ROOT/.agents/plugins/marketplace.json"

if ! command -v python3 >/dev/null 2>&1; then
  echo "error: python3 is required" >&2
  exit 1
fi

bash "$REPO_ROOT/scripts/build-codex.sh"
SOURCE_PLUGIN_DIR="$REPO_ROOT/dist/$DIST_BUNDLE_NAME"

sync_plugin_dir() {
  local source_dir="$1"
  local target_dir="$2"

  mkdir -p "$target_dir"
  rsync -a --delete \
    --exclude '.git' \
    --exclude '.DS_Store' \
    "$source_dir/" "$target_dir/"
}

update_marketplace() {
  local marketplace_path="$1"
  local default_name="$2"
  local default_display_name="$3"

  python3 - "$marketplace_path" "$PLUGIN_NAME" "$default_name" "$default_display_name" <<'PY'
import json
import sys
from pathlib import Path

marketplace_path = Path(sys.argv[1])
plugin_name = sys.argv[2]
default_name = sys.argv[3]
default_display_name = sys.argv[4]

plugin_entry = {
    "name": plugin_name,
    "source": {
        "source": "local",
        "path": f"./plugins/{plugin_name}",
    },
    "policy": {
        "installation": "INSTALLED_BY_DEFAULT",
        "authentication": "ON_INSTALL",
    },
    "category": "Productivity",
}

if marketplace_path.exists():
    with marketplace_path.open("r", encoding="utf-8") as fh:
        data = json.load(fh)
else:
    data = {
        "name": default_name,
        "interface": {
            "displayName": default_display_name,
        },
        "plugins": [],
    }

data.setdefault("name", default_name)
interface = data.setdefault("interface", {})
if not isinstance(interface, dict):
    interface = {}
    data["interface"] = interface
interface.setdefault("displayName", default_display_name)

plugins = data.setdefault("plugins", [])
updated = False
for index, entry in enumerate(plugins):
    if isinstance(entry, dict) and entry.get("name") == plugin_name:
        plugins[index] = plugin_entry
        updated = True
        break

if not updated:
    plugins.append(plugin_entry)

marketplace_path.parent.mkdir(parents=True, exist_ok=True)
with marketplace_path.open("w", encoding="utf-8") as fh:
    json.dump(data, fh, ensure_ascii=False, indent=2)
    fh.write("\n")
PY
}

mkdir -p "$TARGET_PLUGINS_DIR" "$AGENTS_DIR"

echo "[1/6] plugin bundle sync"
sync_plugin_dir "$SOURCE_PLUGIN_DIR" "$TARGET_PLUGIN_DIR"

echo "[2/6] home marketplace update"
update_marketplace "$MARKETPLACE_PATH" "$DEFAULT_MARKETPLACE_NAME" "$DEFAULT_DISPLAY_NAME"

MARKETPLACE_NAME="$(python3 - "$MARKETPLACE_PATH" <<'PY'
import json
import sys
from pathlib import Path

with Path(sys.argv[1]).open("r", encoding="utf-8") as fh:
    print(json.load(fh)["name"])
PY
)"

CACHE_PLUGIN_DIR="$CODEX_CACHE_ROOT/$MARKETPLACE_NAME/$PLUGIN_NAME/local"

echo "[3/6] Codex config update"
python3 - "$MARKETPLACE_PATH" "$CODEX_CONFIG_PATH" "$PLUGIN_NAME" <<'PY'
import json
import sys
from pathlib import Path

marketplace_path = Path(sys.argv[1])
config_path = Path(sys.argv[2])
plugin_name = sys.argv[3]

with marketplace_path.open("r", encoding="utf-8") as fh:
    marketplace = json.load(fh)

marketplace_name = marketplace["name"]
plugin_key = f'{plugin_name}@{marketplace_name}'
header = f'[plugins."{plugin_key}"]'
enabled_line = "enabled = true"

config_path.parent.mkdir(parents=True, exist_ok=True)
if config_path.exists():
    lines = config_path.read_text(encoding="utf-8").splitlines()
else:
    lines = []

for index, line in enumerate(lines):
    if line.strip() != header:
      continue

    cursor = index + 1
    found_enabled = False
    while cursor < len(lines) and not lines[cursor].startswith("["):
        if lines[cursor].strip().startswith("enabled"):
            lines[cursor] = enabled_line
            found_enabled = True
            break
        cursor += 1

    if not found_enabled:
        lines.insert(index + 1, enabled_line)

    config_path.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")
    break
else:
    if lines and lines[-1].strip():
        lines.append("")
    lines.append(header)
    lines.append(enabled_line)
    config_path.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")
PY

echo "[4/6] Codex cache install sync"
sync_plugin_dir "$SOURCE_PLUGIN_DIR" "$CACHE_PLUGIN_DIR"

echo "[5/6] Codex tmp plugin mirror sync"
sync_plugin_dir "$SOURCE_PLUGIN_DIR" "$CODEX_TMP_PLUGIN_DIR"
update_marketplace "$CODEX_TMP_MARKETPLACE_PATH" "$DEFAULT_MARKETPLACE_NAME" "$DEFAULT_DISPLAY_NAME"

echo "[6/6] install summary"
echo "plugin: $TARGET_PLUGIN_DIR"
echo "marketplace: $MARKETPLACE_PATH"
echo "config: $CODEX_CONFIG_PATH"
echo "cache: $CACHE_PLUGIN_DIR"
echo "tmp mirror: $CODEX_TMP_PLUGIN_DIR"
