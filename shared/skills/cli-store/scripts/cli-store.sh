#!/usr/bin/env bash
# ai-symbiote CLI Store executor.
#
# Author: JunyoungJung
# Date: 2026-04-14

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../hooks/scripts/lib/common.sh"

CATALOG="$SCRIPT_DIR/../catalog.json"
SERVICE_PATTERNS_PATH="$SCRIPT_DIR/../../../lib/service-patterns.json"
STACK_ALIASES_PATH="$SCRIPT_DIR/../../../lib/stack-aliases.json"
STATE_DIR="${CLI_STORE_STATE_DIR:-$(ensure_state_dir)}"
MANIFEST_PATH="$STATE_DIR/manifest.json"
STATE_SUBDIR="$STATE_DIR/state"
COVERED_MCP_PATH="$STATE_SUBDIR/cli-covered-mcps.json"
RECOMMENDATION_PATH="$STATE_SUBDIR/cli-store-recommendations.json"
PROJECT_ROOT_OVERRIDE="${CLI_STORE_PROJECT_ROOT:-}"
WRITE_STATE="${CLI_STORE_WRITE_STATE:-true}"

if [ ! -f "$CATALOG" ]; then
  echo "[CLI Store] catalog.json not found: $CATALOG" >&2
  exit 1
fi

if [ "$WRITE_STATE" = "true" ]; then
  mkdir -p "$STATE_DIR" "$STATE_SUBDIR"
fi

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
  local mode="$1" arg="$2" project_root="$3"
  python3 - "$CATALOG" "$mode" "$arg" "$project_root" "$SERVICE_PATTERNS_PATH" "$STACK_ALIASES_PATH" <<'PY'
import json, sys
from pathlib import Path

catalog = json.loads(Path(sys.argv[1]).read_text())
mode = sys.argv[2]
arg = sys.argv[3].strip().lower()
project_root_arg = sys.argv[4].strip()
sp_path = Path(sys.argv[5])
alias_path = Path(sys.argv[6])

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
  [ "$WRITE_STATE" = "true" ] || return 0
  python3 - "$MANIFEST_PATH" "$COVERED_MCP_PATH" "$entry_json" "$status" <<'PY'
import json, sys
from datetime import datetime, UTC
from pathlib import Path

manifest_path = Path(sys.argv[1])
covered_path = Path(sys.argv[2])
entry = json.loads(sys.argv[3])
status = sys.argv[4]
now = datetime.now(UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z")

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
manifest.setdefault("cliTools", {})
existing_entry = manifest["cliTools"].get(entry["id"], {})
manifest["cliTools"][entry["id"]] = deep_merge(existing_entry, {
    "cmd": entry["cmd"],
    "installed": now,
    "mcpEquivalent": entry.get("mcpEquivalent"),
    "status": status,
})
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

overwrite_covered_mcp_state() {
  local covered_ids_json="$1"
  [ "$WRITE_STATE" = "true" ] || return 0
  python3 - "$COVERED_MCP_PATH" "$covered_ids_json" <<'PY'
import json, sys
from datetime import datetime, UTC
from pathlib import Path

path = Path(sys.argv[1])
covered_ids = sorted(set(json.loads(sys.argv[2])))
payload = {
    "coveredMcpIds": covered_ids,
    "generatedAt": datetime.now(UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
}
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n")
PY
}

write_auto_recommendations() {
  local payload_json="$1"
  [ "$WRITE_STATE" = "true" ] || return 0
  python3 - "$RECOMMENDATION_PATH" "$payload_json" <<'PY'
import json, sys
from datetime import datetime, UTC
from pathlib import Path

path = Path(sys.argv[1])
payload = json.loads(sys.argv[2])
payload["generatedAt"] = datetime.now(UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z")
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n")
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
  matches_json=$(query_catalog query "$QUERY" "$PROJECT_ROOT_OVERRIDE")
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
  if ! bash -c "$install_cmd"; then
    echo "[CLI Store] Installation command failed for $tool_name." >&2
    update_manifest_and_state "$entry_json" "install-failed"
    return 0
  fi

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
    echo "[CLI Store] manifest.json not found. Run setup in plan mode first."
    exit 0
  fi
  matches_json=$(query_catalog auto "$manifest" "$PROJECT_ROOT_OVERRIDE")
  local count manager
  count=$(python3 - "$matches_json" <<'PY'
import json, sys
print(len(json.loads(sys.argv[1])))
PY
)
  if [ "$count" -eq 0 ]; then
    python3 - "$COVERED_MCP_PATH" <<'PY'
import json, sys
from datetime import datetime, UTC
from pathlib import Path

path = Path(sys.argv[1])
path.parent.mkdir(parents=True, exist_ok=True)
payload = {
    "coveredMcpIds": [],
    "generatedAt": datetime.now(UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
}
path.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n")
print("[CLI Store] No automatic CLI recommendations.")
PY
    exit 0
  fi

  manager=$(detect_package_manager)
  local ready_lines="" install_lines="" ready_ids_json="[]"
  local recommendations_json='{"ready":[],"installable":[]}'
  while IFS= read -r entry_json; do
    [ -z "$entry_json" ] && continue
    local tool_id tool_name description check_cmd status install_cmd line
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
    description=$(python3 - "$entry_json" <<'PY'
import json, sys
print(json.loads(sys.argv[1]).get("description", ""))
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
      ready_ids_json=$(python3 - "$ready_ids_json" "$entry_json" <<'PY'
import json, sys
ready_ids = json.loads(sys.argv[1])
entry = json.loads(sys.argv[2])
mcp_id = entry.get("mcpEquivalent")
if mcp_id and mcp_id not in ready_ids:
    ready_ids.append(mcp_id)
print(json.dumps(ready_ids, separators=(",", ":")))
PY
)
      recommendations_json=$(python3 - "$recommendations_json" "$entry_json" <<'PY'
import json, sys
payload = json.loads(sys.argv[1])
entry = json.loads(sys.argv[2])
payload["ready"].append(entry)
print(json.dumps(payload, separators=(",", ":")))
PY
)
      line="  ✓ $tool_id ($tool_name) — $description"
      ready_lines="${ready_lines}${line}\n"
    else
      line="  - $tool_id ($tool_name) — $description"
      if [ -n "$install_cmd" ]; then
        line="${line}\n    Install: $install_cmd"
      fi
      install_lines="${install_lines}${line}\n"
      recommendations_json=$(python3 - "$recommendations_json" "$entry_json" <<'PY'
import json, sys
payload = json.loads(sys.argv[1])
entry = json.loads(sys.argv[2])
payload["installable"].append(entry)
print(json.dumps(payload, separators=(",", ":")))
PY
)
    fi
  done < <(python3 - "$matches_json" <<'PY'
import json, sys
for item in json.loads(sys.argv[1]):
    print(json.dumps(item, separators=(",", ":")))
PY
)

  echo "[CLI Store] Automatic CLI recommendations:"
  if [ -n "$ready_lines" ]; then
    echo "Ready (will skip equivalent MCP servers):"
    printf "%b" "$ready_lines"
  fi
  if [ -n "$install_lines" ]; then
    echo "Recommended to install:"
    printf "%b" "$install_lines"
  fi
  overwrite_covered_mcp_state "$ready_ids_json"
  write_auto_recommendations "$recommendations_json"
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
