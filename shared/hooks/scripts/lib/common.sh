#!/bin/bash
# ai-symbiote shared utilities
# Provides: slug generation, JSON helpers, shared state path resolution

# Generate project slug from git root basename.
# Algorithm:
#   1. git rev-parse --show-toplevel → basename → lowercase → sanitize
#   2. No git? Use basename of CURSOR_PROJECT_DIR / CODEX_PROJECT_DIR / CLAUDE_PROJECT_DIR / pwd
#   3. Collision guard: if ~/ai-symbiote/{slug}/ already exists and belongs to
#      a different project, prepend the parent directory name.
get_project_slug() {
  local dir="${CURSOR_PROJECT_DIR:-${CODEX_PROJECT_DIR:-${CLAUDE_PROJECT_DIR:-$(pwd)}}}"
  local git_root
  git_root=$(cd "$dir" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null) || git_root=""

  local base_dir="${git_root:-$dir}"
  local name parent slug full_slug
  name=$(basename "$base_dir")
  parent=$(basename "$(dirname "$base_dir")")
  slug=$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9_-' | cut -c1-64)
  full_slug=$(printf '%s_%s' "$parent" "$name" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9_-' | cut -c1-64)

  # Empty basename guard
  if [ -z "$slug" ] || [ "$slug" = "-" ]; then
    slug="$full_slug"
  fi

  # Collision detection: if slug dir exists but was created for a different project
  local state_root
  state_root=$(get_state_root)
  local slug_dir="$state_root/$slug"
  if [ -d "$slug_dir" ] && [ -f "$slug_dir/manifest.json" ]; then
    local recorded_path manifest_json
    manifest_json=$(cat "$slug_dir/manifest.json")
    recorded_path=$(json_field "$manifest_json" "projectPath")
    # fallback: legacy manifests may use "path" field
    [ -z "$recorded_path" ] && recorded_path=$(json_field "$manifest_json" "path")
    if [ -n "$recorded_path" ] && [ "$recorded_path" != "$base_dir" ]; then
      slug="$full_slug"
    fi
  fi

  printf '%s' "$slug"
}

# Get shared state root path: $SYMBIOTE_HOME or ~/ai-symbiote
get_state_root() {
  local root="${SYMBIOTE_HOME:-$HOME/ai-symbiote}"
  printf '%s' "${root%/}"
}

# Get state directory path: prefer ~/ai-symbiote/{slug}/ and fall back to legacy dirs
get_state_dir() {
  if [ -n "${HARNESS_TEST_STATE_DIR:-}" ]; then
    printf '%s' "$HARNESS_TEST_STATE_DIR"
    return 0
  fi
  local slug
  local shared_root
  local shared_dir
  local legacy_shared_dir
  local legacy_codex_dir
  local legacy_claude_dir
  local fallback_dir=""
  slug=$(get_project_slug)
  shared_root=$(get_state_root)
  shared_dir="$shared_root/$slug"
  legacy_shared_dir="$HOME/symbiote/$slug"
  legacy_codex_dir="$HOME/codex_symbiote/$slug"
  legacy_claude_dir="$HOME/claude_symbiote/$slug"

  if [ -d "$shared_dir" ]; then
    printf '%s' "$shared_dir"
  else
    for candidate in "$legacy_shared_dir" "$legacy_codex_dir" "$legacy_claude_dir"; do
      if [ -d "$candidate" ]; then
        if [ -z "$fallback_dir" ] || [ "$candidate" -nt "$fallback_dir" ]; then
          fallback_dir="$candidate"
        fi
      fi
    done

    if [ -n "$fallback_dir" ]; then
      printf '%s' "$fallback_dir"
    else
      printf '%s' "$shared_dir"
    fi
  fi
}

# Ensure state directory exists
ensure_state_dir() {
  local state_dir
  state_dir=$(get_state_dir)
  mkdir -p "$state_dir" 2>/dev/null
  printf '%s' "$state_dir"
}

# JSON field extractor (jq with fallback to python3, then grep+sed)
json_field() {
  local json="$1" field="$2"
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$json" | jq -r ".$field // empty" 2>/dev/null
  elif command -v python3 >/dev/null 2>&1; then
    printf '%s' "$json" | python3 -c '
import json, sys

field = sys.argv[1]
try:
    data = json.load(sys.stdin)
except Exception:
    raise SystemExit(0)

value = data.get(field, "")
if value in ("", None):
    raise SystemExit(0)
if isinstance(value, bool):
    print("true" if value else "false")
elif isinstance(value, (int, float)):
    print(value)
elif isinstance(value, str):
    print(value)
else:
    print(json.dumps(value, separators=(",", ":")))
' "$field" 2>/dev/null
  else
    printf '%s' "$json" | grep -o "\"$field\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | head -1 | sed "s/\"$field\"[[:space:]]*:[[:space:]]*\"//" | sed 's/"$//'
  fi
}

# Nested JSON field extractor
json_nested_field() {
  local json="$1" parent="$2" field="$3"
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$json" | jq -r ".$parent.$field // empty" 2>/dev/null
  elif command -v python3 >/dev/null 2>&1; then
    printf '%s' "$json" | python3 -c '
import json, sys

parent = sys.argv[1]
field = sys.argv[2]
try:
    data = json.load(sys.stdin)
except Exception:
    raise SystemExit(0)

parent_val = data.get(parent, {})
if not isinstance(parent_val, dict):
    raise SystemExit(0)

value = parent_val.get(field, "")
if value in ("", None):
    raise SystemExit(0)
if isinstance(value, bool):
    print("true" if value else "false")
elif isinstance(value, (int, float)):
    print(value)
elif isinstance(value, str):
    print(value)
else:
    print(json.dumps(value, separators=(",", ":")))
' "$parent" "$field" 2>/dev/null
  else
    local parent_val
    parent_val=$(printf '%s' "$json" | grep -o "\"$parent\"[[:space:]]*:[[:space:]]*{[^}]*}" | head -1)
    if [ -n "$parent_val" ]; then
      printf '%s' "$parent_val" | grep -o "\"$field\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | head -1 | sed "s/\"$field\"[[:space:]]*:[[:space:]]*\"//" | sed 's/"$//'
    fi
  fi
}

# JSON escape helper
json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/	/\\t/g' | tr '\n' ' '
}

