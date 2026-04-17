#!/bin/bash
# ai-symbiote PreToolUse hook: Block modifications to linter/formatter config files.
# Steers the agent to fix code instead of weakening configs.
#
# Created by JunyoungJung on 2026-04-16. Copyright © 2026 ai-symbiote.
#
# Principle: Silence on success — output ONLY when a config edit is blocked.
#
# Protocol:
#   stdin:  {"tool_name":"Edit","tool_input":{"file_path":"/path/to/file","old_string":"...","new_string":"..."}}
#   stdout: {"continue":false,"permissionDecision":"deny","systemMessage":"..."} to block
#           (empty or {"continue":true}) to approve

# Safety: never crash the agent workflow
trap 'exit 0' ERR
set +e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

# --- 1. Read stdin JSON ---
INPUT=$(read_stdin_safe)

# --- 2. Extract file_path from tool input (structured JSON parsing) ---
FILE_PATH=""
if command -v jq >/dev/null 2>&1; then
  FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null) || FILE_PATH=""
elif command -v python3 >/dev/null 2>&1; then
  FILE_PATH=$(echo "$INPUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("file_path",""))' 2>/dev/null) || FILE_PATH=""
else
  # Fallback: grep/sed (less safe but functional)
  FILE_PATH=$(echo "$INPUT" | grep -o '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"file_path"[[:space:]]*:[[:space:]]*"//' | sed 's/"$//') || FILE_PATH=""
fi

# --- 3. No file_path → continue ---
if [ -z "$FILE_PATH" ]; then
  emit_hook_continue
  exit 0
fi

# --- 4. Check override ---
if [ "${SYMBIOTE_ALLOW_CONFIG_EDIT:-}" = "1" ]; then
  emit_hook_continue
  exit 0
fi

# --- 5. Load protected patterns from manifest.json ---
STATE_DIR=$(get_state_dir)
MANIFEST_JSON=$(cat "$STATE_DIR/manifest.json" 2>/dev/null)
PROTECTED_CONFIGS=$(json_nested_field "$MANIFEST_JSON" "security" "protectedConfigs")

# --- 6. Default patterns if empty/missing ---
if [ -z "$PROTECTED_CONFIGS" ] || [ "$PROTECTED_CONFIGS" = "null" ]; then
  PROTECTED_CONFIGS=".swiftlint.yml .eslintrc .eslintrc.js .eslintrc.json .eslintrc.yaml .prettierrc .prettierrc.js .prettierrc.json biome.json tsconfig.json pyproject.toml"
fi

# --- 7. Extract basename ---
BASENAME=$(basename "$FILE_PATH")

# --- 8. Match basename against patterns ---
MATCHED=""
for pattern in $PROTECTED_CONFIGS; do
  # Direct match
  if [ "$BASENAME" = "$pattern" ]; then
    MATCHED="yes"
    break
  fi
done

# Wildcard match for eslintrc* and prettierrc* variants
if [ -z "$MATCHED" ]; then
  case "$BASENAME" in
    .eslintrc*) MATCHED="yes" ;;
    .prettierrc*) MATCHED="yes" ;;
  esac
fi

# --- 9. Block or continue ---
if [ -n "$MATCHED" ]; then
  emit_hook_block "[Config Protection] $BASENAME is protected. Fix the code instead of weakening the config. Override: set SYMBIOTE_ALLOW_CONFIG_EDIT=1"

  # Record to security-log.jsonl (escape file name for safe JSON)
  if [ -d "$STATE_DIR" ]; then
    ESCAPED_BASENAME=$(json_escape "$(basename "$FILE_PATH")")
    printf '{"v":2,"ts":"%s","type":"security","action":"blocked","category":"config_protection","file":"%s"}\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$ESCAPED_BASENAME" >> "$STATE_DIR/security-log.jsonl"
  fi
  exit 0
fi

emit_hook_continue
exit 0
