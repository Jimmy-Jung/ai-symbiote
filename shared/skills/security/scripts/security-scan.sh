#!/usr/bin/env bash
# ai-symbiote security baseline scanner.
#
# Author: JunyoungJung
# Date: 2026-04-14

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../hooks/scripts/lib/common.sh"

PROJECT_ROOT=""
STATE_DIR=""
CONTEXT_FILE=""
INSTALL_HINTS="active"
EXECUTE_INSTALLS="false"
COMMAND="${1:-status}"
shift || true

while [ $# -gt 0 ]; do
  case "$1" in
    --project-root)
      PROJECT_ROOT="${2:-}"
      shift 2
      ;;
    --state-dir)
      STATE_DIR="${2:-}"
      shift 2
      ;;
    --context-file)
      CONTEXT_FILE="${2:-}"
      shift 2
      ;;
    --install-hints)
      INSTALL_HINTS="${2:-active}"
      shift 2
      ;;
    --execute)
      EXECUTE_INSTALLS="true"
      shift
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

PROJECT_ROOT="${PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
STATE_DIR="${STATE_DIR:-$(ensure_state_dir)}"
CONTEXT_FILE="${CONTEXT_FILE:-$STATE_DIR/context.md}"
BASELINE_FILE="$STATE_DIR/security-baseline.json"
CLI_CATALOG="$SCRIPT_DIR/../../cli-store/catalog.json"
STATE_SUBDIR="$STATE_DIR/state"
RECOMMENDATIONS_STATE_FILE="$STATE_SUBDIR/security-tool-recommendations.json"
CLI_STORE_SCRIPT="$SCRIPT_DIR/../../cli-store/scripts/cli-store.sh"
SECURITY_LOG_FILE="$STATE_DIR/security-log.jsonl"
SCANNER_TIMEOUT_SECONDS="${SECURITY_SCAN_TIMEOUT_SECONDS:-45}"
SCANNER_HEARTBEAT_SECONDS="${SECURITY_SCAN_HEARTBEAT_SECONDS:-5}"

mkdir -p "$STATE_DIR"
mkdir -p "$STATE_SUBDIR"

RAW_FINDINGS=$(mktemp)
SORTED_FINDINGS=$(mktemp)
TOP_FINDINGS=$(mktemp)
GITLEAKS_REPORT=$(mktemp)
SEMGREP_REPORT=$(mktemp)
TMP_JSON=$(mktemp)
RECOMMENDATIONS_JSON=$(mktemp)
GITLEAKS_CONFIG=$(mktemp)

cleanup() {
  rm -f "$RAW_FINDINGS" "$SORTED_FINDINGS" "$TOP_FINDINGS" "$GITLEAKS_REPORT" "$SEMGREP_REPORT" "$TMP_JSON" "$RECOMMENDATIONS_JSON" "$GITLEAKS_CONFIG"
}
trap cleanup EXIT

SCANNER_EXCLUDE_PATTERNS=(
  "node_modules"
  "dist"
  "build"
  ".next"
  ".turbo"
  "vendor"
  ".venv"
  "venv"
  "Pods"
  "Derived"
  "DerivedData"
  "Tuist"
  ".build"
  "*.framework"
  "*.xcframework"
)

severity_order() {
  case "$1" in
    critical) echo 0 ;;
    high) echo 1 ;;
    medium) echo 2 ;;
    info) echo 3 ;;
    *) echo 9 ;;
  esac
}

severity_penalty() {
  case "$1" in
    critical) echo 20 ;;
    high) echo 10 ;;
    medium) echo 5 ;;
    info) echo 1 ;;
    *) echo 0 ;;
  esac
}

append_finding() {
  local severity="$1" category="$2" file_path="$3" line_no="$4" source="$5" description="$6"
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$severity" "$category" "$file_path" "$line_no" "$source" "$description" >> "$RAW_FINDINGS"
}

