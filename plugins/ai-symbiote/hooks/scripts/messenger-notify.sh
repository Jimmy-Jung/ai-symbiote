#!/bin/bash
# ai-symbiote PostToolUse hook: Messenger notification trigger
# Detects state changes when ralph-state.md is written and creates notification JSON.
#
# Author: JunyoungJung
# Date: 2026-04-02

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

INPUT=$(cat)

STATE_DIR=$(get_state_dir)
MESSENGER_DIR="$STATE_DIR/messenger"
NOTIFY_DIR="$MESSENGER_DIR/notifications"

# Skip if no messenger config
[ -f "$MESSENGER_DIR/config.json" ] || exit 0

# Skip if bot is not running
if [ -f "$MESSENGER_DIR/bot.pid" ]; then
  BOT_PID=$(cat "$MESSENGER_DIR/bot.pid" 2>/dev/null)
  if [ -n "$BOT_PID" ] && ! kill -0 "$BOT_PID" 2>/dev/null; then
    exit 0
  fi
else
  exit 0
fi

# Get written file path
TOOL_INPUT=$(json_field "$INPUT" "tool_input")
FILE_PATH=""

# Write tool: file_path field
FILE_PATH=$(printf '%s' "$INPUT" | grep -o '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"file_path"[[:space:]]*:[[:space:]]*"//' | sed 's/"$//')

# Skip if not ralph-state.md
case "$FILE_PATH" in
  *ralph-state.md) ;;
  *) exit 0 ;;
esac

# Parse ralph-state.md
[ -f "$FILE_PATH" ] || exit 0

ACTIVE=$(grep -o 'active: [a-z]*' "$FILE_PATH" | head -1 | awk '{print $2}')
PHASE=$(grep -o 'phase: [a-z]*' "$FILE_PATH" | head -1 | awk '{print $2}')
ITERATION=$(grep -o 'iteration: [0-9]*' "$FILE_PATH" | head -1 | awk '{print $2}')
MAX_ITER=$(grep -o 'maxIterations: [0-9]*' "$FILE_PATH" | head -1 | awk '{print $2}')
TASK_DESC=$(grep 'taskDescription:' "$FILE_PATH" | head -1 | sed 's/- taskDescription:[[:space:]]*//')

# Extract task-folder name
TASK_FOLDER=$(basename "$(dirname "$FILE_PATH")")

# Compare with previous state cache
CACHE_FILE="$MESSENGER_DIR/.ralph-state-cache"
PREV_PHASE=""
PREV_ACTIVE=""
if [ -f "$CACHE_FILE" ]; then
  PREV_PHASE=$(grep 'phase:' "$CACHE_FILE" 2>/dev/null | awk '{print $2}')
  PREV_ACTIVE=$(grep 'active:' "$CACHE_FILE" 2>/dev/null | awk '{print $2}')
fi

# Save current state to cache
printf "phase: %s\nactive: %s\niteration: %s\n" "$PHASE" "$ACTIVE" "$ITERATION" > "$CACHE_FILE"

# Determine event
EVENT=""
SUMMARY=""

if [ "$ACTIVE" = "true" ] && [ -z "$PREV_ACTIVE" ]; then
  EVENT="loop_start"
  SUMMARY="Loop started"
elif [ "$ACTIVE" = "false" ] && [ "$PREV_ACTIVE" = "true" ]; then
  if [ "$PHASE" = "complete" ]; then
    EVENT="loop_complete"
    SUMMARY="Task completed"
  elif [ "$PHASE" = "cancelled" ]; then
    EVENT="loop_complete"
    SUMMARY="Task cancelled"
  else
    EVENT="error"
    SUMMARY="Loop terminated abnormally"
  fi
elif [ "$PHASE" != "$PREV_PHASE" ] && [ -n "$PREV_PHASE" ]; then
  EVENT="phase_change"
  SUMMARY="Phase changed from ${PREV_PHASE} to ${PHASE}"
fi

# Skip if no event
[ -n "$EVENT" ] || exit 0

# Ensure notification directory
mkdir -p "$NOTIFY_DIR" 2>/dev/null

# Generate filename-safe timestamp
TS=$(date -u +"%Y-%m-%dT%H-%M-%S")

# Write notification JSON
ESCAPED_SUMMARY=$(json_escape "$SUMMARY")
ESCAPED_TASK_DESC=$(json_escape "$TASK_DESC")
ESCAPED_TASK_FOLDER=$(json_escape "$TASK_FOLDER")

cat > "$NOTIFY_DIR/${TS}_${EVENT}.json" <<ENDJSON
{
  "event": "${EVENT}",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "taskFolder": "${ESCAPED_TASK_FOLDER}",
  "data": {
    "iteration": ${ITERATION:-0},
    "maxIterations": ${MAX_ITER:-10},
    "phase": "${PHASE}",
    "summary": "${ESCAPED_SUMMARY}",
    "taskDescription": "${ESCAPED_TASK_DESC}"
  }
}
ENDJSON

# Claude Code hook protocol: continue
emit_hook_continue
exit 0
