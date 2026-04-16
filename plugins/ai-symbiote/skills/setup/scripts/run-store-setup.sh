#!/usr/bin/env bash
# ai-symbiote setup store orchestrator.
#
# Author: JunyoungJung
# Date: 2026-04-15

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../hooks/scripts/lib/common.sh"

PLUGIN_ROOT="${CURSOR_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-${CODEX_PLUGIN_ROOT:-$(cd "$SCRIPT_DIR/../../.." && pwd)}}}"
STATE_DIR=""
PROJECT_ROOT=""
MODE="${SETUP_STORE_MODE:-guided}"

while [ $# -gt 0 ]; do
  case "$1" in
    --state-dir)
      STATE_DIR="${2:-}"
      shift 2
      ;;
    --project-root)
      PROJECT_ROOT="${2:-}"
      shift 2
      ;;
    --mode)
      MODE="${2:-}"
      shift 2
      ;;
    *)
      echo "Usage: run-store-setup.sh [--state-dir PATH] [--project-root PATH] [--mode fast|guided|dry-run]" >&2
      exit 1
      ;;
  esac
done

if [ -z "$STATE_DIR" ]; then
  STATE_DIR=$(ensure_state_dir)
fi

if [ -z "$PROJECT_ROOT" ]; then
  PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
fi

STATE_SUBDIR="$STATE_DIR/state"
MANIFEST_PATH="$STATE_DIR/manifest.json"
PREFERENCES_PATH="$STATE_SUBDIR/setup-store-preferences.json"
SUMMARY_PATH="$STATE_SUBDIR/setup-store-summary.json"
SKILL_RECOMMENDATION_PATH="$STATE_SUBDIR/skill-store-recommendations.json"
CLI_RECOMMENDATION_PATH="$STATE_SUBDIR/cli-store-recommendations.json"
MCP_RECOMMENDATION_PATH="$STATE_SUBDIR/mcp-store-recommendations.json"

mkdir -p "$STATE_DIR" "$STATE_SUBDIR"

bootstrap_manifest_if_missing() {
  if [ -f "$MANIFEST_PATH" ]; then
    return 0
  fi
  python3 - "$MANIFEST_PATH" "$PROJECT_ROOT" <<'PY'
import json, sys
from pathlib import Path

manifest_path = Path(sys.argv[1])
project_root = sys.argv[2]
payload = {
    "projectPath": project_root,
    "path": project_root,
    "project": {
        "languages": [],
    },
    "stack": {
        "frameworks": [],
    },
}
manifest_path.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n")
PY
  bash "$PLUGIN_ROOT/skills/setup/scripts/manifest-defaults.sh" --manifest "$MANIFEST_PATH" >/dev/null
  echo "[Setup] bootstrap manifest created: $MANIFEST_PATH"
}

run_recommendation_pass() {
  echo "[Setup] Running store recommendations..."
  if ! SKILL_STORE_STATE_DIR="$STATE_DIR" \
    SKILL_STORE_PROJECT_ROOT="$PROJECT_ROOT" \
    bash "$PLUGIN_ROOT/skills/skill-store/scripts/skill-store.sh" --auto; then
    echo "[Setup] WARNING: skill-store recommendation failed." >&2
  fi

  if ! CLI_STORE_STATE_DIR="$STATE_DIR" \
    CLI_STORE_PROJECT_ROOT="$PROJECT_ROOT" \
    bash "$PLUGIN_ROOT/skills/cli-store/scripts/cli-store.sh" --auto; then
    echo "[Setup] WARNING: cli-store recommendation failed." >&2
  fi

  if ! MCP_STORE_STATE_DIR="$STATE_DIR" \
    MCP_STORE_PROJECT_ROOT="$PROJECT_ROOT" \
    bash "$PLUGIN_ROOT/skills/mcp-store/scripts/mcp-store.sh" --auto; then
    echo "[Setup] WARNING: mcp-store recommendation failed." >&2
  fi
}

