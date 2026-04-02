#!/bin/bash
# ai-symbiote shared utilities
# Provides: slug generation, JSON helpers, shared state path resolution

# Generate project slug from Codex/Claude project dir or cwd
get_project_slug() {
  local dir="${CODEX_PROJECT_DIR:-${CLAUDE_PROJECT_DIR:-$(pwd)}}"
  printf '%s' "$dir" | tr '[:upper:]' '[:lower:]' | sed 's|^/||' | tr '/' '_' | tr -cd 'a-z0-9_-' | cut -c1-64
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