detect_package_manager() {
  if command -v brew >/dev/null 2>&1; then
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

build_recommendations_json() {
  local gitleaks_status="$1" semgrep_status="$2" manager
  manager=$(detect_package_manager)

  if ! command -v python3 >/dev/null 2>&1; then
    printf '[]\n' > "$RECOMMENDATIONS_JSON"
    return 0
  fi

  python3 - "$CLI_CATALOG" "$manager" "$gitleaks_status" "$semgrep_status" > "$RECOMMENDATIONS_JSON" <<'PY'
import json, sys
from pathlib import Path

catalog_path = Path(sys.argv[1])
manager = sys.argv[2]
statuses = {"gitleaks": sys.argv[3], "semgrep": sys.argv[4]}

try:
    catalog = json.loads(catalog_path.read_text())
except Exception:
    print("[]")
    raise SystemExit(0)

def find_entry(tool_id: str):
    for section_name in ("services", "domains", "stacks"):
        section = catalog.get(section_name, {})
        if not isinstance(section, dict):
            continue
        for _key, entries in section.items():
            for entry in entries:
                if entry.get("id") == tool_id:
                    return entry
    return None

recommendations = []
for tool_id, status in statuses.items():
    if status != "not-installed":
        continue
    entry = find_entry(tool_id)
    if not entry:
        continue
    install_cmds = entry.get("installCmd", {})
    install_cmd = install_cmds.get(manager)
    if not install_cmd and install_cmds:
      install_cmd = next(iter(install_cmds.values()))
    recommendations.append({
        "tool": tool_id,
        "name": entry.get("name", tool_id),
        "status": status,
        "packageManager": manager,
        "installCommand": install_cmd or "",
        "description": entry.get("description", ""),
        "mcpEquivalent": entry.get("mcpEquivalent"),
        "skillHint": f"/ai-symbiote:cli-store {tool_id}",
        "rerunHint": "/security scan"
    })

print(json.dumps(recommendations, separators=(",", ":")))
PY
}

persist_recommendations_state() {
  if ! command -v python3 >/dev/null 2>&1; then
    return 0
  fi

  python3 - "$RECOMMENDATIONS_JSON" "$RECOMMENDATIONS_STATE_FILE" "$BASELINE_FILE" <<'PY'
import json, sys
from pathlib import Path

recommendations_path = Path(sys.argv[1])
state_path = Path(sys.argv[2])
baseline_path = Path(sys.argv[3])

try:
    recommendations = json.loads(recommendations_path.read_text())
except Exception:
    recommendations = []

if not recommendations:
    if state_path.exists():
        state_path.unlink()
    raise SystemExit(0)

baseline = {}
try:
    baseline = json.loads(baseline_path.read_text())
except Exception:
    pass

payload = {
    "generatedAt": baseline.get("scan_date"),
    "source": "security-scan",
    "score": baseline.get("score"),
    "recommendations": recommendations,
}
state_path.write_text(json.dumps(payload, separators=(",", ":")))
PY
}

find_repo_files() {
  find "$PROJECT_ROOT" \
    -type d \( -name ".git" \
    -o -name "node_modules" \
    -o -name "dist" \
    -o -name "build" \
    -o -name ".next" \
    -o -name ".turbo" \
    -o -name "vendor" \
    -o -name ".venv" \
    -o -name "venv" \
    -o -name "Pods" \
    -o -name "Derived" \
    -o -name "DerivedData" \
    -o -name "Tuist" \
    -o -name ".build" \
    -o -name "*.framework" \
    -o -name "*.xcframework" \) -prune \
    -o -type f -print
}

run_command_with_timeout() {
  local label="$1"
  shift

  python3 - "$SCANNER_TIMEOUT_SECONDS" "$@" <<'PY' >/dev/null 2>&1 &
import subprocess
import sys

timeout_s = int(sys.argv[1])
cmd = sys.argv[2:]

try:
    completed = subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=timeout_s, check=False)
except subprocess.TimeoutExpired:
    raise SystemExit(124)
except FileNotFoundError:
    raise SystemExit(127)

code = completed.returncode
raise SystemExit(code if 0 <= code <= 255 else 1)
PY
  local cmd_pid=$!
  local heartbeat_pid="" started_at now elapsed
  started_at=$(date +%s)

  if [ "${SCANNER_HEARTBEAT_SECONDS:-0}" -gt 0 ]; then
    (
      sleep "$SCANNER_HEARTBEAT_SECONDS"
      while kill -0 "$cmd_pid" 2>/dev/null; do
        now=$(date +%s)
        elapsed=$((now - started_at))
        echo "[Security] ${label} scanning... ${elapsed}s elapsed" >&2
        sleep "$SCANNER_HEARTBEAT_SECONDS"
      done
    ) &
    heartbeat_pid=$!
  fi

  local rc=0
  set +e
  wait "$cmd_pid"
  rc=$?
  set -e
  if [ -n "$heartbeat_pid" ]; then
    kill "$heartbeat_pid" >/dev/null 2>&1 || true
    wait "$heartbeat_pid" 2>/dev/null || true
  fi
  return "$rc"
}

