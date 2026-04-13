#!/bin/bash
# ai-symbiote PostToolUse(Write|Edit) hook: Harness learning from agent mistakes.
# Detects repeated edits to the same file and error patterns.
# Records failures to harness-log.jsonl and auto-generates harness-rules.md rules.
#
# Author: JunyoungJung
# Date: 2026-04-08
#
# Principle: Silence on success — output ONLY when failure detected or rule added.
#
# Protocol:
#   stdin:  {"session_id":"...","tool_name":"Write|Edit","tool_input":{"file_path":"..."}}
#   stdout: {"continue":true,"systemMessage":"..."} when rule added or gc recommended
#           (empty) on success — "silence on success, loud on failure"
#
# Schema versions:
#   v1 (no "v" field): tool_error, repeated_error, churn, rule_created
#   v2 ("v":2):        loop_verify_fail, guard_blocked, pattern_*, rule_prevented, seed_loaded

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
SESSION_DIR="$STATE_DIR/state/session-$PPID"
mkdir -p "$SESSION_DIR" 2>/dev/null || exit 0

EVENTS_FILE="$SESSION_DIR/events.jsonl"
HARNESS_LOG="$STATE_DIR/harness-log.jsonl"
RULES_FILE="$STATE_DIR/harness-rules.md"

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
ERROR_CATEGORY=""
if [ -n "$TOOL_RESPONSE" ]; then
  # Classify error category from tool_response for precise pattern matching
  if printf '%s' "$TOOL_RESPONSE" | grep -qiE 'not unique' 2>/dev/null; then
    HAS_ERROR="error"
    ERROR_CATEGORY="not_unique"
  elif printf '%s' "$TOOL_RESPONSE" | grep -qiE '(not found|was not found)' 2>/dev/null; then
    HAS_ERROR="error"
    ERROR_CATEGORY="not_found"
  elif printf '%s' "$TOOL_RESPONSE" | grep -qiE '(no such file|does not exist)' 2>/dev/null; then
    HAS_ERROR="error"
    ERROR_CATEGORY="no_such_file"
  elif printf '%s' "$TOOL_RESPONSE" | grep -qiE 'permission denied' 2>/dev/null; then
    HAS_ERROR="error"
    ERROR_CATEGORY="permission_denied"
  elif printf '%s' "$TOOL_RESPONSE" | grep -qiE '(same as|new_string.*same|no changes|must be different)' 2>/dev/null; then
    HAS_ERROR="error"
    ERROR_CATEGORY="no_change"
  elif printf '%s' "$TOOL_RESPONSE" | grep -qiE '(error|failed|FAIL)' 2>/dev/null; then
    HAS_ERROR="error"
    ERROR_CATEGORY="generic_error"
  fi
fi

ESCAPED_FILE=$(json_escape "$FILE_PATH")
FILE_EXT="${FILE_PATH##*.}"
printf '{"ts":"%s","tool":"%s","file":"%s","ext":"%s","status":"%s","error_category":"%s"}\n' "$NOW" "$TOOL_NAME" "$ESCAPED_FILE" "$FILE_EXT" "$HAS_ERROR" "$ERROR_CATEGORY" >> "$EVENTS_FILE" 2>/dev/null

