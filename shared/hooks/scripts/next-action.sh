#!/bin/bash
# ai-symbiote Stop hook: Context-aware next action recommender.
# Suggests next skills based on git state and last skill invocation.
#
# Created by JunyoungJung on 2026-04-16. Copyright © 2026 ai-symbiote.

trap 'exit 0' ERR
set +e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

# Capture stdin to temp file for byte-for-byte passthrough
# Fallback: if temp file I/O fails, pass stdin directly and skip recommendations
STDIN_TMP=$(mktemp "${TMPDIR:-/tmp}/symbiote-next-action.XXXXXX" 2>/dev/null) || STDIN_TMP="${TMPDIR:-/tmp}/symbiote-next-action.$$"
cat > "$STDIN_TMP"
if [ ! -s "$STDIN_TMP" ] && [ ! -f "$STDIN_TMP" ]; then
  # Temp file creation failed — cannot proceed safely
  exit 0
fi

# Check disable flag
if [ "${SYMBIOTE_NEXT_ACTION:-}" = "0" ]; then
  cat "$STDIN_TMP"
  rm -f "$STDIN_TMP"
  exit 0
fi

STATE_DIR=$(get_state_dir)

# Locate skill-chains.json
CHAINS_FILE="$SCRIPT_DIR/../../lib/skill-chains.json"
[ ! -f "$CHAINS_FILE" ] && CHAINS_FILE="$SCRIPT_DIR/../lib/skill-chains.json"

# Detect last skill from usage data
USAGE_DIR="$STATE_DIR/usage-data"
LAST_SKILL=""
if [ -d "$USAGE_DIR" ]; then
  # usage-tracker stores per-skill files in usage-data/skills/
  # Each file is named after the skill and contains "count|timestamp"
  SKILLS_DIR="$USAGE_DIR/skills"
  if [ -d "$SKILLS_DIR" ]; then
    # Find the most recently modified skill file
    LATEST_FILE=""
    LATEST_MOD=0
    for f in "$SKILLS_DIR"/*; do
      [ -f "$f" ] || continue
      # Get modification time as epoch
      if stat -f '%m' "$f" >/dev/null 2>&1; then
        MOD_TIME=$(stat -f '%m' "$f" 2>/dev/null) || MOD_TIME=0
      elif stat -c '%Y' "$f" >/dev/null 2>&1; then
        MOD_TIME=$(stat -c '%Y' "$f" 2>/dev/null) || MOD_TIME=0
      else
        MOD_TIME=0
      fi
      case "$MOD_TIME" in
        ''|*[!0-9]*) MOD_TIME=0 ;;
      esac
      if [ "$MOD_TIME" -gt "$LATEST_MOD" ] 2>/dev/null; then
        LATEST_MOD="$MOD_TIME"
        LATEST_FILE="$f"
      fi
    done
    if [ -n "$LATEST_FILE" ]; then
      LAST_SKILL=$(basename "$LATEST_FILE")
    fi
  fi

  # Fallback: check for JSONL files with skill field
  if [ -z "$LAST_SKILL" ]; then
    for f in "$USAGE_DIR"/*.json "$USAGE_DIR"/*.jsonl; do
      [ -f "$f" ] || continue
      if command -v jq >/dev/null 2>&1; then
        LAST_SKILL=$(tail -1 "$f" 2>/dev/null | jq -r '.skill // empty' 2>/dev/null) || LAST_SKILL=""
      fi
      [ -n "$LAST_SKILL" ] && break
    done
  fi
fi

# Check skill chain for recommendation
RECOMMENDATION=""
if [ -n "$LAST_SKILL" ] && [ -f "$CHAINS_FILE" ]; then
  if command -v jq >/dev/null 2>&1; then
    RECOMMENDATION=$(jq -r ".chains.\"$LAST_SKILL\".message // empty" "$CHAINS_FILE" 2>/dev/null) || RECOMMENDATION=""
  elif command -v python3 >/dev/null 2>&1; then
    RECOMMENDATION=$(python3 -c "import json; data=json.load(open('$CHAINS_FILE')); print(data.get('chains',{}).get('$LAST_SKILL',{}).get('message',''))" 2>/dev/null) || RECOMMENDATION=""
  fi
fi

# Git context fallback (if no skill chain match)
if [ -z "$RECOMMENDATION" ]; then
  MODIFIED_COUNT=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ') || MODIFIED_COUNT=0
  BRANCH=$(git branch --show-current 2>/dev/null) || BRANCH=""

  if [ "$MODIFIED_COUNT" -gt 0 ] 2>/dev/null; then
    if command -v jq >/dev/null 2>&1 && [ -f "$CHAINS_FILE" ]; then
      RECOMMENDATION=$(jq -r '.git_context_fallbacks.modified_uncommitted // empty' "$CHAINS_FILE" 2>/dev/null) || RECOMMENDATION=""
    else
      RECOMMENDATION="Changes detected. Consider: /commit to save, /review to check quality"
    fi
  elif [ -n "$BRANCH" ] && [ "$BRANCH" != "main" ] && [ "$BRANCH" != "master" ]; then
    AHEAD=$(git rev-list --count origin/"$BRANCH"..HEAD 2>/dev/null) || AHEAD=0
    if [ "$AHEAD" -gt 0 ] 2>/dev/null; then
      RECOMMENDATION="On feature branch with commits. Consider: /ship to create PR"
    fi
  fi
fi

# Log recommendation to harness-log.jsonl
if [ -n "$RECOMMENDATION" ]; then
  mkdir -p "$STATE_DIR" 2>/dev/null
  LOG_FILE="$STATE_DIR/harness-log.jsonl"
  TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  ESCAPED_MSG=$(json_escape "$RECOMMENDATION")
  printf '{"v":2,"ts":"%s","type":"next_action","message":"%s"}\n' "$TS" "$ESCAPED_MSG" >> "$LOG_FILE" 2>/dev/null
fi

# Pass stdin through to stdout (byte-for-byte via temp file)
cat "$STDIN_TMP"
rm -f "$STDIN_TMP"

exit 0