build_gitleaks_config() {
  local project_config="$PROJECT_ROOT/.gitleaks.toml"
  if [ -f "$project_config" ]; then
    printf '%s\n' "$project_config"
    return 0
  fi

  python3 - "$GITLEAKS_CONFIG" <<'PY'
import json
import sys
from pathlib import Path

config_path = Path(sys.argv[1])
patterns = [
    r"(^|/)(node_modules|dist|build|\.next|\.turbo|vendor|\.venv|venv|Pods|Derived|DerivedData|Tuist|\.build)(/|$)",
    r"(^|/).*?\.(framework|xcframework)(/|$)",
]

lines = [
    'title = "ai-symbiote security scan temporary config"',
    "",
    "[extend]",
    "useDefault = true",
    "",
    "[allowlist]",
    'description = "Skip generated/build artifacts during local baseline scan"',
    "paths = [",
]
for pattern in patterns:
    lines.append(f"  '''{pattern}''',")
lines.extend(["]", ""])
config_path.write_text("\n".join(lines), encoding="utf-8")
print(config_path)
PY
}

append_semgrep_excludes() {
  local target_name="$1"
  local pattern
  for pattern in "${SCANNER_EXCLUDE_PATTERNS[@]}"; do
    eval "$target_name+=(\"--exclude\" \"\$pattern\")"
  done
}

scan_builtin_rules() {
  local env_files=""
  env_files=$(find_repo_files | grep -E '(^|/)\.env(\..*)?$' || true)

  if [ -n "$env_files" ]; then
    if [ ! -f "$PROJECT_ROOT/.gitignore" ] || ! grep -qE '(^|/)\.env(\..*)?$|^\*\.env$|^\.env$' "$PROJECT_ROOT/.gitignore" 2>/dev/null; then
      append_finding "high" "gitignore" ".gitignore" "" "builtin" ".env files exist but .gitignore does not clearly ignore them."
    fi
  fi

  while IFS= read -r env_file; do
    [ -z "$env_file" ] && continue
    if grep -qE '^[A-Z0-9_]+=.+' "$env_file" 2>/dev/null && ! grep -qiE '(changeme|placeholder|example|your_|replace_me|dummy|sample)' "$env_file" 2>/dev/null; then
      append_finding "critical" "env_secret" "${env_file#$PROJECT_ROOT/}" "" "builtin" ".env file contains real values. Keep only placeholders in tracked examples."
    fi
  done <<EOF
$env_files
EOF

  while IFS= read -r match; do
    [ -z "$match" ] && continue
    local file_path line_no
    file_path=$(printf '%s' "$match" | cut -d: -f1)
    line_no=$(printf '%s' "$match" | cut -d: -f2)
    append_finding "critical" "hardcoded_secret" "${file_path#$PROJECT_ROOT/}" "$line_no" "builtin" "Hardcoded secret-like assignment detected."
  done <<EOF
$(find_repo_files | grep -E '\.(js|jsx|ts|tsx|py|rb|go|swift|java|kt|rs|sh|bash|zsh|yaml|yml|json|toml|env|ini|cfg|conf)$|(^|/)Dockerfile$|(^|/)docker-compose.*\.ya?ml$|(^|/)\.github/workflows/.*\.ya?ml$' | xargs grep -nHi -E '(api_key|api_secret|secret_key|access_key|private_key|auth_token|client_secret|database_url|db_password)\s*[:=]\s*["'"'"']?[A-Za-z0-9_./+=-]{12,}' 2>/dev/null || true)
EOF

  while IFS= read -r match; do
    [ -z "$match" ] && continue
    local file_path line_no
    file_path=$(printf '%s' "$match" | cut -d: -f1)
    line_no=$(printf '%s' "$match" | cut -d: -f2)
    append_finding "high" "eval_exec" "${file_path#$PROJECT_ROOT/}" "$line_no" "builtin" "Dynamic eval/exec pattern detected. Review input trust boundary."
  done <<EOF
$(find_repo_files | grep -E '\.(js|jsx|ts|tsx|py|rb|sh|bash|zsh)$' | xargs grep -nH -E '\beval\s*\(|\bexec\s*\(' 2>/dev/null || true)
EOF

  while IFS= read -r match; do
    [ -z "$match" ] && continue
    local file_path line_no
    file_path=$(printf '%s' "$match" | cut -d: -f1)
    line_no=$(printf '%s' "$match" | cut -d: -f2)
    append_finding "high" "sql_concat" "${file_path#$PROJECT_ROOT/}" "$line_no" "builtin" "SQL string concatenation detected. Prefer parameterized queries."
  done <<EOF
$(find_repo_files | grep -E '\.(js|jsx|ts|tsx|py|rb|go|java|kt|swift)$' | xargs grep -nH -E '(SELECT|INSERT|UPDATE|DELETE).*(\+|%s|f"|f'"'"')' 2>/dev/null || true)
EOF

  while IFS= read -r match; do
    [ -z "$match" ] && continue
    local file_path line_no
    file_path=$(printf '%s' "$match" | cut -d: -f1)
    line_no=$(printf '%s' "$match" | cut -d: -f2)
    append_finding "medium" "xss_surface" "${file_path#$PROJECT_ROOT/}" "$line_no" "builtin" "HTML injection surface detected. Sanitize or avoid unsafe rendering."
  done <<EOF
$(find_repo_files | grep -E '\.(js|jsx|ts|tsx|vue|html)$' | xargs grep -nH -E 'dangerouslySetInnerHTML|\.innerHTML\s*=|v-html=' 2>/dev/null || true)
EOF

  while IFS= read -r match; do
    [ -z "$match" ] && continue
    local file_path line_no
    file_path=$(printf '%s' "$match" | cut -d: -f1)
    line_no=$(printf '%s' "$match" | cut -d: -f2)
    append_finding "medium" "debug_mode" "${file_path#$PROJECT_ROOT/}" "$line_no" "builtin" "Production-facing debug or verbose mode is enabled."
  done <<EOF
$(find_repo_files | grep -E '\.(env|json|yaml|yml|toml|ini|cfg|conf|js|ts|py|rb)$' | xargs grep -nH -E '^\s*(DEBUG|VERBOSE|DEV_MODE)\s*[:=]\s*(true|1|yes|on)\b' 2>/dev/null || true)
EOF

  while IFS= read -r world_writable; do
    [ -z "$world_writable" ] && continue
    append_finding "high" "permissions" "${world_writable#$PROJECT_ROOT/}" "" "builtin" "World-writable file or directory detected."
  done <<EOF
$(find "$PROJECT_ROOT" \
  -type d \( -name ".git" \
  -o -name "node_modules" \
  -o -name "dist" \
  -o -name "build" \
  -o -name ".next" \
  -o -name ".turbo" \
  -o -name "vendor" \
  -o -name ".venv" \
  -o -name "venv" \
  -o -name "Pods" \
  -o -name "Derived" \
  -o -name "DerivedData" \
  -o -name "Tuist" \
  -o -name ".build" \
  -o -name "*.framework" \
  -o -name "*.xcframework" \) -prune \
  -o \( -type f -o -type d \) -perm -0002 -print 2>/dev/null || true)
EOF

  if [ -f "$PROJECT_ROOT/Dockerfile" ] && ! grep -qE '^\s*USER\s+' "$PROJECT_ROOT/Dockerfile" 2>/dev/null; then
    append_finding "medium" "docker_user" "Dockerfile" "" "builtin" "Dockerfile has no USER directive. Container may run as root."
  fi

  while IFS= read -r match; do
    [ -z "$match" ] && continue
    local file_path line_no
    file_path=$(printf '%s' "$match" | cut -d: -f1)
    line_no=$(printf '%s' "$match" | cut -d: -f2)
    append_finding "high" "port_exposure" "${file_path#$PROJECT_ROOT/}" "$line_no" "builtin" "Sensitive service is bound to 0.0.0.0."
  done <<EOF
$(find_repo_files | grep -E '(^|/)docker-compose.*\.ya?ml$|(^|/)\.env(\..*)?$|(^|/).*\.ya?ml$|(^|/).*\.toml$' | xargs grep -nH -E '0\.0\.0\.0:(22|3306|5432|6379|27017)' 2>/dev/null || true)
EOF
}

