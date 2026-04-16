#!/bin/bash
# ai-symbiote PostToolUse hook: Track read files for GateGuard.
# Records file paths from Read tool calls to a session-scoped tracking file.
#
# Created by JunyoungJung on 2026-04-16. Copyright © 2026 ai-symbiote.

# Safety: never crash the agent workflow
trap 'exit 0' ERR
set +e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

# --- 1. Read stdin JSON ---
INPUT=$(cat)

# --- 2. Extract file_path from tool_input ---
FILE_PATH=""
if command -v jq >/dev/null 2>&1; then
  FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null) || FILE_PATH=""
elif command -v python3 >/dev/null 2>&1; then
  FILE_PATH=$(echo "$INPUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("file_path",""))' 2>/dev/null) || FILE_PATH=""
else
  FILE_PATH=$(echo "$INPUT" | grep -o '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"file_path"[[:space:]]*:[[:space:]]*"//' | sed 's/"$//') || FILE_PATH=""
fi

# --- 3. No file_path → continue ---
if [ -z "$FILE_PATH" ]; then
  emit_hook_continue
  exit 0
fi

# --- 4. Record to session tracking file ---
SESSION_FILE=$(safe_session_file "symbiote-gateguard")
echo "$FILE_PATH" >> "$SESSION_FILE"

# --- 5. Always continue (passive tracker, never blocks) ---
emit_hook_continue
exit 0
