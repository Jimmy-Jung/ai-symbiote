#!/bin/bash
# ai-symbiote PostToolUse(Write|Edit) hook: Security guard for written files.
# Scans file content after write/edit for security anti-patterns.
#
# Author: JunyoungJung
# Date: 2026-04-14
#
# Principle: Silence on success — output ONLY when a security issue is detected.
# This hook WARNS but does not block (PostToolUse cannot block).
#
# Platform: Claude Code only (Codex CLI does not support Write/Edit PostToolUse matcher)
#
# Performance guardrails:
#   - File size > 100KB → skip
#   - Extension whitelist only
#   - Per-file timeout: 2 seconds
#   - Binary files auto-excluded
#
# Protocol:
#   stdin:  {"session_id":"...","tool_name":"Write|Edit","tool_input":{"file_path":"..."}}
#   stdout: {"continue":true,"systemMessage":"..."} when security issue found
#           (empty) on success

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

if [ -z "$FILE_PATH" ] || [ ! -f "$FILE_PATH" ]; then
  exit 0
fi

# --- 2. Extension whitelist check ---
FILE_EXT="${FILE_PATH##*.}"
FILE_EXT_LOWER=$(printf '%s' "$FILE_EXT" | tr '[:upper:]' '[:lower:]')
BASENAME=$(basename "$FILE_PATH")
BASENAME_LOWER=$(printf '%s' "$BASENAME" | tr '[:upper:]' '[:lower:]')

# Check if file is in extension whitelist or is a dotfile like .env
case "$BASENAME_LOWER" in
  .env|.env.*) ;; # Always scan .env files
  *)
    case "$FILE_EXT_LOWER" in
      js|ts|jsx|tsx|py|go|rb|swift|java|kt|rs|c|cpp|h|hpp) ;;
      yml|yaml|json|toml|xml|ini|cfg|conf) ;;
      sh|bash|zsh|fish) ;;
      dockerfile|makefile) ;;
      env) ;;
      *) exit 0 ;; # Skip non-whitelisted extensions
    esac
    ;;
esac

# --- 3. File size check (skip > 100KB) ---
FILE_SIZE=$(wc -c < "$FILE_PATH" 2>/dev/null | tr -d ' ')
if [ -z "$FILE_SIZE" ] || [ "$FILE_SIZE" -gt 102400 ] 2>/dev/null; then
  exit 0
fi

# --- 4. Binary file check ---
# Use "charset=binary" to detect true binary files. Avoid matching "executable" (catches scripts)
# or "data" alone (too broad). Match only patterns that indicate non-text content.
if file --mime "$FILE_PATH" 2>/dev/null | grep -q 'charset=binary'; then
  exit 0
fi

# --- 5. Read file content (with 2s timeout) ---
CONTENT=""
if command -v timeout >/dev/null 2>&1; then
  CONTENT=$(timeout 2 cat "$FILE_PATH" 2>/dev/null)
elif command -v gtimeout >/dev/null 2>&1; then
  CONTENT=$(gtimeout 2 cat "$FILE_PATH" 2>/dev/null)
else
  CONTENT=$(cat "$FILE_PATH" 2>/dev/null)
fi

if [ -z "$CONTENT" ]; then
  exit 0
fi

CONTENT_LOWER=$(printf '%s' "$CONTENT" | tr '[:upper:]' '[:lower:]')

# --- 6. Security pattern scanning ---
# NOTE: Use grep on $FILE_PATH directly to avoid shell quoting issues with printf.
WARNINGS=""
WARN_COUNT=0

# Pattern: Hardcoded secrets (secret-like variable names with long string values)
if grep -qiE '(api_key|api_secret|secret_key|access_key|private_key|auth_token|client_secret|database_url|db_password)\s*[:=]\s*.*[A-Za-z0-9_/+=]{16,}' "$FILE_PATH" 2>/dev/null; then
  WARNINGS="${WARNINGS}[SEC-W01/HIGH] Hardcoded secret detected in $BASENAME. Use environment variables instead.\n"
  WARN_COUNT=$((WARN_COUNT + 1))
fi

