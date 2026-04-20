#!/usr/bin/env bash
# ai-symbiote MCP Store executor.
#
# Author: JunyoungJung
# Date: 2026-04-15

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../hooks/scripts/lib/common.sh"

CATALOG="$SCRIPT_DIR/../catalog.json"
SERVICE_PATTERNS_PATH="$SCRIPT_DIR/../../../lib/service-patterns.json"
STACK_ALIASES_PATH="$SCRIPT_DIR/../../../lib/stack-aliases.json"
STATE_DIR="${MCP_STORE_STATE_DIR:-$(ensure_state_dir)}"
MANIFEST_PATH="$STATE_DIR/manifest.json"
STATE_SUBDIR="$STATE_DIR/state"
COVERED_MCP_PATH="$STATE_SUBDIR/cli-covered-mcps.json"
RECOMMENDATION_PATH="$STATE_SUBDIR/mcp-store-recommendations.json"
PROJECT_ROOT_OVERRIDE="${MCP_STORE_PROJECT_ROOT:-}"
WRITE_STATE="${MCP_STORE_WRITE_STATE:-true}"

if [ ! -f "$CATALOG" ]; then
  echo "[MCP Store] catalog.json not found: $CATALOG" >&2
  exit 1
fi

if [ "$WRITE_STATE" = "true" ]; then
  mkdir -p "$STATE_DIR" "$STATE_SUBDIR"
fi

MODE="query"
QUERY=""
LIST_CATEGORY=""
INSTALL_ID=""

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
    --install)
      MODE="install"
      INSTALL_ID="${2:-}"
      shift 2
      ;;
    *)
      QUERY="$1"
      shift
      ;;
  esac
done

query_catalog() {
  local mode="$1" arg="$2" project_root="$3" covered_path="$4"
  python3 - "$CATALOG" "$mode" "$arg" "$project_root" "$covered_path" "$SERVICE_PATTERNS_PATH" "$STACK_ALIASES_PATH" <<'PY'
import json, sys
from pathlib import Path

catalog = json.loads(Path(sys.argv[1]).read_text())
mode = sys.argv[2]
arg = sys.argv[3].strip().lower()
project_root_arg = sys.argv[4].strip()
covered_path = Path(sys.argv[5])
sp_path = Path(sys.argv[6])
alias_path = Path(sys.argv[7])

all_patterns = json.loads(sp_path.read_text())
catalog_services = set(catalog.get("services", {}).keys())
SERVICE_PATTERNS = {k: v for k, v in all_patterns["patterns"].items() if k in catalog_services}
CANDIDATE_FILES = all_patterns.get("candidateFiles", [])

ALIAS_MAP = {}
if alias_path.exists():
    try:
        ALIAS_MAP = json.loads(alias_path.read_text()).get("aliases", {}) or {}
    except Exception:
        ALIAS_MAP = {}

def expand_keys(raw_keys):
    expanded = []
    seen = set()
    for raw in raw_keys:
        if not isinstance(raw, str):
            continue
        key = raw.strip().lower()
        if not key or key in seen:
            continue
        seen.add(key)
        expanded.append(key)
        for mapped in ALIAS_MAP.get(key, []):
            mapped_key = str(mapped).strip().lower()
            if mapped_key and mapped_key not in seen:
                seen.add(mapped_key)
                expanded.append(mapped_key)
    return expanded

def detect_project_root(manifest_path):
    if project_root_arg:
        return Path(project_root_arg)
    if manifest_path.exists():
        try:
            manifest = json.loads(manifest_path.read_text())
        except Exception:
            manifest = {}
        for key in ("projectPath", "path"):
            value = manifest.get(key)
            if isinstance(value, str) and value:
                return Path(value)
    return manifest_path.parent if manifest_path.parent.exists() else None

def scan_services(project_root):
    if project_root is None or not project_root.exists():
        return []
    haystacks = []
    for name in CANDIDATE_FILES:
        path = project_root / name
        if path.is_file():
            try:
                haystacks.append(path.read_text(encoding="utf-8", errors="ignore").lower())
            except Exception:
                pass
    try:
        for pbx in project_root.glob("*.xcodeproj/project.pbxproj"):
            if pbx.is_file():
                haystacks.append(pbx.read_text(encoding="utf-8", errors="ignore").lower())
    except Exception:
        pass
    try:
        if any(project_root.rglob("*.tf")):
            haystacks.append(".tf")
    except Exception:
        pass
    matches = []
    for service, patterns in SERVICE_PATTERNS.items():
        if any(pattern.lower() in hay for hay in haystacks for pattern in patterns):
            matches.append(service)
    return matches

def read_covered_ids():
    if not covered_path.exists():
        return set()
    try:
        payload = json.loads(covered_path.read_text())
    except Exception:
        return set()
    return set(payload.get("coveredMcpIds", []))

def flatten_entries():
    items = []
    for section_name in ("stacks", "services", "domains"):
        for group, entries in catalog.get(section_name, {}).items():
            for entry in entries:
                payload = dict(entry)
                payload["_section"] = section_name
                payload["_group"] = group
                items.append(payload)
    return items

if mode == "list":
    print(json.dumps(catalog.get(arg, {}), separators=(",", ":")))
    raise SystemExit(0)

if mode == "auto":
    manifest_path = Path(arg)
    raw_keys = []
    if manifest_path.exists():
        try:
            manifest = json.loads(manifest_path.read_text())
            project = manifest.get("project", {}) or {}
            stack = manifest.get("stack", {}) or {}
            raw_keys.extend(project.get("languages", []) or [])
            raw_keys.extend(project.get("platforms", []) or [])
            raw_keys.extend(stack.get("frameworks", []) or [])
            build_tool = stack.get("buildTool")
            if build_tool:
                raw_keys.append(build_tool)
            ptype = project.get("type")
            if ptype:
                raw_keys.append(ptype)
        except Exception:
            pass
    lookup_keys = expand_keys(raw_keys)
    matched = []
    seen = set()
    for key in lookup_keys:
        for entry in catalog.get("stacks", {}).get(key, []):
            if entry["id"] not in seen:
                seen.add(entry["id"])
                matched.append(entry)
    for key in scan_services(detect_project_root(manifest_path)):
        for entry in catalog.get("services", {}).get(key, []):
            if entry["id"] not in seen:
                seen.add(entry["id"])
                matched.append(entry)

    covered_ids = read_covered_ids()
    payload = {"recommended": [], "covered": []}
    for entry in matched:
        if entry["id"] in covered_ids:
            payload["covered"].append(entry)
        else:
            payload["recommended"].append(entry)
    print(json.dumps(payload, separators=(",", ":")))
    raise SystemExit(0)

matches = []
for entry in flatten_entries():
    hay = " ".join([
        entry.get("id", ""),
        entry.get("name", ""),
        entry.get("repo", ""),
        entry.get("description", ""),
        entry.get("_group", ""),
        entry.get("category", ""),
    ]).lower()
    if arg and arg in hay:
        matches.append(entry)
print(json.dumps(matches, separators=(",", ":")))
PY
}

