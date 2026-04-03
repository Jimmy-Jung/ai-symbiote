#!/bin/bash
# ai-symbiote shared utilities
# Provides: slug generation, JSON helpers, shared state path resolution

# Generate project slug from git root basename.
# Algorithm:
#   1. git rev-parse --show-toplevel → basename → lowercase → sanitize
#   2. No git? Use basename of CODEX_PROJECT_DIR / CLAUDE_PROJECT_DIR / pwd
#   3. Collision guard: if ~/ai-symbiote/{slug}/ already exists and belongs to
#      a different project, prepend the parent directory name.
get_project_slug() {
  local dir="${CODEX_PROJECT_DIR:-${CLAUDE_PROJECT_DIR:-$(pwd)}}"
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
    # fallback: 기존 manifest는 "path" 필드를 사용할 수 있음
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

# JSON field extractor (jq with fallback to grep+sed)
json_field() {
  local json="$1" field="$2"
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$json" | jq -r ".$field // empty" 2>/dev/null
  else
    printf '%s' "$json" | grep -o "\"$field\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | head -1 | sed "s/\"$field\"[[:space:]]*:[[:space:]]*\"//" | sed 's/"$//'
  fi
}

# Nested JSON field extractor
json_nested_field() {
  local json="$1" parent="$2" field="$3"
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$json" | jq -r ".$parent.$field // empty" 2>/dev/null
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
