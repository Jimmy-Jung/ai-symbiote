#!/usr/bin/env bash
# ai-symbiote CLI Store executor.
#
# Author: JunyoungJung
# Date: 2026-04-14

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../hooks/scripts/lib/common.sh"

CATALOG="$SCRIPT_DIR/../catalog.json"
STATE_DIR="${CLI_STORE_STATE_DIR:-$(ensure_state_dir)}"
MANIFEST_PATH="$STATE_DIR/manifest.json"
STATE_SUBDIR="$STATE_DIR/state"
COVERED_MCP_PATH="$STATE_SUBDIR/cli-covered-mcps.json"

mkdir -p "$STATE_DIR" "$STATE_SUBDIR"

MODE="query"
QUERY=""
LIST_CATEGORY=""
DRY_RUN="false"

while [ $# -gt 0 ]; do
  case "$1" in
    --auto)
      MODE="auto"
      shift
      ;;
    --list)
      MODE="list"
      LIST_CATEGORY="${2:-}"
      shift 2
      ;;
    --dry-run)
      DRY_RUN="true"
      shift
      ;;
    *)
      QUERY="$1"
      shift
      ;;
  esac
done

detect_package_manager() {
  if [ -n "${CLI_STORE_FORCE_PM:-}" ]; then
    echo "$CLI_STORE_FORCE_PM"
  elif command -v brew >/dev/null 2>&1; then
    echo "brew"
  elif command -v apt >/dev/null 2>&1; then
    echo "apt"
  elif command -v npm >/dev/null 2>&1; then
    echo "npm"
  elif command -v pip >/dev/null 2>&1 || command -v python3 >/dev/null 2>&1; then
    echo "pip"
  else
    echo "unknown"
  fi
}

tool_forced_status() {
  local tool_id="$1"
  local env_name="CLI_STORE_FORCE_STATUS_$(printf '%s' "$tool_id" | tr '[:lower:]-' '[:upper:]_')"
  local value="${!env_name:-}"
  if [ -n "$value" ]; then
    echo "$value"
    return 0
  fi
  return 1
}

tool_forced_after_status() {
  local tool_id="$1"
  local env_name="CLI_STORE_FORCE_STATUS_AFTER_$(printf '%s' "$tool_id" | tr '[:lower:]-' '[:upper:]_')"
  local value="${!env_name:-}"
  if [ -n "$value" ]; then
    echo "$value"
    return 0
  fi
  return 1
}

tool_forced_install_command() {
  local tool_id="$1"
  local env_name="CLI_STORE_FORCE_INSTALL_CMD_$(printf '%s' "$tool_id" | tr '[:lower:]-' '[:upper:]_')"
  local value="${!env_name:-}"
  if [ -n "$value" ]; then
    echo "$value"
    return 0
  fi
  return 1
}

query_catalog() {
  local mode="$1" arg="$2"
  python3 - "$CATALOG" "$mode" "$arg" <<'PY'
import json, sys
from pathlib import Path
from datetime import datetime, UTC

catalog = json.loads(Path(sys.argv[1]).read_text())
mode = sys.argv[2]
arg = sys.argv[3].strip().lower()

def all_entries():
    items = []
    for section_name in ("stacks", "services", "domains"):
        for group, entries in catalog.get(section_name, {}).items():
            for entry in entries:
                payload = dict(entry)
                payload["_section"] = section_name
                payload["_group"] = group
                items.append(payload)
    return items

entries = all_entries()

if mode == "list":
    groups = catalog.get(arg, {})
    print(json.dumps(groups, separators=(",", ":")))
    raise SystemExit(0)

if mode == "auto":
    languages = []
    frameworks = []
    manifest_path = Path(arg)
    if manifest_path.exists():
        try:
            manifest = json.loads(manifest_path.read_text())
            languages = [str(x).lower() for x in manifest.get("project", {}).get("languages", [])]
            frameworks = [str(x).lower() for x in manifest.get("stack", {}).get("frameworks", [])]
        except Exception:
            pass
    matched = []
    seen = set()
    for key in languages + frameworks:
        for entry in catalog.get("stacks", {}).get(key, []):
            if entry["id"] not in seen:
                seen.add(entry["id"])
                matched.append(entry)
    print(json.dumps(matched, separators=(",", ":")))
    raise SystemExit(0)

matches = []
for entry in entries:
    hay = " ".join([
        entry.get("id", ""),
        entry.get("name", ""),
        entry.get("cmd", ""),
        entry.get("description", ""),
        entry.get("_group", ""),
        entry.get("category", ""),
    ]).lower()
    exact = arg in {entry.get("id", "").lower(), entry.get("name", "").lower(), entry.get("cmd", "").lower()}
    if exact or (arg and arg in hay):
        payload = dict(entry)
        payload["_exact"] = exact
        matches.append(payload)

matches.sort(key=lambda item: (0 if item.get("_exact") else 1, item.get("id", "")))
dedup = []
seen = set()
for item in matches:
    if item["id"] in seen:
        continue
    seen.add(item["id"])
    dedup.append(item)
print(json.dumps(dedup, separators=(",", ":")))
PY
}

