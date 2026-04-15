#!/usr/bin/env bash
# ai-symbiote Skill Store executor.
#
# Author: JunyoungJung
# Date: 2026-04-15

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../hooks/scripts/lib/common.sh"

CATALOG="$SCRIPT_DIR/../catalog.json"
STATE_DIR="${SKILL_STORE_STATE_DIR:-$(ensure_state_dir)}"
MANIFEST_PATH="$STATE_DIR/manifest.json"
STATE_SUBDIR="$STATE_DIR/state"
RECOMMENDATION_PATH="$STATE_SUBDIR/skill-store-recommendations.json"
PROJECT_ROOT_OVERRIDE="${SKILL_STORE_PROJECT_ROOT:-}"

mkdir -p "$STATE_DIR" "$STATE_SUBDIR"

MODE="query"
QUERY=""
LIST_CATEGORY=""
INSTALL_REPO=""

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
      INSTALL_REPO="${2:-}"
      shift 2
      ;;
    *)
      QUERY="$1"
      shift
      ;;
  esac
done

query_catalog() {
  local mode="$1" arg="$2" project_root="$3"
  python3 - "$CATALOG" "$mode" "$arg" "$project_root" <<'PY'
import json, sys
from pathlib import Path

catalog = json.loads(Path(sys.argv[1]).read_text())
mode = sys.argv[2]
arg = sys.argv[3].strip().lower()
project_root_arg = sys.argv[4].strip()

SERVICE_PATTERNS = {
    "supabase": ["@supabase/supabase-js", "supabase"],
    "neon": ["@neondatabase/", "neon"],
    "stripe": ["stripe"],
    "cloudflare": ["@cloudflare/", "wrangler"],
    "netlify": ["@netlify/", "netlify"],
    "vercel": ["@vercel/", "vercel"],
    "terraform": [".tf"],
    "sanity": ["sanity"],
    "wordpress": ["wordpress", "@wordpress/"],
    "sentry": ["@sentry/", "sentry-sdk"],
    "figma": ["figma"],
}

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
    candidate_files = [
        project_root / "package.json",
        project_root / "requirements.txt",
        project_root / "pyproject.toml",
        project_root / "Cargo.toml",
        project_root / "go.mod",
        project_root / "Package.swift",
        project_root / "wrangler.toml",
    ]
    haystacks = []
    for path in candidate_files:
        if path.is_file():
            try:
                haystacks.append(path.read_text(encoding="utf-8", errors="ignore").lower())
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
    languages = []
    frameworks = []
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
            repo = entry.get("repo")
            if repo and repo not in seen:
                seen.add(repo)
                matched.append(entry)
    for key in scan_services(detect_project_root(manifest_path)):
        for entry in catalog.get("services", {}).get(key, []):
            repo = entry.get("repo")
            if repo and repo not in seen:
                seen.add(repo)
                matched.append(entry)
    print(json.dumps(matched, separators=(",", ":")))
    raise SystemExit(0)

matches = []
for entry in flatten_entries():
    hay = " ".join([
        entry.get("repo", ""),
        entry.get("name", ""),
        entry.get("category", ""),
        entry.get("_group", ""),
    ]).lower()
    if arg and arg in hay:
        matches.append(entry)
print(json.dumps(matches, separators=(",", ":")))
PY
}

