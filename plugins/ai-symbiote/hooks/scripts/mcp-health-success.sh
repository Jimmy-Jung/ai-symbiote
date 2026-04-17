#!/bin/bash
# ai-symbiote PostToolUse hook: Reset MCP failure counter on successful tool call.
# Clears the consecutive failure counter so healthy servers are not blocked.
#
# Created by JunyoungJung on 2026-04-16. Copyright © 2026 ai-symbiote.
#
# Protocol:
#   stdin:  {"tool_name":"mcp__context7__query-docs","tool_input":{...},"tool_result":"..."}
#   stdout: {"continue":true}

# Safety: never crash the agent workflow
trap 'exit 0' ERR
set +e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

# --- 1. Read stdin JSON ---
INPUT=$(read_stdin_safe)

# --- 2. Extract tool_name ---
TOOL_NAME=""
if command -v jq >/dev/null 2>&1; then
  TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null) || TOOL_NAME=""
elif command -v python3 >/dev/null 2>&1; then
  TOOL_NAME=$(printf '%s' "$INPUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_name",""))' 2>/dev/null) || TOOL_NAME=""
else
  TOOL_NAME=$(printf '%s' "$INPUT" | grep -o '"tool_name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/"tool_name"[[:space:]]*:[[:space:]]*"//' | sed 's/"$//') || TOOL_NAME=""
fi

# --- 3. Skip non-MCP tools ---
case "$TOOL_NAME" in
  mcp__*) ;;
  *)
    emit_hook_continue
    exit 0
    ;;
esac

# --- 4. Extract server name ---
SERVER="${TOOL_NAME#mcp__}"
SERVER="${SERVER%%__*}"

if [ -z "$SERVER" ]; then
  emit_hook_continue
  exit 0
fi

# --- 5. Health file path ---
HEALTH_FILE="$(safe_session_file "symbiote-mcp-health").json"

# --- 6. Reset fail_count if health file exists and has an entry ---
if [ ! -f "$HEALTH_FILE" ]; then
  emit_hook_continue
  exit 0
fi

if command -v jq >/dev/null 2>&1; then
  # Check if server entry exists
  HAS_ENTRY=$(jq -r "has(\"${SERVER}\")" "$HEALTH_FILE" 2>/dev/null) || HAS_ENTRY="false"
  if [ "$HAS_ENTRY" = "true" ]; then
    UPDATED=$(jq --arg srv "$SERVER" '.[$srv].fail_count = 0' "$HEALTH_FILE" 2>/dev/null)
    if [ -n "$UPDATED" ]; then
      _TMP_HF=$(mktemp "${HEALTH_FILE}.XXXXXX" 2>/dev/null) || _TMP_HF="${HEALTH_FILE}.tmp.$$"
      printf '%s' "$UPDATED" > "$_TMP_HF"
      mv -f "$_TMP_HF" "$HEALTH_FILE" 2>/dev/null || printf '%s' "$UPDATED" > "$HEALTH_FILE"
    fi
  fi
elif command -v python3 >/dev/null 2>&1; then
  python3 -c "
import json, os
health_file = '$HEALTH_FILE'
server = '$SERVER'
try:
    with open(health_file) as f:
        data = json.load(f)
    if server in data:
        data[server]['fail_count'] = 0
        with open(health_file, 'w') as f:
            json.dump(data, f, separators=(',', ':'))
except Exception:
    pass
" 2>/dev/null
else
  # grep fallback: rewrite with reset counter
  if grep -q "\"${SERVER}\"" "$HEALTH_FILE" 2>/dev/null; then
    LAST_FAILURE=$(grep -o "\"${SERVER}\"[^}]*\"last_failure\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$HEALTH_FILE" 2>/dev/null | grep -o '"[0-9T:Z-]*"$' | tr -d '"') || LAST_FAILURE=""
    printf '{\"%s\":{\"fail_count\":0,\"last_failure\":\"%s\"}}' "$SERVER" "$LAST_FAILURE" > "$HEALTH_FILE"
  fi
fi

# --- 7. Always continue ---
emit_hook_continue
exit 0