# --- 3a. Auto-loop Inspector result detection ---
# When file_path matches an Inspector result file, parse FAIL/PASS from content.
# Inspector FAIL results don't trigger tool_response errors (Write succeeds),
# so we detect by file path pattern + content parsing.
case "$FILE_PATH" in
  */state/*/results/inspector-*.result.md)
    if [ -f "$FILE_PATH" ]; then
      VERDICT=$(grep -m1 'FAIL\|PASS' "$FILE_PATH" 2>/dev/null)
      if printf '%s' "$VERDICT" | grep -q 'FAIL' 2>/dev/null; then
        # Extract failure reasons (first 20 lines, list items)
        FAIL_REASONS=$(head -20 "$FILE_PATH" | grep '^-' | head -3 | tr '\n' '; ' | sed 's/; $//')
        [ -z "$FAIL_REASONS" ] && FAIL_REASONS="Inspector returned FAIL"

        # Extract loop_task from state directory name
        LOOP_TASK=$(printf '%s' "$FILE_PATH" | sed 's|.*/state/\([^/]*\)/results/.*|\1|')
        # Extract iteration from ralph-state.md
        RALPH_STATE_DIR=$(printf '%s' "$FILE_PATH" | sed 's|/results/.*||')
        ITERATION=0
        if [ -f "$RALPH_STATE_DIR/ralph-state.md" ]; then
          ITERATION=$(grep -o 'iteration: [0-9]*' "$RALPH_STATE_DIR/ralph-state.md" 2>/dev/null | grep -o '[0-9]*' | head -1)
          [ -z "$ITERATION" ] && ITERATION=0
        fi

        ESC_REASONS=$(json_escape "$FAIL_REASONS")
        ESC_TASK=$(json_escape "$LOOP_TASK")
        RULE_CAND="Verify implementation meets all acceptance criteria before marking complete"

        # Record loop_verify_fail event (v2 schema)
        printf '{"v":2,"ts":"%s","error_type":"loop_verify_fail","file":"%s","description":"%s","rule_candidate":"%s","loop_task":"%s","iteration":%s,"session_pid":"%s"}\n' \
          "$NOW" "$ESCAPED_FILE" "$ESC_REASONS" "$(json_escape "$RULE_CAND")" "$ESC_TASK" "$ITERATION" "$PPID" >> "$HARNESS_LOG" 2>/dev/null

        # Check if same loop_task had repeated verify failures (2+ in 7 days)
        if [ -f "$HARNESS_LOG" ]; then
          LOOP_FAIL_COUNT=$(filter_recent_jsonl "$HARNESS_LOG" 7 | \
            grep '"error_type":"loop_verify_fail"' 2>/dev/null | \
            grep "\"loop_task\":\"$ESC_TASK\"" 2>/dev/null | \
            wc -l | tr -d ' ') || LOOP_FAIL_COUNT=0

          if [ "$LOOP_FAIL_COUNT" -ge 2 ] && [ -f "$RULES_FILE" ]; then
            # Dedup: skip if identical rule already exists
            if grep -qF "$RULE_CAND" "$RULES_FILE" 2>/dev/null; then
              exit 0
            fi
            RULE_COUNT=$(grep -c '^\[Harness #' "$RULES_FILE" 2>/dev/null) || RULE_COUNT=0
            NEXT_ID=$((RULE_COUNT + 1))
            TODAY=$(date +%Y-%m-%d)
            printf '\n[Harness #%d] %s (auto-generated %s)\n' "$NEXT_ID" "$RULE_CAND" "$TODAY" >> "$RULES_FILE" 2>/dev/null
            printf '{"v":2,"ts":"%s","type":"rule_created","rule_id":%d,"description":"%s"}\n' \
              "$NOW" "$NEXT_ID" "$ESC_REASONS" >> "$HARNESS_LOG" 2>/dev/null
            printf '{"continue":true,"systemMessage":"[Harness] Repeated auto failure in %s — auto-added Harness #%d rule."}\n' "$ESC_TASK" "$NEXT_ID"
            exit 0
          fi
        fi
      fi
      # PASS or no verdict — silence on success
    fi
    exit 0
    ;;