run_gitleaks() {
  local rc config_path
  if [ -n "${SECURITY_SCAN_FORCE_GITLEAKS_STATUS:-}" ]; then
    echo "$SECURITY_SCAN_FORCE_GITLEAKS_STATUS"
    return 0
  fi
  if ! command -v gitleaks >/dev/null 2>&1; then
    echo "not-installed"
    return 0
  fi

  config_path=$(build_gitleaks_config)

  if run_command_with_timeout "gitleaks" \
    gitleaks detect --no-git --source "$PROJECT_ROOT" \
    --config "$config_path" \
    --report-format json --report-path "$GITLEAKS_REPORT"; then
    rc=0
  else
    rc=$?
  fi
  if [ "$rc" -eq 124 ]; then
    echo "timeout"
    return 0
  fi
  if [ "$rc" -eq 127 ]; then
    echo "not-installed"
    return 0
  fi
  if [ "$rc" -ne 0 ] && [ ! -s "$GITLEAKS_REPORT" ]; then
    : > "$GITLEAKS_REPORT"
    if run_command_with_timeout "gitleaks" \
      gitleaks dir "$PROJECT_ROOT" \
      --config "$config_path" \
      --report-format json --report-path "$GITLEAKS_REPORT"; then
      rc=0
    else
      rc=$?
    fi
    if [ "$rc" -eq 124 ]; then
      echo "timeout"
      return 0
    fi
    if [ "$rc" -eq 127 ]; then
      echo "not-installed"
      return 0
    fi
    if [ "$rc" -ne 0 ] && [ ! -s "$GITLEAKS_REPORT" ]; then
      echo "error"
      return 0
    fi
  fi

  if [ -s "$GITLEAKS_REPORT" ] && command -v python3 >/dev/null 2>&1; then
    python3 - "$GITLEAKS_REPORT" <<'PY' >> "$RAW_FINDINGS"
import json, sys
path = sys.argv[1]
try:
    data = json.load(open(path))
except Exception:
    raise SystemExit(0)
if isinstance(data, dict):
    data = data.get("findings") or data.get("results") or []
if not isinstance(data, list):
    data = []
for item in data[:50]:
    file_path = item.get("File") or item.get("file") or ""
    line_no = item.get("StartLine") or item.get("start", {}).get("line") or item.get("line") or ""
    rule = item.get("RuleID") or item.get("rule_id") or "Potential secret detected by gitleaks"
    desc = item.get("Description") or item.get("description") or rule
    fields = ["critical", "gitleaks", str(file_path), str(line_no), "gitleaks", str(desc)]
    print("\t".join(fields))
PY
  fi
  echo "used"
}

