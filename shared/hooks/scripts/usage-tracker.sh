#!/bin/bash
# ai-symbiote usage tracker hook: Track skill/command usage.
# Monitors Claude UserPromptSubmit command-message events, Read tool calls,
# and Skill tool calls to capture skill invocations across platforms.
#
# Principle: Silence on success — never outputs to stdout (writes to files only).
#
# Also supports CLI mode: bash usage-tracker.sh <category> <name>
# Categories: skills | commands

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

PLUGIN_ROOT="${CURSOR_PLUGIN_ROOT:-${CODEX_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}}}"

sanitize_name() {
  printf '%s' "$1" | tr -cd 'a-zA-Z0-9_-'
}

first_line_match() {
  local pattern="$1" input="$2"
  printf '%s' "$input" | sed -n "s:${pattern}:\\1:p" | head -1
}

normalize_command_token() {
  local raw="$1"
  raw=$(printf '%s' "$raw" | tr '\n' ' ' | sed 's/^[[:space:]]*//; s/[[:space:]].*$//')
  raw=${raw#/}
  printf '%s' "$raw"
}

recent_skill_marker_file() {
  local state_dir
  state_dir=$(get_state_dir)
  mkdir -p "$state_dir/state" 2>/dev/null
  printf '%s' "$state_dir/state/.usage-tracker-recent-skill"
}

remember_recent_skill() {
  local name="$1"
  local marker
  local now_epoch
  marker=$(recent_skill_marker_file)
  now_epoch=$(date +%s 2>/dev/null || echo 0)
  printf '%s|%s\n' "$name" "$now_epoch" > "$marker" 2>/dev/null || true
}

recent_skill_matches() {
  local name="$1" window="${2:-15}"
  local marker
  marker=$(recent_skill_marker_file)
  [ -f "$marker" ] || return 1

  local marker_name marker_ts now_epoch
  marker_name=$(cut -d'|' -f1 "$marker" 2>/dev/null)
  marker_ts=$(cut -d'|' -f2 "$marker" 2>/dev/null)
  [ "$marker_name" = "$name" ] || return 1

  case "$marker_ts" in
    ''|*[!0-9]*) return 1 ;;
  esac

  now_epoch=$(date +%s 2>/dev/null || echo 0)
  case "$now_epoch" in
    ''|*[!0-9]*) return 1 ;;
  esac

  [ $((now_epoch - marker_ts)) -le "$window" ]
}

track_skill_usage() {
  local name="$1" source="${2:-generic}"
  [ -n "$name" ] || return 0
  [ "$name" = "stats" ] && return 0

  case "$source" in
    read)
      if recent_skill_matches "$name" 15; then
        return 0
      fi
      ;;
  esac

  increment_counter "skills" "$name"
  remember_recent_skill "$name"
}

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

  NAME=$(sanitize_name "$NAME")
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

# Hook mode: UserPromptSubmit or PostToolUse(Read|Skill)
INPUT=$(read_stdin_safe)

# --- Claude slash-command detection ---
# UserPromptSubmit provides prompt with:
# <command-message>ai-symbiote:setup</command-message>
PROMPT=$(json_field "$INPUT" "prompt")
if [ -n "$PROMPT" ]; then
  COMMAND_MESSAGE=$(first_line_match '.*<command-message>\([^<]*\)</command-message>.*' "$PROMPT")
  if [ -n "$COMMAND_MESSAGE" ]; then
    COMMAND_MESSAGE=$(normalize_command_token "$COMMAND_MESSAGE")
  fi

  if [ -z "$COMMAND_MESSAGE" ]; then
    COMMAND_MESSAGE=$(first_line_match '.*<command-name>\([^<]*\)</command-name>.*' "$PROMPT")
    [ -n "$COMMAND_MESSAGE" ] && COMMAND_MESSAGE=$(normalize_command_token "$COMMAND_MESSAGE")
  fi

  if [ -z "$COMMAND_MESSAGE" ]; then
    COMMAND_MESSAGE=$(normalize_command_token "$PROMPT")
  fi

  case "$COMMAND_MESSAGE" in
    ai-symbiote:*)
      NAME="${COMMAND_MESSAGE##*:}"
      NAME=$(sanitize_name "$NAME")
      if [ -n "$NAME" ] && [ "$NAME" != "stats" ]; then
        increment_counter "commands" "$NAME"
        track_skill_usage "$NAME" "command"
      fi
      exit 0
      ;;
    ai-symbiote/*)
      NAME="${COMMAND_MESSAGE##*/}"
      NAME=$(sanitize_name "$NAME")
      if [ -n "$NAME" ] && [ "$NAME" != "stats" ]; then
        increment_counter "commands" "$NAME"
        track_skill_usage "$NAME" "command"
      fi
      exit 0
      ;;
    /ai-symbiote:*)
      # normalize_command_token should have removed '/', but keep defensive fallback
      NAME="${COMMAND_MESSAGE##*:}"
      NAME=$(sanitize_name "$NAME")
      if [ -n "$NAME" ] && [ "$NAME" != "stats" ]; then
        increment_counter "commands" "$NAME"
        track_skill_usage "$NAME" "command"
      fi
      exit 0
      ;;
  esac
fi

# --- Skill tool detection ---
# Skill tool provides: tool_input.skill (e.g. "ai-symbiote:setup", "commit")
SKILL_NAME=$(json_nested_field "$INPUT" "tool_input" "skill")
if [ -z "$SKILL_NAME" ]; then
  SKILL_NAME=$(json_field "$INPUT" "skill")
fi
if [ -z "$SKILL_NAME" ]; then
  SKILL_NAME=$(json_nested_field "$INPUT" "tool_input" "skill_name")
fi
if [ -z "$SKILL_NAME" ]; then
  SKILL_NAME=$(json_nested_field "$INPUT" "tool_input" "command")
fi
if [ -z "$SKILL_NAME" ]; then
  SKILL_NAME=$(json_nested_field "$INPUT" "tool_input" "name")
fi

if [ -n "$SKILL_NAME" ]; then
  # Strip plugin prefix if present (e.g. "ai-symbiote:setup" -> "setup")
  SKILL_NAME=$(normalize_command_token "$SKILL_NAME")
  NAME="${SKILL_NAME##*:}"
  NAME=$(sanitize_name "$NAME")
  track_skill_usage "$NAME" "skill"
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

if [ "$CATEGORY" = "skills" ]; then
  track_skill_usage "$NAME" "read"
else
  increment_counter "$CATEGORY" "$NAME"
fi

exit 0
