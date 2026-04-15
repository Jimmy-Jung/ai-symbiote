#!/bin/bash
# ai-symbiote PostToolUse hook: Track skill/command usage.
# Monitors Read tool calls to detect skill/command file reads,
# and Skill tool calls to directly capture skill invocations.
#
# Principle: Silence on success — never outputs to stdout (writes to files only).
#
# Also supports CLI mode: bash usage-tracker.sh <category> <name>
# Categories: skills | commands

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

PLUGIN_ROOT="${CURSOR_PLUGIN_ROOT:-${CODEX_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}}}"

increment_counter() {
  local category="$1" name="$2"
  local state_dir
  state_dir=$(get_state_dir)
  local data_dir="$state_dir/usage-data/$category"
  local data_file="$data_dir/$name"
  local since_file="$state_dir/usage-data/.tracked-since"
  local now
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  mkdir -p "$data_dir" 2>/dev/null

  if [ ! -f "$since_file" ]; then
    printf '%s\n' "$now" > "$since_file"
  fi

  local current=0
  if [ -f "$data_file" ]; then
    current=$(cut -d'|' -f1 "$data_file" 2>/dev/null)
    case "$current" in
      ''|*[!0-9]*) current=0 ;;
    esac
  fi

  local new_count=$((current + 1))
  local temp_file="${data_file}.tmp"
  printf '%d|%s\n' "$new_count" "$now" > "$temp_file" 2>/dev/null && mv "$temp_file" "$data_file" 2>/dev/null
}

# CLI mode
if [ $# -ge 2 ]; then
  CATEGORY="$1"
  NAME="$2"

  case "$CATEGORY" in
    skills|commands) ;;
    *)
      echo "error: invalid category '$CATEGORY' (must be skills|commands)" >&2
      exit 1
      ;;
  esac

  NAME=$(printf '%s' "$NAME" | tr -cd 'a-zA-Z0-9_-')
  if [ -z "$NAME" ]; then
    echo "error: invalid name" >&2
    exit 1
  fi

  if [ "$CATEGORY" = "commands" ] && [ "$NAME" = "stats" ]; then
    exit 0
  fi

  increment_counter "$CATEGORY" "$NAME"
  exit 0
fi

# Hook mode: PostToolUse(Read|Skill)
INPUT=$(cat)

# --- Skill tool detection ---
# Skill tool provides: tool_input.skill (e.g. "ai-symbiote:setup", "commit")
SKILL_NAME=$(json_nested_field "$INPUT" "tool_input" "skill")
if [ -z "$SKILL_NAME" ]; then
  SKILL_NAME=$(json_field "$INPUT" "skill")
fi

if [ -n "$SKILL_NAME" ]; then
  # Strip plugin prefix if present (e.g. "ai-symbiote:setup" -> "setup")
  NAME="${SKILL_NAME##*:}"
  NAME=$(printf '%s' "$NAME" | tr -cd 'a-zA-Z0-9_-')
  if [ -n "$NAME" ] && [ "$NAME" != "stats" ]; then
    increment_counter "skills" "$NAME"
  fi
  exit 0
fi

# --- Read tool detection (legacy: SKILL.md file reads) ---
FILE_PATH=$(json_nested_field "$INPUT" "tool_input" "file_path")
if [ -z "$FILE_PATH" ]; then
  FILE_PATH=$(json_field "$INPUT" "file_path")
fi
if [ -z "$FILE_PATH" ]; then
  FILE_PATH=$(json_nested_field "$INPUT" "tool_input" "path")
fi

if [ -z "$FILE_PATH" ]; then
  exit 0
fi

CATEGORY=""
NAME=""

case "$FILE_PATH" in
  *"$PLUGIN_ROOT"/skills/*/SKILL.md)
    CATEGORY="skills"
    NAME=$(echo "$FILE_PATH" | sed "s|.*$PLUGIN_ROOT/skills/\([^/]*\)/SKILL\.md|\1|")
    ;;
  */ai-symbiote/*/skills/*/SKILL.md|*/symbiote/*/skills/*/SKILL.md|*/codex_symbiote/*/skills/*/SKILL.md|*/claude_symbiote/*/skills/*/SKILL.md)
    CATEGORY="skills"
    NAME=$(echo "$FILE_PATH" | sed 's|.*/skills/\([^/]*\)/SKILL\.md|\1|')
    ;;
esac

if [ -z "$NAME" ] || [ -z "$CATEGORY" ]; then
  exit 0
fi

if [ "$CATEGORY" = "commands" ] && [ "$NAME" = "stats" ]; then
  exit 0
fi

increment_counter "$CATEGORY" "$NAME"

exit 0