run_semgrep() {
  local rc
  local semgrep_cmd=(semgrep scan --config auto --json --output "$SEMGREP_REPORT")
  if [ -n "${SECURITY_SCAN_FORCE_SEMGREP_STATUS:-}" ]; then
    echo "$SECURITY_SCAN_FORCE_SEMGREP_STATUS"
    return 0
  fi
  if ! command -v semgrep >/dev/null 2>&1; then
    echo "not-installed"
    return 0
  fi

  append_semgrep_excludes semgrep_cmd
  semgrep_cmd+=("$PROJECT_ROOT")

  if run_command_with_timeout "semgrep" "${semgrep_cmd[@]}"; then
    rc=0
  else
    rc=$?
  fi
  if [ "$rc" -eq 124 ]; then
    echo "timeout"
    return 0
  fi
  if [ "$rc" -ne 0 ] && [ ! -s "$SEMGREP_REPORT" ]; then
    : > "$SEMGREP_REPORT"
    semgrep_cmd=(semgrep --config auto --json --output "$SEMGREP_REPORT")
    append_semgrep_excludes semgrep_cmd
    semgrep_cmd+=("$PROJECT_ROOT")
    if run_command_with_timeout "semgrep" "${semgrep_cmd[@]}"; then
      rc=0
    else
      rc=$?
    fi
    if [ "$rc" -eq 124 ]; then
      echo "timeout"
      return 0
    fi
    if [ "$rc" -ne 0 ] && [ ! -s "$SEMGREP_REPORT" ]; then
      echo "error"
      return 0
    fi
  fi

  if [ -s "$SEMGREP_REPORT" ] && command -v python3 >/dev/null 2>&1; then
    python3 - "$SEMGREP_REPORT" <<'PY' >> "$RAW_FINDINGS"
import json, sys
severity_map = {
    "ERROR": "high",
    "WARNING": "medium",
    "INFO": "info",
    "CRITICAL": "critical",
}
path = sys.argv[1]
try:
    data = json.load(open(path))
except Exception:
    raise SystemExit(0)
results = data.get("results", []) if isinstance(data, dict) else []
for item in results[:50]:
    extra = item.get("extra", {})
    sev = severity_map.get(str(extra.get("severity", "WARNING")).upper(), "medium")
    file_path = item.get("path", "")
    line_no = item.get("start", {}).get("line", "")
    check_id = item.get("check_id", "semgrep")
    desc = extra.get("message") or check_id
    fields = [sev, "semgrep", str(file_path), str(line_no), "semgrep", str(desc)]
    print("\t".join(fields))
PY
  fi
  echo "used"
}

dedupe_and_sort_findings() {
  awk -F '\t' '!seen[$0]++' "$RAW_FINDINGS" | while IFS=$'\t' read -r severity category file_path line_no source description; do
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$(severity_order "$severity")" "$severity" "$category" "$file_path" "$line_no" "$source" "$description"
  done | sort -t $'\t' -k1,1n -k4,4 -k5,5n > "$SORTED_FINDINGS"
  cut -f2- "$SORTED_FINDINGS" > "$RAW_FINDINGS.cleaned"
  mv "$RAW_FINDINGS.cleaned" "$SORTED_FINDINGS"
  head -3 "$SORTED_FINDINGS" > "$TOP_FINDINGS" || true
}

