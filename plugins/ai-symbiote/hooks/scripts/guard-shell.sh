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
    BLOCKED="force push는 원격 히스토리를 파괴합니다. --force-with-lease를 사용하세요."
    ;;
  *"git reset --hard"*)
    BLOCKED="hard reset은 커밋되지 않은 변경사항을 영구 삭제합니다."
    ;;
  *"rm -rf /"*|*"rm -rf ~"*|*"rm -rf /*"*)
    BLOCKED="시스템 또는 홈 디렉터리 삭제는 차단됩니다."
    ;;
  *"git clean -fd"*)
    BLOCKED="git clean -fd는 추적되지 않는 파일을 영구 삭제합니다."
    ;;
  *"git rebase -i"*|*"git rebase --interactive"*)
    BLOCKED="인터랙티브 rebase는 터미널에서 지원되지 않습니다."
    ;;
  *"git add -i"*|*"git add --interactive"*)
    BLOCKED="인터랙티브 add는 터미널에서 지원되지 않습니다."
    ;;
  *"rm -rf .git"*)
    BLOCKED="Git 저장소 삭제는 차단됩니다. 의도적이라면 수동으로 실행하세요."
    ;;
  *"chmod -R 777"*)
    BLOCKED="chmod -R 777은 과도한 권한을 부여합니다. 적절한 권한을 지정하세요."
    ;;
  *"sudo rm"*|*"sudo chmod"*|*"sudo chown"*)
    BLOCKED="sudo를 사용한 파일 시스템 변경은 차단됩니다. 수동으로 실행하세요."
    ;;
esac

CMD_LOWER=$(printf '%s' "$COMMAND" | tr '[:upper:]' '[:lower:]')
if [ -z "$BLOCKED" ]; then
  if printf '%s' "$CMD_LOWER" | grep -qE '(curl|wget)\s.*\|\s*(ba)?sh'; then
    BLOCKED="원격 스크립트 직접 실행은 보안 위험이 있습니다. 먼저 다운로드 후 검토하세요."
  fi
fi

if [ -n "$BLOCKED" ]; then
  ESCAPED=$(json_escape "$BLOCKED")
  printf '{"continue":false,"permissionDecision":"deny","systemMessage":"[Guard] %s"}\n' "$ESCAPED"
  exit 0
fi

exit 0