write_recommendations() {
  local payload_json="$1"
  [ "$WRITE_STATE" = "true" ] || return 0
  python3 - "$RECOMMENDATION_PATH" "$payload_json" <<'PY'
import json, sys
from datetime import datetime, UTC
from pathlib import Path

path = Path(sys.argv[1])
payload = json.loads(sys.argv[2])
payload["generatedAt"] = datetime.now(UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z")
path.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n")
PY
}

lookup_mcp_entry() {
  local mcp_id="$1"
  python3 - "$CATALOG" "$mcp_id" <<'PY'
import json, sys
from pathlib import Path

catalog = json.loads(Path(sys.argv[1]).read_text())
target = sys.argv[2].strip().lower()

for section_name in ("stacks", "services", "domains"):
    for _group, entries in catalog.get(section_name, {}).items():
        for entry in entries:
            if entry.get("id", "").lower() == target:
                print(json.dumps(entry, separators=(",", ":")))
                raise SystemExit(0)
print("")
PY
}

record_mcp_installation() {
  local entry_json="$1"
  [ "$WRITE_STATE" = "true" ] || return 0
  python3 - "$MANIFEST_PATH" "$STATE_SUBDIR/mcp-store-installed.json" "$entry_json" <<'PY'
import json, os, sys
from datetime import datetime, UTC
from pathlib import Path

manifest_path = Path(sys.argv[1])
installed_path = Path(sys.argv[2])
entry = json.loads(sys.argv[3])
now = datetime.now(UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z")

required_env = entry.get("env", [])
env_values = {key: os.environ.get(key, "") for key in required_env}
status = "configured"
if required_env and any(not env_values[key] for key in required_env):
    status = "needs-env"

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

manifest = {}
if manifest_path.exists():
    try:
        manifest = json.loads(manifest_path.read_text())
    except Exception:
        manifest = {}

manifest.setdefault("mcpServers", {})
existing_entry = manifest["mcpServers"].get(entry["id"], {})
manifest["mcpServers"][entry["id"]] = deep_merge(existing_entry, {
    "name": entry.get("name"),
    "transport": entry.get("transport"),
    "command": entry.get("command"),
    "args": entry.get("args", []),
    "env": required_env,
    "installed": now,
    "status": status,
})
manifest_path.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n")

installed = {"generatedAt": now, "items": []}
if installed_path.exists():
    try:
        installed = json.loads(installed_path.read_text())
    except Exception:
        installed = {"generatedAt": now, "items": []}

items = [item for item in installed.get("items", []) if item.get("id") != entry["id"]]
items.append({
    "id": entry["id"],
    "name": entry.get("name"),
    "transport": entry.get("transport"),
    "command": entry.get("command"),
    "args": entry.get("args", []),
    "env": required_env,
    "status": status,
    "installed": now,
})
installed["generatedAt"] = now
installed["items"] = sorted(items, key=lambda item: item["id"])
installed_path.write_text(json.dumps(installed, indent=2, ensure_ascii=False) + "\n")

print(status)
print(json.dumps(env_values, separators=(",", ":")))
PY
}

run_auto_mode() {
  if [ ! -f "$MANIFEST_PATH" ]; then
    echo "[MCP Store] manifest.json not found. Run setup in plan mode first."
    exit 0
  fi
  local payload_json
  payload_json=$(query_catalog auto "$MANIFEST_PATH" "$PROJECT_ROOT_OVERRIDE" "$COVERED_MCP_PATH")
  write_recommendations "$payload_json"
  python3 - "$payload_json" <<'PY'
import json, sys
payload = json.loads(sys.argv[1])
recommended = payload.get("recommended", [])
covered = payload.get("covered", [])
if not recommended and not covered:
    print("[MCP Store] No automatic MCP recommendations.")
    raise SystemExit(0)
print("[MCP Store] Automatic MCP recommendations:")
for item in recommended:
    print(f"  - {item['name']} ({item['id']}) — {item.get('description','')}")
for item in covered:
    print(f"  - ~~{item['name']} ({item['id']})~~ — covered by CLI")
PY
}

run_list_mode() {
  if [ -z "$LIST_CATEGORY" ]; then
    echo "Usage: mcp-store --list <stacks|services|domains>"
    exit 1
  fi
  python3 - "$CATALOG" "$LIST_CATEGORY" <<'PY'
import json, sys
catalog = json.loads(open(sys.argv[1]).read())
section = catalog.get(sys.argv[2])
if not isinstance(section, dict):
    print(f"[MCP Store] Unknown category: {sys.argv[2]}")
    raise SystemExit(1)
print(f"[MCP Store] {sys.argv[2]}:")
for key, entries in sorted(section.items()):
    names = ", ".join(entry["id"] for entry in entries)
    print(f"  - {key}: {names}")
PY
}

run_query_mode() {
  if [ -z "$QUERY" ]; then
    echo "Usage: mcp-store [--auto | --list <category> | <query>]"
    exit 1
  fi
  local matches_json
  matches_json=$(query_catalog query "$QUERY" "$PROJECT_ROOT_OVERRIDE" "$COVERED_MCP_PATH")
  python3 - "$matches_json" "$QUERY" <<'PY'
import json, sys
items = json.loads(sys.argv[1])
query = sys.argv[2]
if not items:
    print(f"[MCP Store] No MCP servers found for \"{query}\".")
    raise SystemExit(0)
print("[MCP Store] Matching MCP servers:")
for idx, item in enumerate(items, start=1):
    print(f"  {idx}. {item['name']} ({item['id']})")
PY
}

run_install_mode() {
  if [ -z "$INSTALL_ID" ]; then
    echo "Usage: mcp-store --install <id>"
    exit 1
  fi
  local entry_json install_result status env_json
  entry_json=$(lookup_mcp_entry "$INSTALL_ID")
  if [ -z "$entry_json" ]; then
    echo "[MCP Store] MCP server not found in catalog: $INSTALL_ID"
    exit 1
  fi

  install_result=$(record_mcp_installation "$entry_json")
  status=$(printf '%s\n' "$install_result" | sed -n '1p')
  env_json=$(printf '%s\n' "$install_result" | sed -n '2p')

  python3 - "$entry_json" "$status" "$env_json" <<'PY'
import json, sys
entry = json.loads(sys.argv[1])
status = sys.argv[2]
env_values = json.loads(sys.argv[3])

print(f"[MCP Store] {entry['name']} recorded in manifest.")
if status == "needs-env":
    missing = [key for key, value in env_values.items() if not value]
    print(f"[MCP Store] Missing env: {', '.join(missing)}")
else:
    print(f"[MCP Store] Status: {status}")
PY
}

case "$MODE" in
  auto)
    run_auto_mode
    ;;
  install)
    run_install_mode
    ;;
  list)
    run_list_mode
    ;;
  query)
    run_query_mode
    ;;
  *)
    echo "Usage: mcp-store [--auto | --list <category> | <query>]"
    exit 1
    ;;
esac
