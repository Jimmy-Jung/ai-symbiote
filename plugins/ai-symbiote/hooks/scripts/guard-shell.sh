#!/bin/bash
# ai-symbiote PreToolUse hook: Guard against dangerous shell commands.
# Blocks destructive git operations and other risky commands.
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

case "$COMMAND" in
  *"git push --force"*|*"git push -f "*)
    BLOCKED="Force push destroys remote history. Use --force-with-lease instead."
    ;;
  *"git reset --hard"*)
    BLOCKED="Hard reset permanently deletes uncommitted changes."
    ;;
  *"rm -rf /"*|*"rm -rf ~"*|*"rm -rf /*"*)
    BLOCKED="Deleting system or home directory is blocked."
    ;;
  *"git clean -fd"*)
    BLOCKED="git clean -fd permanently deletes untracked files."
    ;;
  *"git rebase -i"*|*"git rebase --interactive"*)
    BLOCKED="Interactive rebase is not supported in this terminal."
    ;;
  *"git add -i"*|*"git add --interactive"*)
    BLOCKED="Interactive add is not supported in this terminal."
    ;;
  *"rm -rf .git"*)
    BLOCKED="Deleting git repository is blocked. Run manually if intentional."
    ;;
  *"chmod -R 777"*)
    BLOCKED="chmod -R 777 grants excessive permissions. Specify appropriate permissions."
    ;;
  *"sudo rm"*|*"sudo chmod"*|*"sudo chown"*)
    BLOCKED="Filesystem changes via sudo are blocked. Run manually if needed."
    ;;
esac

CMD_LOWER=$(printf '%s' "$COMMAND" | tr '[:upper:]' '[:lower:]')
if [ -z "$BLOCKED" ]; then
  if printf '%s' "$CMD_LOWER" | grep -qE '(curl|wget)\s.*\|\s*(ba)?sh'; then
    BLOCKED="Piping remote scripts directly is a security risk. Download and review first."
  fi
fi

if [ -n "$BLOCKED" ]; then
  ESCAPED=$(json_escape "$BLOCKED")
  printf '{"continue":false,"permissionDecision":"deny","systemMessage":"[Guard] %s"}\n' "$ESCAPED"
  exit 0
fi

exit 0