get_tool_status() {
  local tool_id="$1" check_cmd="$2"
  if tool_forced_status "$tool_id" >/dev/null 2>&1; then
    tool_forced_status "$tool_id"
    return 0
  fi
  if bash -c "$check_cmd" >/dev/null 2>&1; then
    echo "ready"
  else
    echo "not-ready"
  fi
}

pick_install_command() {
  local manager="$1" entry_json="$2"
  python3 - "$manager" "$entry_json" <<'PY'
import json, sys
manager = sys.argv[1]
entry = json.loads(sys.argv[2])
cmds = entry.get("installCmd", {})
cmd = cmds.get(manager)
if not cmd and cmds:
    for key in ("brew", "apt", "npm", "pip", "xcode"):
        if key in cmds:
            cmd = cmds[key]
            break
print(cmd or "")
PY
}

update_manifest_and_state() {
  local entry_json="$1" status="$2"
  python3 - "$MANIFEST_PATH" "$COVERED_MCP_PATH" "$entry_json" "$status" <<'PY'
import json, sys
from datetime import datetime, UTC
from pathlib import Path

manifest_path = Path(sys.argv[1])
covered_path = Path(sys.argv[2])
entry = json.loads(sys.argv[3])
status = sys.argv[4]
now = datetime.now(UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z")

manifest = {}
if manifest_path.exists():
    try:
        manifest = json.loads(manifest_path.read_text())
    except Exception:
        manifest = {}
manifest.setdefault("cliTools", {})
manifest["cliTools"][entry["id"]] = {
    "cmd": entry["cmd"],
    "installed": now,
    "mcpEquivalent": entry.get("mcpEquivalent"),
    "status": status,
}
manifest_path.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n")

covered = {"coveredMcpIds": [], "generatedAt": now}
if covered_path.exists():
    try:
        covered = json.loads(covered_path.read_text())
    except Exception:
        covered = {"coveredMcpIds": [], "generatedAt": now}
covered_ids = set(covered.get("coveredMcpIds", []))
if status == "ready" and entry.get("mcpEquivalent"):
    covered_ids.add(entry["mcpEquivalent"])
covered["coveredMcpIds"] = sorted(covered_ids)
covered["generatedAt"] = now
covered_path.write_text(json.dumps(covered, indent=2, ensure_ascii=False) + "\n")
PY
}

print_match_list() {
  local matches_json="$1"
  python3 - "$matches_json" <<'PY'
import json, sys
matches = json.loads(sys.argv[1])
if not matches:
    print("[CLI Store] No matching CLI tools found.")
    raise SystemExit(0)
print("[CLI Store] Matching CLI tools:")
for idx, item in enumerate(matches, start=1):
    print(f"  {idx}. {item['id']} — {item.get('description','')}")
PY
}

run_query_mode() {
  local manager matches_json count
  manager=$(detect_package_manager)
  matches_json=$(query_catalog query "$QUERY")
  count=$(python3 - "$matches_json" <<'PY'
import json, sys
print(len(json.loads(sys.argv[1])))
PY
)

  if [ "$count" -eq 0 ]; then
    echo "[CLI Store] No CLI tools found for \"$QUERY\"."
    exit 0
  fi

  if [ "$count" -gt 1 ]; then
    print_match_list "$matches_json"
    exit 0
  fi

  local entry_json tool_id tool_name check_cmd status install_cmd
  entry_json=$(python3 - "$matches_json" <<'PY'
import json, sys
print(json.dumps(json.loads(sys.argv[1])[0], separators=(",", ":")))
PY
)
  tool_id=$(python3 - "$entry_json" <<'PY'
import json, sys
print(json.loads(sys.argv[1])["id"])
PY
)
  tool_name=$(python3 - "$entry_json" <<'PY'
import json, sys
print(json.loads(sys.argv[1])["name"])
PY
)
  check_cmd=$(python3 - "$entry_json" <<'PY'
import json, sys
print(json.loads(sys.argv[1])["checkCmd"])
PY
)
  status=$(get_tool_status "$tool_id" "$check_cmd")
  install_cmd=$(pick_install_command "$manager" "$entry_json")

  if [ "$status" = "ready" ]; then
    update_manifest_and_state "$entry_json" "ready"
    echo "[CLI Store] $tool_name is already ready."
    exit 0
  fi

  if [ "$DRY_RUN" = "true" ]; then
    echo "[CLI Store] $tool_name is installable."
    echo "Install: $install_cmd"
    echo "After install, rerun: /ai-symbiote:cli-store $tool_id"
    exit 0
  fi

  if [ -z "$install_cmd" ]; then
    echo "[CLI Store] No install command available for $tool_name on this system."
    exit 1
  fi

  if tool_forced_install_command "$tool_id" >/dev/null 2>&1; then
    install_cmd=$(tool_forced_install_command "$tool_id")
  fi

  echo "[CLI Store] Installing $tool_name..."
  bash -c "$install_cmd"

  if tool_forced_after_status "$tool_id" >/dev/null 2>&1; then
    status=$(tool_forced_after_status "$tool_id")
  else
    status=$(get_tool_status "$tool_id" "$check_cmd")
  fi
  if [ "$status" = "ready" ]; then
    update_manifest_and_state "$entry_json" "ready"
    echo "[CLI Store] $tool_name installed and ready."
  else
    update_manifest_and_state "$entry_json" "installed"
    echo "[CLI Store] $tool_name installed, but additional setup may be required."
  fi
}

run_list_mode() {
  if [ -z "$LIST_CATEGORY" ]; then
    echo "Usage: cli-store --list <stacks|services|domains>"
    exit 1
  fi
  python3 - "$CATALOG" "$LIST_CATEGORY" <<'PY'
import json, sys
catalog = json.loads(open(sys.argv[1]).read())
category = sys.argv[2]
section = catalog.get(category)
if not isinstance(section, dict):
    print(f"[CLI Store] Unknown category: {category}")
    raise SystemExit(1)
print(f"[CLI Store] {category}:")
for key, entries in sorted(section.items()):
    names = ", ".join(entry["id"] for entry in entries)
    print(f"  - {key}: {names}")
PY
}

run_auto_mode() {
  local manifest matches_json
  manifest="$MANIFEST_PATH"
  if [ ! -f "$manifest" ]; then
    echo "[CLI Store] manifest.json not found. Run setup first."
    exit 0
  fi
  matches_json=$(query_catalog auto "$manifest")
  python3 - "$matches_json" <<'PY'
import json, sys
items = json.loads(sys.argv[1])
if not items:
    print("[CLI Store] No automatic CLI recommendations.")
    raise SystemExit(0)
print("[CLI Store] Automatic CLI recommendations:")
for item in items:
    print(f"  - {item['id']} — {item.get('description','')}")
PY
}

case "$MODE" in
  query)
    if [ -z "$QUERY" ]; then
      echo "Usage: cli-store [--dry-run] <query>"
      exit 1
    fi
    run_query_mode
    ;;
  list)
    run_list_mode
    ;;
  auto)
    run_auto_mode
    ;;
  *)
    echo "Usage: cli-store [--auto | --list <category> | <query>] [--dry-run]"
    exit 1
    ;;
esac
