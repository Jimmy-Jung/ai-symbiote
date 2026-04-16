#!/bin/bash
# ai-symbiote feedback logger: Record user rejection of agent changes.
# Called by the agent when the user says a change doesn't work or needs revert.
#
# Author: JunyoungJung
# Date: 2026-04-13
#
# Usage:
#   bash feedback-logger.sh "<file_path>" "<rejection_reason>" "<rule_suggestion>"
#
# Example:
#   bash feedback-logger.sh "src/App.swift" "layout breaks on iPad" "Test on multiple screen sizes before submitting layout changes"
#
# This is NOT a hook — it's a utility script invoked by the agent via Bash tool
# when it detects user dissatisfaction. The agent is instructed to call this
# via Seed #S6 in generic.md.

set +e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

FILE_PATH="${1:-unknown}"
REASON="${2:-user rejected change}"
RULE_SUGGESTION="${3:-Verify changes meet user requirements before proceeding}"

STATE_DIR=$(get_state_dir)
[ -z "$STATE_DIR" ] && exit 0

HARNESS_LOG="$STATE_DIR/harness-log.jsonl"
RULES_FILE="$STATE_DIR/harness-rules.md"
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
BASENAME=$(basename "$FILE_PATH")

ESC_FILE=$(json_escape "$FILE_PATH")
ESC_REASON=$(json_escape "$REASON")
ESC_RULE=$(json_escape "$RULE_SUGGESTION")
ESC_DESC=$(json_escape "$BASENAME: user rejected — $REASON")

# Record to harness-log.jsonl
printf '{"v":2,"ts":"%s","error_type":"user_feedback","error_category":"user_rejected","file":"%s","description":"%s","rule_candidate":"%s","session_pid":"%s"}\n' \
  "$NOW" "$ESC_FILE" "$ESC_DESC" "$ESC_RULE" "$PPID" >> "$HARNESS_LOG" 2>/dev/null

# Check repeated user rejections on same file (2+ in 7 days)
if [ -f "$HARNESS_LOG" ] && [ -f "$RULES_FILE" ]; then
  PATTERN_COUNT=$(filter_recent_jsonl "$HARNESS_LOG" 7 | \
    grep '"error_type":"user_feedback"' 2>/dev/null | \
    grep "\"file\":\"$ESC_FILE\"" 2>/dev/null | \
    wc -l | tr -d ' ') || PATTERN_COUNT=0

  if [ "$PATTERN_COUNT" -ge 2 ]; then
    if grep -qF "$RULE_SUGGESTION" "$RULES_FILE" 2>/dev/null; then
      echo "Feedback logged. Rule already exists."
      exit 0
    fi

    LINE_COUNT=$(wc -l < "$RULES_FILE" | tr -d ' ')
    if [ "$LINE_COUNT" -ge 300 ]; then
      echo "Feedback logged. harness-rules.md at limit — run gc skill."
      exit 0
    fi

    RULE_COUNT=$(grep -c '^\[Harness #' "$RULES_FILE" 2>/dev/null) || RULE_COUNT=0
    NEXT_ID=$((RULE_COUNT + 1))
    TODAY=$(date +%Y-%m-%d)

    printf '\n[Harness #%d] %s (auto-generated %s from user feedback)\n' "$NEXT_ID" "$RULE_SUGGESTION" "$TODAY" >> "$RULES_FILE" 2>/dev/null
    printf '{"v":2,"ts":"%s","type":"rule_created","rule_id":%d,"description":"%s","source":"user_feedback"}\n' \
      "$NOW" "$NEXT_ID" "$ESC_DESC" >> "$HARNESS_LOG" 2>/dev/null

    echo "Feedback logged. Auto-added Harness #$NEXT_ID rule."
    exit 0
  fi
fi

echo "Feedback logged."
exit 0