write_recommendations() {
  local matches_json="$1"
  python3 - "$RECOMMENDATION_PATH" "$matches_json" <<'PY'
import json, sys
from datetime import datetime, UTC
from pathlib import Path

path = Path(sys.argv[1])
payload = {
    "generatedAt": datetime.now(UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
    "items": json.loads(sys.argv[2]),
}
path.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n")
PY
}

lookup_repo_entry() {
  local repo="$1"
  python3 - "$CATALOG" "$repo" <<'PY'
import json, sys
from pathlib import Path

catalog = json.loads(Path(sys.argv[1]).read_text())
target = sys.argv[2].strip().lower()

for section_name in ("stacks", "services", "domains"):
    for _group, entries in catalog.get(section_name, {}).items():
        for entry in entries:
            if entry.get("repo", "").lower() == target:
                print(json.dumps(entry, separators=(",", ":")))
                raise SystemExit(0)
print("")
PY
}

record_installation() {
  local entry_json="$1" status="${2:-selected}"
  python3 - "$MANIFEST_PATH" "$STATE_SUBDIR/skill-store-installed.json" "$entry_json" "$status" <<'PY'
import json, sys
from datetime import datetime, UTC
from pathlib import Path

manifest_path = Path(sys.argv[1])
installed_path = Path(sys.argv[2])
entry = json.loads(sys.argv[3])
status = sys.argv[4]
now = datetime.now(UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z")

manifest = {}
if manifest_path.exists():
    try:
        manifest = json.loads(manifest_path.read_text())
    except Exception:
        manifest = {}

manifest.setdefault("plugins", {})
manifest["plugins"][entry["repo"]] = {
    "name": entry.get("name"),
    "category": entry.get("category"),
    "source": f"github:{entry['repo']}",
    "installed": now,
    "status": status,
}
manifest_path.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n")

installed = {"generatedAt": now, "items": []}
if installed_path.exists():
    try:
        installed = json.loads(installed_path.read_text())
    except Exception:
        installed = {"generatedAt": now, "items": []}

items = [item for item in installed.get("items", []) if item.get("repo") != entry["repo"]]
items.append({
    "repo": entry["repo"],
    "name": entry.get("name"),
    "category": entry.get("category"),
    "installed": now,
    "status": status,
})
installed["generatedAt"] = now
installed["items"] = sorted(items, key=lambda item: item["repo"])
installed_path.write_text(json.dumps(installed, indent=2, ensure_ascii=False) + "\n")
PY
}

run_auto_mode() {
  if [ ! -f "$MANIFEST_PATH" ]; then
    echo "[Skill Store] manifest.json not found. Run setup in plan mode first."
    exit 0
  fi
  local matches_json
  matches_json=$(query_catalog auto "$MANIFEST_PATH" "$PROJECT_ROOT_OVERRIDE")
  write_recommendations "$matches_json"
  python3 - "$matches_json" <<'PY'
import json, sys
items = json.loads(sys.argv[1])
if not items:
    print("[Skill Store] No automatic skill recommendations.")
    raise SystemExit(0)
print("[Skill Store] Automatic skill recommendations:")
for item in items:
    print(f"  - {item['name']} ({item['repo']})")
PY
}

run_list_mode() {
  if [ -z "$LIST_CATEGORY" ]; then
    echo "Usage: skill-store --list <stacks|services|domains>"
    exit 1
  fi
  python3 - "$CATALOG" "$LIST_CATEGORY" <<'PY'
import json, sys
catalog = json.loads(open(sys.argv[1]).read())
section = catalog.get(sys.argv[2])
if not isinstance(section, dict):
    print(f"[Skill Store] Unknown category: {sys.argv[2]}")
    raise SystemExit(1)
print(f"[Skill Store] {sys.argv[2]}:")
for key, entries in sorted(section.items()):
    names = ", ".join(entry["repo"] for entry in entries)
    print(f"  - {key}: {names}")
PY
}

run_query_mode() {
  if [ -z "$QUERY" ]; then
    echo "Usage: skill-store [--auto | --list <category> | <query>]"
    exit 1
  fi
  local matches_json
  matches_json=$(query_catalog query "$QUERY" "$PROJECT_ROOT_OVERRIDE")
  python3 - "$matches_json" "$QUERY" <<'PY'
import json, sys
items = json.loads(sys.argv[1])
query = sys.argv[2]
if not items:
    print(f"[Skill Store] No skills found for \"{query}\".")
    raise SystemExit(0)
print("[Skill Store] Matching skills:")
for idx, item in enumerate(items, start=1):
    print(f"  {idx}. {item['name']} ({item['repo']})")
PY
}

run_install_mode() {
  if [ -z "$INSTALL_REPO" ]; then
    echo "Usage: skill-store --install <owner/repo>"
    exit 1
  fi
  local entry_json
  entry_json=$(lookup_repo_entry "$INSTALL_REPO")
  if [ -z "$entry_json" ]; then
    echo "[Skill Store] Skill not found in catalog: $INSTALL_REPO"
    exit 1
  fi
  record_installation "$entry_json" "selected"
  python3 - "$entry_json" <<'PY'
import json, sys
entry = json.loads(sys.argv[1])
print(f"[Skill Store] {entry['name']} recorded for installation sync.")
print(f"[Skill Store] Source: https://github.com/{entry['repo']}")
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
    echo "Usage: skill-store [--auto | --list <category> | <query>]"
    exit 1
    ;;
esac