build_baseline_json() {
  local builtin_status="$1" gitleaks_status="$2" semgrep_status="$3"
  local critical_count high_count medium_count info_count total_count score
  critical_count=$(awk -F '\t' '$1=="critical"{c++} END{print c+0}' "$SORTED_FINDINGS")
  high_count=$(awk -F '\t' '$1=="high"{c++} END{print c+0}' "$SORTED_FINDINGS")
  medium_count=$(awk -F '\t' '$1=="medium"{c++} END{print c+0}' "$SORTED_FINDINGS")
  info_count=$(awk -F '\t' '$1=="info"{c++} END{print c+0}' "$SORTED_FINDINGS")
  total_count=$((critical_count + high_count + medium_count + info_count))
  score=100

  while IFS=$'\t' read -r severity _category _file _line _source _description; do
    [ -z "$severity" ] && continue
    score=$((score - $(severity_penalty "$severity")))
  done < "$SORTED_FINDINGS"

  if [ "$score" -lt 0 ]; then
    score=0
  fi

  build_recommendations_json "$gitleaks_status" "$semgrep_status"

  {
    printf '{\n'
    printf '  "scan_date": "%s",\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '  "project_root": "%s",\n' "$(json_escape "$PROJECT_ROOT")"
    printf '  "score": %d,\n' "$score"
    printf '  "summary": {"critical": %d, "high": %d, "medium": %d, "info": %d, "total": %d},\n' \
      "$critical_count" "$high_count" "$medium_count" "$info_count" "$total_count"
    printf '  "tools": {"builtin": "%s", "gitleaks": "%s", "semgrep": "%s"},\n' \
      "$builtin_status" "$gitleaks_status" "$semgrep_status"
    printf '  "recommendations": %s,\n' "$(cat "$RECOMMENDATIONS_JSON")"

    printf '  "top_findings": [\n'
    local first=1
    while IFS=$'\t' read -r severity category file_path line_no source description; do
      [ -z "$severity" ] && continue
      [ "$first" -eq 0 ] && printf ',\n'
      printf '    {"severity":"%s","category":"%s","file":"%s","line":"%s","source":"%s","description":"%s"}' \
        "$(json_escape "$severity")" "$(json_escape "$category")" "$(json_escape "$file_path")" \
        "$(json_escape "$line_no")" "$(json_escape "$source")" "$(json_escape "$description")"
      first=0
    done < "$TOP_FINDINGS"
    printf '\n  ],\n'

    printf '  "findings": [\n'
    first=1
    while IFS=$'\t' read -r severity category file_path line_no source description; do
      [ -z "$severity" ] && continue
      [ "$first" -eq 0 ] && printf ',\n'
      printf '    {"severity":"%s","category":"%s","file":"%s","line":"%s","source":"%s","description":"%s"}' \
        "$(json_escape "$severity")" "$(json_escape "$category")" "$(json_escape "$file_path")" \
        "$(json_escape "$line_no")" "$(json_escape "$source")" "$(json_escape "$description")"
      first=0
    done < "$SORTED_FINDINGS"
    printf '\n  ]\n'
    printf '}\n'
  } > "$TMP_JSON"

  mv "$TMP_JSON" "$BASELINE_FILE"
  persist_recommendations_state
}

