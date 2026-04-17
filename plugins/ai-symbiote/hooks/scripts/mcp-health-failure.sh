#!/bin/bash
# ai-symbiote PostToolUseFailure hook: Record MCP tool failures for health tracking.
# Increments the consecutive failure counter and updates the last_failure timestamp.
#
# Created by JunyoungJung on 2026-04-16. Copyright © 2026 ai-symbiote.
#
# Protocol:
#   stdin:  {"tool_name":"mcp__context7__query-docs","tool_input":{...},"error":"..."}
#   stdout: {"continue":true} (PostToolUseFailure hooks should never block)

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

# --- 6. Read current health JSON or initialize ---
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "1970-01-01T00:00:00Z")

if command -v jq >/dev/null 2>&1; then
  # Read existing or start with empty object
  if [ -f "$HEALTH_FILE" ]; then
    HEALTH_JSON=$(cat "$HEALTH_FILE" 2>/dev/null) || HEALTH_JSON="{}"
  else
    HEALTH_JSON="{}"
  fi
  # Get current fail_count
  CURRENT_COUNT=$(printf '%s' "$HEALTH_JSON" | jq -r ".\"${SERVER}\".fail_count // 0" 2>/dev/null) || CURRENT_COUNT=0
  NEW_COUNT=$((CURRENT_COUNT + 1))
  # Update JSON
  UPDATED=$(printf '%s' "$HEALTH_JSON" | jq --arg srv "$SERVER" --argjson cnt "$NEW_COUNT" --arg ts "$NOW" \
    '.[$srv] = {"fail_count": $cnt, "last_failure": $ts}' 2>/dev/null)
  if [ -n "$UPDATED" ]; then
    # Atomic write: temp file + mv
    _TMP_HF=$(mktemp "${HEALTH_FILE}.XXXXXX" 2>/dev/null) || _TMP_HF="${HEALTH_FILE}.tmp.$$"
    printf '%s' "$UPDATED" > "$_TMP_HF"
    mv -f "$_TMP_HF" "$HEALTH_FILE" 2>/dev/null || printf '%s' "$UPDATED" > "$HEALTH_FILE"
  fi
elif command -v python3 >/dev/null 2>&1; then
  python3 -c "
import json, os
health_file = '$HEALTH_FILE'
server = '$SERVER'
now = '$NOW'
try:
    if os.path.isfile(health_file):
        with open(health_file) as f:
            data = json.load(f)
    else:
        data = {}
except Exception:
    data = {}
entry = data.get(server, {'fail_count': 0, 'last_failure': ''})
entry['fail_count'] = entry.get('fail_count', 0) + 1
entry['last_failure'] = now
data[server] = entry
with open(health_file, 'w') as f:
    json.dump(data, f, separators=(',', ':'))
" 2>/dev/null
else
  # Minimal fallback: append to a simple key-value file
  # This is lossy but functional
  if [ -f "$HEALTH_FILE" ]; then
    CURRENT_COUNT=$(grep -o "\"${SERVER}\"[^}]*\"fail_count\"[[:space:]]*:[[:space:]]*[0-9]*" "$HEALTH_FILE" 2>/dev/null | grep -o '[0-9]*$') || CURRENT_COUNT=0
  else
    CURRENT_COUNT=0
  fi
  NEW_COUNT=$((CURRENT_COUNT + 1))
  # Write minimal JSON (overwrites — acceptable for grep-only environments)
  if [ -f "$HEALTH_FILE" ] && command -v sed >/dev/null 2>&1; then
    # Try to update in place; if server not found, append
    if grep -q "\"${SERVER}\"" "$HEALTH_FILE" 2>/dev/null; then
      # Replace the server entry (simplified: rewrite entire file via python-less approach)
      :
    fi
  fi
  # Fallback: just write/overwrite this server's entry as the whole file
  printf '{\"%s\":{\"fail_count\":%d,\"last_failure\":\"%s\"}}' "$SERVER" "$NEW_COUNT" "$NOW" > "$HEALTH_FILE"
fi

# --- 7. Always continue ---
emit_hook_continue
exit 0