esac

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
# Error-category-specific rules for precise pattern matching
if [ "$HAS_ERROR" = "error" ]; then
  FAILURE_DETECTED="yes"
  case "$ERROR_CATEGORY" in
    not_unique)
      ERROR_TYPE="edit_not_unique"
      DESCRIPTION="$BASENAME: old_string is not unique"
      RULE_CANDIDATE="Provide more surrounding context lines in old_string to ensure uniqueness"
      ;;
    not_found)
      ERROR_TYPE="edit_not_found"
      DESCRIPTION="$BASENAME: old_string not found"
      RULE_CANDIDATE="Read $BASENAME content before editing; verify the exact target string exists with correct whitespace"
      ;;
    no_such_file)
      ERROR_TYPE="file_not_found"
      DESCRIPTION="$BASENAME: file does not exist"
      RULE_CANDIDATE="Verify $BASENAME exists (use Glob or ls) before attempting to edit"
      ;;
    permission_denied)
      ERROR_TYPE="permission_denied"
      DESCRIPTION="$BASENAME: permission denied"
      RULE_CANDIDATE="Check file permissions before editing $BASENAME; it may be read-only or a build artifact"
      ;;
    no_change)
      ERROR_TYPE="edit_no_change"
      DESCRIPTION="$BASENAME: new_string same as old_string"
      RULE_CANDIDATE="Verify the replacement is actually different from the original before calling Edit"
      ;;
    *)
      ERROR_TYPE="tool_error"
      DESCRIPTION="$BASENAME: tool returned error"
      RULE_CANDIDATE="Read $BASENAME content before editing; verify the exact target string exists"
      ;;
  esac
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

  ESC_ECAT=$(json_escape "$ERROR_CATEGORY")
  printf '{"ts":"%s","error_type":"%s","error_category":"%s","file":"%s","description":"%s","rule_candidate":"%s","session_pid":"%s"}\n' \
    "$NOW" "$ESC_ETYPE" "$ESC_ECAT" "$ESCAPED_FILE" "$ESC_DESC" "$ESC_RULE" "$PPID" >> "$HARNESS_LOG" 2>/dev/null

  # --- 6. Check if same pattern repeated 2+ times in last 7 days ---
  if [ -f "$HARNESS_LOG" ]; then
    # Count occurrences of same {error_type, file} tuple in recent entries
    # Filter by error_type field presence to exclude rule_created/rule_prevented events
    PATTERN_COUNT=$(filter_recent_jsonl "$HARNESS_LOG" 7 | \
      grep '"error_type"' 2>/dev/null | \
      grep "\"error_type\":\"$ESC_ETYPE\"" 2>/dev/null | \
      grep "\"file\":\"$ESCAPED_FILE\"" 2>/dev/null | \
      wc -l | tr -d ' ') || PATTERN_COUNT=0

    if [ "$PATTERN_COUNT" -ge 2 ]; then
      # --- 6a. Extension-level pattern aggregation (US-005) ---
      # Before creating a file-specific rule, check if 3+ different files with same
      # extension have the same error_type — if so, create a pattern rule instead.
      EXT_PATTERN_RULE=""
      if [ -n "$FILE_EXT" ] && [ "$FILE_EXT" != "$FILE_PATH" ]; then
        # Count unique files with same {ext, error_type} in recent entries
          EXT_FILE_COUNT=$(filter_recent_jsonl "$HARNESS_LOG" 7 | \
            grep "\"error_type\":\"$ESC_ETYPE\"" 2>/dev/null | \
            grep -o '"file":"[^"]*\.'"$FILE_EXT"'"' 2>/dev/null | \
            sort -u | wc -l | tr -d ' ') || EXT_FILE_COUNT=0

        if [ "$EXT_FILE_COUNT" -ge 3 ]; then
          EXT_PATTERN_RULE="yes"
          RULE_CANDIDATE="For *.$FILE_EXT files: $RULE_CANDIDATE"
        fi
      fi

      # --- 7. Auto-generate rule in harness-rules.md ---
      if [ -f "$RULES_FILE" ]; then
        # Dedup: skip if identical rule already exists
        if grep -qF "$RULE_CANDIDATE" "$RULES_FILE" 2>/dev/null; then
          exit 0
        fi
        LINE_COUNT=$(wc -l < "$RULES_FILE" | tr -d ' ')

        if [ "$LINE_COUNT" -ge 300 ]; then
          # Context too large — recommend gc instead
          printf '{"continue":true,"systemMessage":"[Harness] harness-rules.md reached %d lines (limit 300). Run gc skill to prune unused rules."}\n' "$LINE_COUNT"
          exit 0
        fi

        # If pattern rule, remove existing per-file rules for this extension
        if [ -n "$EXT_PATTERN_RULE" ]; then
          sed -i '' '/^\[Harness #[0-9]*\].*'"$FILE_EXT"'/d' "$RULES_FILE" 2>/dev/null || \
            sed -i '/^\[Harness #[0-9]*\].*'"$FILE_EXT"'/d' "$RULES_FILE" 2>/dev/null
        fi

        # Count existing harness rules to determine next ID
        RULE_COUNT=$(grep -c '^\[Harness #' "$RULES_FILE" 2>/dev/null) || RULE_COUNT=0
        NEXT_ID=$((RULE_COUNT + 1))
        TODAY=$(date +%Y-%m-%d)

        # Append rule to context.md
        printf '\n[Harness #%d] %s (auto-generated %s)\n' "$NEXT_ID" "$RULE_CANDIDATE" "$TODAY" >> "$RULES_FILE" 2>/dev/null

        # Record rule creation event
        if [ -n "$EXT_PATTERN_RULE" ]; then
          printf '{"v":2,"ts":"%s","type":"rule_created","rule_id":%d,"description":"%s","pattern":"*.%s"}\n' \
            "$NOW" "$NEXT_ID" "$ESC_DESC" "$FILE_EXT" >> "$HARNESS_LOG" 2>/dev/null
        else
          printf '{"ts":"%s","type":"rule_created","rule_id":%d,"description":"%s"}\n' \
            "$NOW" "$NEXT_ID" "$ESC_DESC" >> "$HARNESS_LOG" 2>/dev/null
        fi

        printf '{"continue":true,"systemMessage":"[Harness] Repeated mistake detected: %s — auto-added Harness #%d rule to harness-rules.md."}\n' "$ESC_DESC" "$NEXT_ID"
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