update_context_block() {
  [ -f "$CONTEXT_FILE" ] || return 0
  local score critical_count high_count medium_count info_count last_scan
  score=$(json_field "$(cat "$BASELINE_FILE")" "score")
  last_scan=$(json_field "$(cat "$BASELINE_FILE")" "scan_date")
  local blocked_count warned_count latest_event recent_activity_lines
  if command -v python3 >/dev/null 2>&1; then
    read -r critical_count high_count medium_count info_count <<EOF
$(python3 - "$BASELINE_FILE" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
summary = data.get("summary", {})
print(summary.get("critical", 0), summary.get("high", 0), summary.get("medium", 0), summary.get("info", 0))
PY
)
EOF
    local telemetry_output
    telemetry_output=$(python3 - "$SECURITY_LOG_FILE" <<'PY'
import json, sys
from pathlib import Path

log_path = Path(sys.argv[1])
blocked = 0
warned = 0
latest = "none"
recent = []

if log_path.exists():
    for raw in log_path.read_text().splitlines():
        raw = raw.strip()
        if not raw:
            continue
        try:
            item = json.loads(raw)
        except Exception:
            continue
        if item.get("type") != "security":
            continue
        action = item.get("action")
        if action == "blocked":
            blocked += 1
        elif action == "warned":
            warned += 1
        ts = item.get("ts") or "unknown"
        latest = ts
        category = item.get("category") or "unknown"
        detail = item.get("file") or item.get("command") or item.get("rule_id") or "n/a"
        recent.append(f"- {ts} | {action or 'unknown'} | {category} | {detail}")

recent = recent[-3:]
print(blocked)
print(warned)
print(latest)
for line in recent:
    print(line)
PY
)
    blocked_count=$(printf '%s\n' "$telemetry_output" | sed -n '1p')
    warned_count=$(printf '%s\n' "$telemetry_output" | sed -n '2p')
    latest_event=$(printf '%s\n' "$telemetry_output" | sed -n '3p')
    recent_activity_lines=$(printf '%s\n' "$telemetry_output" | sed -n '4,$p')
  else
    critical_count=0; high_count=0; medium_count=0; info_count=0
    blocked_count=0; warned_count=0; latest_event=none; recent_activity_lines=""
  fi

  local block_file
  block_file=$(mktemp)
  {
    printf '<!-- AI-SYMBIOTE:START security-baseline -->\n'
    printf '## Security Baseline\n'
    printf -- '- Score: %s/100\n' "${score:-0}"
    printf -- '- Critical: %s | High: %s | Medium: %s | Info: %s\n' "$critical_count" "$high_count" "$medium_count" "$info_count"
    printf -- '- Last scan: %s\n' "${last_scan:-unknown}"
    printf -- '- Recent security activity: blocked=%s | warned=%s | latest=%s\n' "${blocked_count:-0}" "${warned_count:-0}" "${latest_event:-none}"
    if [ -n "$recent_activity_lines" ]; then
      printf '%s\n' "$recent_activity_lines"
    fi
    printf -- '- Details: run `/security scan` or `/security status`\n'
    printf '<!-- AI-SYMBIOTE:END security-baseline -->\n'
  } > "$block_file"

  if command -v python3 >/dev/null 2>&1; then
    python3 - "$CONTEXT_FILE" "$block_file" <<'PY'
from pathlib import Path
import sys

context_path = Path(sys.argv[1])
block_path = Path(sys.argv[2])
start = "<!-- AI-SYMBIOTE:START security-baseline -->"
end = "<!-- AI-SYMBIOTE:END security-baseline -->"
context = context_path.read_text()
block = block_path.read_text().rstrip() + "\n"

if start in context and end in context:
    prefix = context.split(start, 1)[0].rstrip()
    suffix = context.split(end, 1)[1].lstrip("\n")
    rebuilt = prefix + ("\n\n" if prefix else "") + block + ("\n" if suffix else "") + suffix
else:
    rebuilt = context.rstrip() + "\n\n" + block

context_path.write_text(rebuilt.rstrip() + "\n")
PY
  fi
  rm -f "$block_file"
}

print_human_summary() {
  local mode="$1" gitleaks_status="$2" semgrep_status="$3"
  if ! command -v python3 >/dev/null 2>&1; then
    echo "[Security] python3 is required to render baseline status." >&2
    return 1
  fi

  python3 - "$BASELINE_FILE" "$SECURITY_LOG_FILE" "$mode" "$INSTALL_HINTS" "$gitleaks_status" "$semgrep_status" <<'PY'
import json, sys
from pathlib import Path

path, security_log_path, mode, install_hints, gitleaks_status, semgrep_status = sys.argv[1:7]
data = json.load(open(path))
summary = data.get("summary", {})

blocked = 0
warned = 0
latest_event = "none"
recent_activity = []

log_path = Path(security_log_path)
if log_path.exists():
    for raw in log_path.read_text().splitlines():
        raw = raw.strip()
        if not raw:
            continue
        try:
            item = json.loads(raw)
        except Exception:
            continue
        if item.get("type") != "security":
            continue
        action = item.get("action")
        if action == "blocked":
            blocked += 1
        elif action == "warned":
            warned += 1
        ts = item.get("ts") or "unknown"
        latest_event = ts
        category = item.get("category") or "unknown"
        detail = item.get("file") or item.get("command") or item.get("rule_id") or "n/a"
        recent_activity.append((ts, action or "unknown", category, detail))

recent_activity = recent_activity[-3:]

print("[Security] " + ("Baseline scan complete" if mode == "scan" else "Current baseline"))
print(f"Score: {data.get('score', 0)}/100")
print(
    "Critical: {critical} | High: {high} | Medium: {medium} | Info: {info}".format(
        critical=summary.get("critical", 0),
        high=summary.get("high", 0),
        medium=summary.get("medium", 0),
        info=summary.get("info", 0),
    )
)
print(f"Last scan: {data.get('scan_date', 'unknown')}")
print(f"Recent activity: blocked={blocked} | warned={warned} | latest={latest_event}")
if recent_activity:
    print("Recent security events:")
    for ts, action, category, detail in recent_activity:
        print(f"  - {ts} | {action} | {category} | {detail}")
print("Top risks:")
top = data.get("top_findings", [])
if not top:
    print("  - No findings. Baseline is clean.")
else:
    for item in top:
        file_part = item.get("file") or "(repo)"
        line_part = f":{item['line']}" if item.get("line") else ""
        print(f"  - [{item.get('severity','info').upper()}] {file_part}{line_part} — {item.get('description','')}")

tools = data.get("tools", {})
print(
    "Tools: builtin={builtin}, gitleaks={gitleaks}, semgrep={semgrep}".format(
        builtin=tools.get("builtin", "unknown"),
        gitleaks=tools.get("gitleaks", "unknown"),
        semgrep=tools.get("semgrep", "unknown"),
    )
)
if install_hints != "off" and mode == "scan":
    recommendations = data.get("recommendations", [])
    if recommendations:
        print("Recommended next tools:")
        for item in recommendations:
            install_cmd = item.get("installCommand") or "see cli-store"
            skill_hint = item.get("skillHint") or ""
            desc = item.get("description") or ""
            print(f"  - {item.get('tool')}: {desc}")
            print(f"    install: {install_cmd}")
            print(f"    or run: {skill_hint}")
elif mode == "status":
    recommendations = data.get("recommendations", [])
    if recommendations:
        print("Pending tool recommendations:")
        for item in recommendations:
            print(f"  - {item.get('tool')} -> {item.get('skillHint')}")
PY
}