# Pattern: .env file with actual values (not placeholders)
case "$BASENAME_LOWER" in
  .env|.env.local|.env.production|.env.staging)
    if grep -qE '^[A-Z_]+=.{8,}' "$FILE_PATH" 2>/dev/null; then
      if ! grep -qiE '(your_|changeme|placeholder|example|xxx|TODO|REPLACE)' "$FILE_PATH" 2>/dev/null; then
        WARNINGS="${WARNINGS}[SEC-W02/CRITICAL] .env file contains real secret values. Ensure this file is in .gitignore.\n"
        WARN_COUNT=$((WARN_COUNT + 1))
      fi
    fi
    ;;
esac

# Pattern: SQL string concatenation (injection risk)
if grep -qiE "(select|insert|update|delete|drop)\s.*\+\s*(req\.|request\.|params\.|user|input|args)" "$FILE_PATH" 2>/dev/null; then
  WARNINGS="${WARNINGS}[SEC-W03/HIGH] SQL query with string concatenation detected. Use parameterized queries.\n"
  WARN_COUNT=$((WARN_COUNT + 1))
fi

# Pattern: innerHTML / dangerouslySetInnerHTML (XSS risk)
if grep -qE '(\.innerHTML\s*=|dangerouslySetInnerHTML|v-html\s*=)' "$FILE_PATH" 2>/dev/null; then
  WARNINGS="${WARNINGS}[SEC-W04/MEDIUM] innerHTML/dangerouslySetInnerHTML usage. Sanitize input to prevent XSS.\n"
  WARN_COUNT=$((WARN_COUNT + 1))
fi

# Pattern: Debug mode left enabled
if grep -qE '^\s*(DEBUG|VERBOSE|DEV_MODE)\s*[:=]\s*(true|1|yes|on)\b' "$FILE_PATH" 2>/dev/null; then
  WARNINGS="${WARNINGS}[SEC-W05/MEDIUM] Debug mode is enabled. Disable before deploying to production.\n"
  WARN_COUNT=$((WARN_COUNT + 1))
fi

# Pattern: eval/exec with variable input
if grep -qiE '\beval\s*\(' "$FILE_PATH" 2>/dev/null; then
  if grep -qE 'eval\s*\([^)]*(\$|req\.|request\.|params\.|user_|input)' "$FILE_PATH" 2>/dev/null; then
    WARNINGS="${WARNINGS}[SEC-W06/HIGH] eval() with dynamic input is a code injection risk.\n"
    WARN_COUNT=$((WARN_COUNT + 1))
  fi
fi

# --- 7. Output warnings ---
if [ "$WARN_COUNT" -gt 0 ]; then
  # Record to security-log.jsonl
  STATE_DIR=$(get_state_dir)
  if [ -d "$STATE_DIR" ]; then
    NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    SECURITY_LOG="$STATE_DIR/security-log.jsonl"
    ESCAPED_FILE=$(json_escape "$FILE_PATH")
    ESCAPED_WARNS=$(json_escape "$(printf '%b' "$WARNINGS")")
    printf '{"v":2,"ts":"%s","type":"security","category":"file_scan","file":"%s","warn_count":%d,"warnings":"%s","action":"warned","session_pid":"%s"}\n' \
      "$NOW" "$ESCAPED_FILE" "$WARN_COUNT" "$ESCAPED_WARNS" "$PPID" >> "$SECURITY_LOG" 2>/dev/null

    # --- 8. Enforce security-log.jsonl size limit (max 10,000 lines) ---
    if [ -f "$SECURITY_LOG" ]; then
      LOG_LINES=$(wc -l < "$SECURITY_LOG" | tr -d ' ')
      if [ "$LOG_LINES" -gt 10000 ]; then
        tail -8000 "$SECURITY_LOG" > "$SECURITY_LOG.tmp" 2>/dev/null && \
          mv "$SECURITY_LOG.tmp" "$SECURITY_LOG" 2>/dev/null
      fi
    fi
  fi

  MSG=$(printf '%b' "$WARNINGS" | tr '\n' ' ' | sed 's/  */ /g; s/ $//')
  emit_hook_notice "[Security] ${MSG}"
  exit 0
fi

exit 0
