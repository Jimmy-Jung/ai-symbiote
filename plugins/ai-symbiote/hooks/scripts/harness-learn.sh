#!/bin/bash
# ai-symbiote PostToolUse(Write|Edit) hook: Harness learning from agent mistakes.
# Detects repeated edits to the same file and error patterns.
# Records failures to harness-log.jsonl and auto-generates context.md rules.
#
# Author: JunyoungJung
# Date: 2026-04-08
#
# Protocol:
#   stdin:  {"session_id":"...","tool_name":"Write|Edit","tool_input":{"file_path":"..."}}
#   stdout: {"continue":true,"systemMessage":"..."} when rule added or gc recommended
#           (empty) on success — "silence on success, loud on failure"

# Safety: never crash the agent workflow
trap 'exit 0' ERR
set +e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

INPUT=$(cat)

# --- 1. Extract file path ---
FILE_PATH=$(json_nested_field "$INPUT" "tool_input" "file_path")
if [ -z "$FILE_PATH" ]; then
  FILE_PATH=$(json_field "$INPUT" "file_path")
fi

if [ -z "$FILE_PATH" ]; then
  exit 0
fi

# --- 2. State directory setup ---
STATE_DIR=$(get_state_dir)
SESSION_DIR="$STATE_DIR/session-$PPID"
mkdir -p "$SESSION_DIR" 2>/dev/null || exit 0

EVENTS_FILE="$SESSION_DIR/events.jsonl"
HARNESS_LOG="$STATE_DIR/harness-log.jsonl"
CONTEXT_FILE="$STATE_DIR/context.md"

# --- 3. Record event ---
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
TOOL_NAME=$(json_field "$INPUT" "tool_name")
[ -z "$TOOL_NAME" ] && TOOL_NAME="Edit"

# Detect actual tool failure from tool_response (available in PostToolUse)
TOOL_RESPONSE=""
if command -v jq >/dev/null 2>&1; then
  TOOL_RESPONSE=$(printf '%s' "$INPUT" | jq -r '.tool_response // empty' 2>/dev/null)
else
  TOOL_RESPONSE=$(printf '%s' "$INPUT" | grep -o '"tool_response"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"tool_response"[[:space:]]*:[[:space:]]*"//' | sed 's/"$//')
fi

HAS_ERROR="ok"
if [ -n "$TOOL_RESPONSE" ]; then
  # Check tool_response for real failure signals
  if printf '%s' "$TOOL_RESPONSE" | grep -qiE '(error|failed|not found|not unique|does not exist|no such file|permission denied)' 2>/dev/null; then
    HAS_ERROR="error"
  fi
fi

ESCAPED_FILE=$(json_escape "$FILE_PATH")
printf '{"ts":"%s","tool":"%s","file":"%s","status":"%s"}\n' "$NOW" "$TOOL_NAME" "$ESCAPED_FILE" "$HAS_ERROR" >> "$EVENTS_FILE" 2>/dev/null

# --- 4. Detect failure patterns ---
EDIT_COUNT=0
ERROR_COUNT=0
if [ -f "$EVENTS_FILE" ]; then
  EDIT_COUNT=$(grep -c "\"file\":\"$ESCAPED_FILE\"" "$EVENTS_FILE" 2>/dev/null) || EDIT_COUNT=0
  ERROR_COUNT=$(grep "\"file\":\"$ESCAPED_FILE\"" "$EVENTS_FILE" 2>/dev/null | grep -c '"status":"error"' 2>/dev/null) || ERROR_COUNT=0
fi

FAILURE_DETECTED=""
ERROR_TYPE=""
DESCRIPTION=""
RULE_CANDIDATE=""
BASENAME=$(basename "$FILE_PATH")

# Pattern 1: Tool returned an error (from tool_response)
if [ "$HAS_ERROR" = "error" ]; then
  FAILURE_DETECTED="yes"
  ERROR_TYPE="tool_error"
  DESCRIPTION="$BASENAME: tool returned error"
  RULE_CANDIDATE="Read $BASENAME content before editing; verify the exact target string exists"
fi

# Pattern 2: Same file had 2+ errors in this session (struggling)
if [ "$ERROR_COUNT" -ge 2 ] && [ -z "$FAILURE_DETECTED" ]; then
  FAILURE_DETECTED="yes"
  ERROR_TYPE="repeated_error"
  DESCRIPTION="$BASENAME: ${ERROR_COUNT} errors in session (struggling pattern)"
  RULE_CANDIDATE="Stop and re-read $BASENAME fully before attempting more edits; consider a different approach"