run_scan() {
  : > "$RAW_FINDINGS"
  scan_builtin_rules
  local builtin_status="used"
  local gitleaks_status semgrep_status
  gitleaks_status=$(run_gitleaks)
  semgrep_status=$(run_semgrep)
  dedupe_and_sort_findings
  build_baseline_json "$builtin_status" "$gitleaks_status" "$semgrep_status"
  update_context_block
  print_human_summary "scan" "$gitleaks_status" "$semgrep_status"
}

run_status() {
  if [ ! -f "$BASELINE_FILE" ]; then
    echo "[Security] No baseline found. Run /security scan first."
    exit 0
  fi
  update_context_block
  print_human_summary "status" "$(json_nested_field "$(cat "$BASELINE_FILE")" "tools" "gitleaks")" "$(json_nested_field "$(cat "$BASELINE_FILE")" "tools" "semgrep")"
}

run_install_tools() {
  if [ ! -f "$RECOMMENDATIONS_STATE_FILE" ]; then
    echo "[Security] No pending tool recommendations. Run /security scan first."
    exit 0
  fi
  if [ ! -x "$CLI_STORE_SCRIPT" ]; then
    echo "[Security] cli-store executor not found at $CLI_STORE_SCRIPT"
    exit 1
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    echo "[Security] python3 is required to read pending tool recommendations."
    exit 1
  fi

  local tool_ids
  tool_ids=$(python3 - "$RECOMMENDATIONS_STATE_FILE" <<'PY'
import json, sys
from pathlib import Path
data = json.loads(Path(sys.argv[1]).read_text())
print(" ".join(item.get("tool", "") for item in data.get("recommendations", []) if item.get("tool")))
PY
)

  if [ -z "$tool_ids" ]; then
    echo "[Security] No installable tools in pending recommendations."
    exit 0
  fi

  echo "[Security] Installing recommended tools via cli-store:"
  for tool_id in $tool_ids; do
    echo "  - $tool_id"
    if [ "$EXECUTE_INSTALLS" = "true" ]; then
      CLI_STORE_STATE_DIR="$STATE_DIR" bash "$CLI_STORE_SCRIPT" "$tool_id"
    else
      CLI_STORE_STATE_DIR="$STATE_DIR" bash "$CLI_STORE_SCRIPT" --dry-run "$tool_id"
    fi
  done
  if [ "$EXECUTE_INSTALLS" = "true" ]; then
    echo "[Security] Installation handoff complete."
  else
    echo "[Security] Dry-run complete. Run /security install-tools --execute when you are ready to perform real installs."
  fi
}

case "$COMMAND" in
  scan)
    run_scan
    ;;
  status)
    run_status
    ;;
  install-tools)
    run_install_tools
    ;;
  *)
    echo "Usage: security-scan.sh [scan|status|install-tools] [--project-root PATH] [--state-dir PATH] [--context-file PATH] [--install-hints active|passive|off] [--execute]" >&2
    exit 1
    ;;
esac
