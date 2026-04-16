#!/bin/bash
# ai-symbiote PreToolUse hook: Check MCP server health before tool calls.
# Blocks calls to servers with 3+ consecutive failures. Resets on success
# after a 5-minute cooldown period.
#
# Created by JunyoungJung on 2026-04-16. Copyright © 2026 ai-symbiote.
#
# Protocol:
#   stdin:  {"tool_name":"mcp__context7__query-docs","tool_input":{...}}
#   stdout: {"continue":false,...} to block | {"continue":true} to approve

# Safety: never crash the agent workflow
trap 'exit 0' ERR
set +e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

# --- 1. Read stdin JSON ---
INPUT=$(cat)

# --- 2. Extract tool_name ---
TOOL_NAME=""
if command -v jq >/dev/null 2>&1; then
  TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null) || TOOL_NAME=""
elif command -v python3 >/dev/null 2>&1; then
  TOOL_NAME=$(printf '%s' "$INPUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_name",""))' 2>/dev/null) || TOOL_NAME=""
else
  TOOL_NAME=$(printf '%s' "$INPUT" | grep -o '"tool_name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/"tool_name"[[:space:]]*:[[:space:]]*"//' | sed 's/"$//') || TOOL_NAME=""
fi

# --- 3. Fast path: skip non-MCP tools ---
case "$TOOL_NAME" in
  mcp__*) ;;
  *)
    emit_hook_continue
    exit 0
    ;;
esac

# --- 4. Extract server name (second segment of mcp__SERVER__method) ---
SERVER=$(printf '%s' "$TOOL_NAME" | cut -d'_' -f4-)
# cut -d'_' splits mcp__server__method → fields: mcp, "", server, "", method...
# More robust: use parameter expansion
SERVER="${TOOL_NAME#mcp__}"
SERVER="${SERVER%%__*}"

if [ -z "$SERVER" ]; then
  emit_hook_continue
  exit 0
fi

# --- 5. Health file path (session-scoped temp file) ---
HEALTH_FILE="$(safe_session_file "symbiote-mcp-health").json"

# --- 6. Read health state for this server ---
FAIL_COUNT=0
LAST_FAILURE=""

if [ -f "$HEALTH_FILE" ]; then
  if command -v jq >/dev/null 2>&1; then
    FAIL_COUNT=$(jq -r ".\"${SERVER}\".fail_count // 0" "$HEALTH_FILE" 2>/dev/null) || FAIL_COUNT=0
    LAST_FAILURE=$(jq -r ".\"${SERVER}\".last_failure // empty" "$HEALTH_FILE" 2>/dev/null) || LAST_FAILURE=""
  elif command -v python3 >/dev/null 2>&1; then
    FAIL_COUNT=$(python3 -c "
import json, sys
try:
    with open('$HEALTH_FILE') as f:
        data = json.load(f)
    print(data.get('$SERVER', {}).get('fail_count', 0))
except Exception:
    print(0)
" 2>/dev/null) || FAIL_COUNT=0
    LAST_FAILURE=$(python3 -c "
import json, sys
try:
    with open('$HEALTH_FILE') as f:
        data = json.load(f)
    print(data.get('$SERVER', {}).get('last_failure', ''))
except Exception:
    print('')
" 2>/dev/null) || LAST_FAILURE=""
  else
    # grep fallback: extract fail_count for this server
    FAIL_COUNT=$(grep -o "\"${SERVER}\"[^}]*\"fail_count\"[[:space:]]*:[[:space:]]*[0-9]*" "$HEALTH_FILE" 2>/dev/null | grep -o '[0-9]*$') || FAIL_COUNT=0
    LAST_FAILURE=$(grep -o "\"${SERVER}\"[^}]*\"last_failure\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$HEALTH_FILE" 2>/dev/null | grep -o '[0-9T:Z-]*"$' | tr -d '"') || LAST_FAILURE=""
  fi
fi

# Ensure FAIL_COUNT is numeric
FAIL_COUNT=$((FAIL_COUNT + 0)) 2>/dev/null || FAIL_COUNT=0

# --- 7. Check threshold ---
if [ "$FAIL_COUNT" -ge 3 ] 2>/dev/null; then
  # Calculate seconds since last failure
  ELAPSED=0
  if [ -n "$LAST_FAILURE" ]; then
    if command -v python3 >/dev/null 2>&1; then
      ELAPSED=$(python3 -c "
import datetime, sys
try:
    ts = '$LAST_FAILURE'.replace('Z', '+00:00')
    last = datetime.datetime.fromisoformat(ts)
    now = datetime.datetime.now(datetime.timezone.utc)
    print(int((now - last).total_seconds()))
except Exception:
    print(0)
" 2>/dev/null) || ELAPSED=0
    elif command -v date >/dev/null 2>&1; then
      # macOS date -j -f or GNU date -d
      NOW_EPOCH=$(date +%s 2>/dev/null) || NOW_EPOCH=0
      LAST_EPOCH=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$LAST_FAILURE" +%s 2>/dev/null) || \
        LAST_EPOCH=$(date -d "$LAST_FAILURE" +%s 2>/dev/null) || LAST_EPOCH=0
      if [ "$NOW_EPOCH" -gt 0 ] && [ "$LAST_EPOCH" -gt 0 ]; then
        ELAPSED=$((NOW_EPOCH - LAST_EPOCH))
      fi
    fi
  fi

  ELAPSED=$((ELAPSED + 0)) 2>/dev/null || ELAPSED=0

  if [ "$ELAPSED" -lt 300 ]; then
    # Still within cooldown — block
    emit_hook_block "[MCP Health] ${SERVER} is unhealthy (${FAIL_COUNT} consecutive failures). Use non-MCP alternatives or restart the server."
    exit 0
  else
    # Cooldown expired — reset counter and allow retry
    if command -v jq >/dev/null 2>&1; then
      UPDATED=$(jq --arg srv "$SERVER" '.[$srv].fail_count = 0' "$HEALTH_FILE" 2>/dev/null)
      if [ -n "$UPDATED" ]; then
        _TMP_HF=$(mktemp "${HEALTH_FILE}.XXXXXX" 2>/dev/null) || _TMP_HF="${HEALTH_FILE}.tmp.$$"
        printf '%s' "$UPDATED" > "$_TMP_HF"
        mv -f "$_TMP_HF" "$HEALTH_FILE" 2>/dev/null || printf '%s' "$UPDATED" > "$HEALTH_FILE"
      fi
    elif command -v python3 >/dev/null 2>&1; then
      python3 -c "
import json
try:
    with open('$HEALTH_FILE') as f:
        data = json.load(f)
    if '$SERVER' in data:
        data['$SERVER']['fail_count'] = 0
    with open('$HEALTH_FILE', 'w') as f:
        json.dump(data, f, separators=(',', ':'))
except Exception:
    pass
" 2>/dev/null
    fi
    emit_hook_continue
    exit 0
  fi
fi

# --- 8. Under threshold — allow ---
emit_hook_continue
exit 0