build_summary_file() {
  python3 - "$SUMMARY_PATH" "$SKILL_RECOMMENDATION_PATH" "$CLI_RECOMMENDATION_PATH" "$MCP_RECOMMENDATION_PATH" <<'PY'
import json, sys
from datetime import datetime, UTC
from pathlib import Path

summary_path = Path(sys.argv[1])
skill_path = Path(sys.argv[2])
cli_path = Path(sys.argv[3])
mcp_path = Path(sys.argv[4])

def load(path, default):
    if not path.exists():
        return default
    try:
        return json.loads(path.read_text())
    except Exception:
        return default

skill_data = load(skill_path, {"items": []})
cli_data = load(cli_path, {"ready": [], "installable": []})
mcp_data = load(mcp_path, {"recommended": [], "covered": []})

summary = {
    "generatedAt": datetime.now(UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
    "skills": {
        "items": skill_data.get("items", []),
        "count": len(skill_data.get("items", [])),
    },
    "cli": {
        "ready": cli_data.get("ready", []),
        "installable": cli_data.get("installable", []),
        "count": len(cli_data.get("installable", [])),
    },
    "mcp": {
        "recommended": mcp_data.get("recommended", []),
        "covered": mcp_data.get("covered", []),
        "count": len(mcp_data.get("recommended", [])),
    },
}
summary_path.write_text(json.dumps(summary, indent=2, ensure_ascii=False) + "\n")
PY
}

print_guided_summary() {
  python3 - "$SUMMARY_PATH" <<'PY'
import json, sys
summary = json.loads(open(sys.argv[1]).read())
print("[Setup] Guided setup summary:")
print(f"  - Skills: {summary['skills']['count']} recommended")
print(f"  - CLI: {summary['cli']['count']} installable, {len(summary['cli']['ready'])} already ready")
print(f"  - MCP: {summary['mcp']['count']} recommended, {len(summary['mcp']['covered'])} covered by CLI")
PY
}

prompt_or_default() {
  local env_name="$1" prompt_text="$2" default_value="later"
  local current="${!env_name:-}"
  if [ -n "$current" ]; then
    printf '%s' "$current"
    return 0
  fi
  if [ -t 0 ]; then
    printf "%s " "$prompt_text" >&2
    read -r current
    current="${current:-$default_value}"
    printf '%s' "$current"
    return 0
  fi
  printf '%s' "$default_value"
}

selection_from_recommendations() {
  local group="$1" selection="$2"
  python3 - "$SUMMARY_PATH" "$group" "$selection" <<'PY'
import json, sys

summary = json.loads(open(sys.argv[1]).read())
group = sys.argv[2]
selection = sys.argv[3].strip().lower()

if group == "skills":
    items = summary["skills"]["items"]
    keys = [item["repo"] for item in items]
elif group == "cli":
    items = summary["cli"]["installable"]
    keys = [item["id"] for item in items]
else:
    items = summary["mcp"]["recommended"]
    keys = [item["id"] for item in items]

if selection in ("", "later", "skip"):
    print("[]")
    raise SystemExit(0)
if selection == "all":
    print(json.dumps(keys, separators=(",", ":")))
    raise SystemExit(0)

picked = []
tokens = [token.strip() for token in selection.split(",") if token.strip()]
for token in tokens:
    if token.isdigit():
        index = int(token) - 1
        if 0 <= index < len(keys):
            picked.append(keys[index])
    elif token in keys:
        picked.append(token)
print(json.dumps(sorted(dict.fromkeys(picked)), separators=(",", ":")))
PY
}

print_option_list() {
  local group="$1"
  python3 - "$SUMMARY_PATH" "$group" <<'PY'
import json, sys
summary = json.loads(open(sys.argv[1]).read())
group = sys.argv[2]

if group == "skills":
    items = summary["skills"]["items"]
    title = "[Setup] Skill recommendations:"
    label = lambda item: f"{item['name']} ({item['repo']})"
elif group == "cli":
    items = summary["cli"]["installable"]
    title = "[Setup] CLI tools you can install now:"
    label = lambda item: f"{item['name']} ({item['id']})"
else:
    items = summary["mcp"]["recommended"]
    title = "[Setup] MCP servers to configure:"
    label = lambda item: f"{item['name']} ({item['id']})"

print(title)
if not items:
    print("  - none")
else:
    for idx, item in enumerate(items, start=1):
        print(f"  {idx}. {label(item)}")
PY
}

record_decisions() {
  local skill_choice="$1" skill_selected="$2" cli_choice="$3" cli_selected="$4" mcp_choice="$5" mcp_selected="$6"
  python3 - "$PREFERENCES_PATH" "$MANIFEST_PATH" "$skill_choice" "$skill_selected" "$cli_choice" "$cli_selected" "$mcp_choice" "$mcp_selected" <<'PY'
import json, sys
from datetime import datetime, UTC
from pathlib import Path

prefs_path = Path(sys.argv[1])
manifest_path = Path(sys.argv[2])
skill_choice = sys.argv[3]
skill_selected = json.loads(sys.argv[4])
cli_choice = sys.argv[5]
cli_selected = json.loads(sys.argv[6])
mcp_choice = sys.argv[7]
mcp_selected = json.loads(sys.argv[8])
now = datetime.now(UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z")

payload = {
    "generatedAt": now,
    "skills": {"choice": skill_choice, "selected": skill_selected},
    "cli": {"choice": cli_choice, "selected": cli_selected},
    "mcp": {"choice": mcp_choice, "selected": mcp_selected},
}
prefs_path.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n")

manifest = {}
if manifest_path.exists():
    try:
        manifest = json.loads(manifest_path.read_text())
    except Exception:
        manifest = {}
manifest["setupSelections"] = payload
manifest_path.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n")
PY
}

apply_cli_selection() {
  local selected_json="$1"
  while IFS= read -r tool_id; do
    [ -z "$tool_id" ] && continue
    CLI_STORE_STATE_DIR="$STATE_DIR" \
    CLI_STORE_PROJECT_ROOT="$PROJECT_ROOT" \
    bash "$PLUGIN_ROOT/skills/cli-store/scripts/cli-store.sh" "$tool_id"
  done < <(python3 - "$selected_json" <<'PY'
import json, sys
for item in json.loads(sys.argv[1]):
    print(item)
PY
)
}

apply_skill_selection() {
  local selected_json="$1"
  while IFS= read -r repo; do
    [ -z "$repo" ] && continue
    SKILL_STORE_STATE_DIR="$STATE_DIR" \
    SKILL_STORE_PROJECT_ROOT="$PROJECT_ROOT" \
    bash "$PLUGIN_ROOT/skills/skill-store/scripts/skill-store.sh" --install "$repo"
  done < <(python3 - "$selected_json" <<'PY'
import json, sys
for item in json.loads(sys.argv[1]):
    print(item)
PY
)
}

apply_mcp_selection() {
  local selected_json="$1"
  while IFS= read -r mcp_id; do
    [ -z "$mcp_id" ] && continue
    MCP_STORE_STATE_DIR="$STATE_DIR" \
    MCP_STORE_PROJECT_ROOT="$PROJECT_ROOT" \
    bash "$PLUGIN_ROOT/skills/mcp-store/scripts/mcp-store.sh" --install "$mcp_id"
  done < <(python3 - "$selected_json" <<'PY'
import json, sys
for item in json.loads(sys.argv[1]):
    print(item)
PY
)
}

print_follow_up_summary() {
  local skill_choice="$1" skill_selected="$2" cli_choice="$3" cli_selected="$4" mcp_choice="$5" mcp_selected="$6"
  python3 - "$skill_choice" "$skill_selected" "$cli_choice" "$cli_selected" "$mcp_choice" "$mcp_selected" <<'PY'
import json, sys

print("[Setup] Selection summary:")
print(f"  - Skills: {sys.argv[1]} -> {', '.join(json.loads(sys.argv[2])) or 'none'}")
print(f"  - CLI: {sys.argv[3]} -> {', '.join(json.loads(sys.argv[4])) or 'none'}")
print(f"  - MCP: {sys.argv[5]} -> {', '.join(json.loads(sys.argv[6])) or 'none'}")
PY
}

bootstrap_manifest_if_missing
run_recommendation_pass
build_summary_file
print_guided_summary

if [ "$MODE" = "dry-run" ]; then
  exit 0
fi

if [ "$MODE" = "fast" ]; then
  record_decisions "later" "[]" "later" "[]" "later" "[]"
  echo "[Setup] fast mode: recommendations recorded without prompts."
  exit 0
fi

print_option_list "skills"
SKILL_CHOICE=$(prompt_or_default "SETUP_STORE_SKILLS_CHOICE" "Skills 선택 [all / 1,2 / skip / later]:")
SKILL_SELECTED=$(selection_from_recommendations "skills" "$SKILL_CHOICE")

print_option_list "cli"
CLI_CHOICE=$(prompt_or_default "SETUP_STORE_CLI_CHOICE" "CLI 선택 [all / 1,2 / skip / later]:")
CLI_SELECTED=$(selection_from_recommendations "cli" "$CLI_CHOICE")

print_option_list "mcp"
MCP_CHOICE=$(prompt_or_default "SETUP_STORE_MCP_CHOICE" "MCP 선택 [all / 1,2 / skip / later]:")
MCP_SELECTED=$(selection_from_recommendations "mcp" "$MCP_CHOICE")

record_decisions "$SKILL_CHOICE" "$SKILL_SELECTED" "$CLI_CHOICE" "$CLI_SELECTED" "$MCP_CHOICE" "$MCP_SELECTED"

if [ "$SKILL_CHOICE" != "skip" ] && [ "$SKILL_CHOICE" != "later" ] && [ "$SKILL_SELECTED" != "[]" ]; then
  echo "[Setup] Applying selected skills..."
  apply_skill_selection "$SKILL_SELECTED"
fi

if [ "$CLI_CHOICE" != "skip" ] && [ "$CLI_CHOICE" != "later" ] && [ "$CLI_SELECTED" != "[]" ]; then
  echo "[Setup] Installing selected CLI tools..."
  apply_cli_selection "$CLI_SELECTED"
fi

if [ "$MCP_CHOICE" != "skip" ] && [ "$MCP_CHOICE" != "later" ] && [ "$MCP_SELECTED" != "[]" ]; then
  echo "[Setup] Applying selected MCP servers..."
  apply_mcp_selection "$MCP_SELECTED"
fi

print_follow_up_summary "$SKILL_CHOICE" "$SKILL_SELECTED" "$CLI_CHOICE" "$CLI_SELECTED" "$MCP_CHOICE" "$MCP_SELECTED"