hook_uses_cursor_protocol() {
  [ -n "${CURSOR_PLUGIN_ROOT:-}" ]
}

emit_hook_continue() {
  if hook_uses_cursor_protocol; then
    printf '{"continue":true,"permission":"allow"}\n'
  else
    printf '{"continue":true}\n'
  fi
}

emit_hook_context() {
  local message="$1"
  local escaped
  escaped=$(json_escape "$message")
  if hook_uses_cursor_protocol; then
    printf '{"continue":true,"permission":"allow","agent_message":"%s","additional_context":"%s"}\n' "$escaped" "$escaped"
  else
    printf '{"continue":true,"systemMessage":"%s"}\n' "$escaped"
  fi
}

emit_hook_notice() {
  local message="$1"
  local escaped
  escaped=$(json_escape "$message")
  if hook_uses_cursor_protocol; then
    printf '{"continue":true,"permission":"allow","user_message":"%s","agent_message":"%s","additional_context":"%s"}\n' "$escaped" "$escaped" "$escaped"
  else
    printf '{"continue":true,"systemMessage":"%s"}\n' "$escaped"
  fi
}

emit_hook_block() {
  local message="$1"
  local escaped
  escaped=$(json_escape "$message")
  if hook_uses_cursor_protocol; then
    printf '{"continue":false,"permission":"deny","user_message":"%s","agent_message":"%s"}\n' "$escaped" "$escaped"
  else
    printf '{"continue":false,"permissionDecision":"deny","systemMessage":"%s"}\n' "$escaped"
  fi
}

# Session-scoped temp file helper: sanitizes session ID and rejects symlinks.
# Usage: safe_session_file "symbiote-compact" → returns sanitized path in $TMPDIR
safe_session_file() {
  local prefix="${1:-symbiote}"
  local session_id="${CLAUDE_SESSION_ID:-${CURSOR_SESSION_ID:-${CODEX_SESSION_ID:-default}}}"
  # Sanitize: keep only alphanumeric, dot, dash, underscore
  session_id=$(printf '%s' "$session_id" | tr -cd 'A-Za-z0-9._-')
  [ -z "$session_id" ] && session_id="default"
  local filepath="${TMPDIR:-/tmp}/${prefix}-${session_id}"
  # Reject symlinks
  if [ -L "$filepath" ]; then
    rm -f "$filepath" 2>/dev/null
  fi
  printf '%s' "$filepath"
}

# ISO-8601 UTC cutoff timestamp helper for recent-event filtering.
recent_cutoff_ts() {
  local days="${1:-7}"
  date -u -v-"$days"d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || \
    date -u -d "$days days ago" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || \
    echo "0000-00-00T00:00:00Z"
}

# Filter JSONL entries whose "ts" field is within the last N days.
# ISO-8601 UTC timestamps compare lexicographically, so string compare is enough.
filter_recent_jsonl() {
  local file="$1" days="${2:-7}"
  [ -f "$file" ] || return 0
  local cutoff
  cutoff=$(recent_cutoff_ts "$days")
  awk -v cutoff="$cutoff" '
    {
      if (match($0, /"ts":"[^"]+"/)) {
        ts = substr($0, RSTART + 6, RLENGTH - 7)
        if (ts >= cutoff) print
      }
    }
  ' "$file" 2>/dev/null
}
