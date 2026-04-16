#!/bin/bash
# ai-symbiote PreToolUse hook: Block edits to files not yet read in this session.
# Forces the AI to read files before modifying them.
#
# Created by JunyoungJung on 2026-04-16. Copyright © 2026 ai-symbiote.
#
# Protocol:
#   stdin:  {"tool_name":"Edit","tool_input":{"file_path":"/path/to/file",...}}
#   stdout: {"continue":false,...} to block
#           {"continue":true,...} to approve

# Safety: never crash the agent workflow
trap 'exit 0' ERR
set +e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

# --- 1. Read stdin JSON ---
INPUT=$(cat)

# --- 2. Check disable flag ---
if [ "${SYMBIOTE_GATEGUARD:-}" = "0" ]; then
  emit_hook_continue
  exit 0
fi

# --- 3. Extract tool_name ---
TOOL_NAME=""
if command -v jq >/dev/null 2>&1; then
  TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null) || TOOL_NAME=""
elif command -v python3 >/dev/null 2>&1; then
  TOOL_NAME=$(echo "$INPUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_name",""))' 2>/dev/null) || TOOL_NAME=""
else
  TOOL_NAME=$(echo "$INPUT" | grep -o '"tool_name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"tool_name"[[:space:]]*:[[:space:]]*"//' | sed 's/"$//') || TOOL_NAME=""
fi

# --- 4. Extract file_path from tool_input ---
FILE_PATH=""
if command -v jq >/dev/null 2>&1; then
  FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null) || FILE_PATH=""
elif command -v python3 >/dev/null 2>&1; then
  FILE_PATH=$(echo "$INPUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("file_path",""))' 2>/dev/null) || FILE_PATH=""
else
  FILE_PATH=$(echo "$INPUT" | grep -o '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"file_path"[[:space:]]*:[[:space:]]*"//' | sed 's/"$//') || FILE_PATH=""
fi

# --- 5. No file_path → continue ---
if [ -z "$FILE_PATH" ]; then
  emit_hook_continue
  exit 0
fi

# --- 6. For Write tool: allow new file creation (file does not exist on disk) ---
if [ "$TOOL_NAME" = "Write" ] && [ ! -e "$FILE_PATH" ]; then
  emit_hook_continue
  exit 0
fi

# --- 7. Check session tracking file ---
SESSION_FILE=$(safe_session_file "symbiote-gateguard")

if grep -qxF "$FILE_PATH" "$SESSION_FILE" 2>/dev/null; then
  # File has been read → allow
  emit_hook_continue
  exit 0
fi

# --- 8. Block: file not read in this session ---
emit_hook_block "[GateGuard] Read $(basename "$FILE_PATH") first. The file must be read before editing to ensure changes are based on current state."

# --- 9. Record to harness-log.jsonl ---
STATE_DIR=$(get_state_dir)
if [ -d "$STATE_DIR" ]; then
  ESCAPED_FILE=$(json_escape "$FILE_PATH")
  printf '{"v":2,"ts":"%s","type":"gateguard_blocked","file":"%s","session_pid":"%s"}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$ESCAPED_FILE" "$$" >> "$STATE_DIR/harness-log.jsonl"
fi

exit 0
