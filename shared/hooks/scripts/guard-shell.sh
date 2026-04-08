#!/bin/bash
# ai-symbiote PreToolUse hook: Guard against dangerous shell commands.
# Blocks destructive git operations and other risky commands.
#
# Principle: Silence on success — output ONLY when a command is blocked.
#
# Claude Code hook protocol:
#   stdin:  {"session_id":"...","cwd":"...","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"..."}}
#   stdout: {"continue":false,"permissionDecision":"deny","systemMessage":"..."} to block
#           (empty or {"continue":true}) to approve

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

INPUT=$(cat)

COMMAND=$(json_nested_field "$INPUT" "tool_input" "command")

if [ -z "$COMMAND" ]; then
  exit 0
fi

BLOCKED=""
WORKAROUND=""

case "$COMMAND" in
  *"git push --force"*|*"git push -f "*)
    BLOCKED="Force push destroys remote history."
    WORKAROUND="git push --force-with-lease"
    ;;
  *"git reset --hard"*)
    BLOCKED="Hard reset permanently deletes uncommitted changes."
    WORKAROUND="git stash"
    ;;
  *"rm -rf /"*|*"rm -rf ~"*|*"rm -rf /*"*)
    BLOCKED="Deleting system or home directory is blocked."
    WORKAROUND=""
    ;;
  *"git clean -fd"*)
    BLOCKED="git clean -fd permanently deletes untracked files."
    WORKAROUND="git clean -fdn (dry-run first)"
    ;;
  *"git rebase -i"*|*"git rebase --interactive"*)
    BLOCKED="Interactive rebase is not supported in this terminal."
    WORKAROUND="git rebase <branch> (non-interactive)"
    ;;
  *"git add -i"*|*"git add --interactive"*)
    BLOCKED="Interactive add is not supported in this terminal."
    WORKAROUND="git add <specific-files>"
    ;;
  *"rm -rf .git"*)
    BLOCKED="Deleting git repository is blocked."
    WORKAROUND="Run manually if intentional"
    ;;
  *"chmod -R 777"*)
    BLOCKED="chmod -R 777 grants excessive permissions."
    WORKAROUND="chmod 755 <target>"
    ;;
  *"sudo rm"*|*"sudo chmod"*|*"sudo chown"*)
    BLOCKED="Filesystem changes via sudo are blocked."
    WORKAROUND="Run manually if needed"
    ;;
esac

CMD_LOWER=$(printf '%s' "$COMMAND" | tr '[:upper:]' '[:lower:]')
if [ -z "$BLOCKED" ]; then
  if printf '%s' "$CMD_LOWER" | grep -qE '(curl|wget)\s.*\|\s*(ba)?sh'; then
    BLOCKED="Piping remote scripts directly is a security risk."
    WORKAROUND="Download file first, then review before executing"
  fi
fi

if [ -n "$BLOCKED" ]; then
  # Build message with workaround
  if [ -n "$WORKAROUND" ]; then
    MSG="Blocked: ${BLOCKED} Workaround: ${WORKAROUND}. Note: verify this matches your intent."
  else
    MSG="Blocked: ${BLOCKED}"
  fi
  ESCAPED=$(json_escape "$MSG")
  printf '{"continue":false,"permissionDecision":"deny","systemMessage":"[Guard] %s"}\n' "$ESCAPED"

  # Record blocked event to harness-log.jsonl
  STATE_DIR=$(get_state_dir)
  if [ -d "$STATE_DIR" ]; then
    HARNESS_LOG="$STATE_DIR/harness-log.jsonl"
    NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    ESC_CMD=$(json_escape "$COMMAND")
    ESC_WA=$(json_escape "$WORKAROUND")
    printf '{"v":2,"ts":"%s","error_type":"guard_blocked","command":"%s","workaround":"%s","session_pid":"%s"}\n' \
      "$NOW" "$ESC_CMD" "$ESC_WA" "$PPID" >> "$HARNESS_LOG" 2>/dev/null
  fi
  exit 0
fi

exit 0