fi

# Pattern 3: Same file edited 5+ times without errors (churn, higher threshold to reduce false positives)
if [ "$EDIT_COUNT" -ge 5 ] && [ -z "$FAILURE_DETECTED" ]; then
  FAILURE_DETECTED="yes"
  ERROR_TYPE="churn"
  DESCRIPTION="$BASENAME: edited ${EDIT_COUNT} times in session (churn pattern)"
  RULE_CANDIDATE="Plan all changes to $BASENAME upfront before editing; avoid incremental trial-and-error"
fi

# --- 5. Record failure to harness-log.jsonl ---
if [ -n "$FAILURE_DETECTED" ]; then
  ESC_DESC=$(json_escape "$DESCRIPTION")
  ESC_RULE=$(json_escape "$RULE_CANDIDATE")
  ESC_ETYPE=$(json_escape "$ERROR_TYPE")

  printf '{"ts":"%s","error_type":"%s","file":"%s","description":"%s","rule_candidate":"%s","session_pid":"%s"}\n' \
    "$NOW" "$ESC_ETYPE" "$ESCAPED_FILE" "$ESC_DESC" "$ESC_RULE" "$PPID" >> "$HARNESS_LOG" 2>/dev/null

  # --- 6. Check if same pattern repeated 2+ times in last 7 days ---
  if [ -f "$HARNESS_LOG" ]; then
    SEVEN_DAYS_AGO=$(date -u -v-7d +%Y-%m-%dT 2>/dev/null || date -u -d '7 days ago' +%Y-%m-%dT 2>/dev/null || echo "0000")

    # Count occurrences of same {error_type, file} tuple in recent entries
    PATTERN_COUNT=$(grep "\"error_type\":\"$ESC_ETYPE\"" "$HARNESS_LOG" 2>/dev/null | \
      grep "\"file\":\"$ESCAPED_FILE\"" 2>/dev/null | \
      grep "$SEVEN_DAYS_AGO\|$(date -u +%Y-%m-%d)" 2>/dev/null | \
      wc -l | tr -d ' ') || PATTERN_COUNT=0

    if [ "$PATTERN_COUNT" -ge 2 ]; then
      # --- 7. Auto-generate rule in context.md ---
      if [ -f "$CONTEXT_FILE" ]; then
        LINE_COUNT=$(wc -l < "$CONTEXT_FILE" | tr -d ' ')

        if [ "$LINE_COUNT" -ge 300 ]; then
          # Context too large — recommend gc instead
          printf '{"continue":true,"systemMessage":"[Harness] context.md reached %d lines (limit 300). Run gc skill to prune unused rules."}\n' "$LINE_COUNT"
          exit 0
        fi

        # Count existing harness rules to determine next ID
        RULE_COUNT=$(grep -c '^\[Harness #' "$CONTEXT_FILE" 2>/dev/null) || RULE_COUNT=0
        NEXT_ID=$((RULE_COUNT + 1))
        TODAY=$(date +%Y-%m-%d)

        # Append rule to context.md
        printf '\n[Harness #%d] %s (auto-generated %s)\n' "$NEXT_ID" "$RULE_CANDIDATE" "$TODAY" >> "$CONTEXT_FILE" 2>/dev/null

        # Record rule_triggered event for gc tracking
        printf '{"ts":"%s","type":"rule_created","rule_id":%d,"description":"%s"}\n' \
          "$NOW" "$NEXT_ID" "$ESC_DESC" >> "$HARNESS_LOG" 2>/dev/null

        printf '{"continue":true,"systemMessage":"[Harness] Repeated mistake detected: %s — auto-added Harness #%d rule to context.md."}\n' "$ESC_DESC" "$NEXT_ID"
        exit 0
      fi
    fi
  fi
fi

# --- 8. Enforce harness-log.jsonl size limit ---
if [ -f "$HARNESS_LOG" ]; then
  LOG_LINES=$(wc -l < "$HARNESS_LOG" | tr -d ' ')
  if [ "$LOG_LINES" -gt 1000 ]; then
    # Keep last 800 lines
    tail -800 "$HARNESS_LOG" > "$HARNESS_LOG.tmp" 2>/dev/null && \
      mv "$HARNESS_LOG.tmp" "$HARNESS_LOG" 2>/dev/null
  fi
fi

exit 0
