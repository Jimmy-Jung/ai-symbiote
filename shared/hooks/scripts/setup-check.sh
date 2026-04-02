#!/bin/bash
# ai-symbiote SessionStart hook: Check project bootstrap status.
# Checks ~/ai-symbiote/{slug}/ for manifest and interrupted Ralph loops.
#
# Codex hook protocol:
#   stdout: {"continue":true,"systemMessage":"..."} for context injection

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

cat > /dev/null

STATE_DIR=$(get_state_dir)
CONTEXT_PARTS=()

if [ ! -f "$STATE_DIR/manifest.json" ]; then
  CONTEXT_PARTS+=("[Symbiote] manifest.json이 없습니다. setup 명령으로 프로젝트를 초기화하세요.")
fi

if [ -d "$STATE_DIR/state" ]; then
  for state_dir in "$STATE_DIR/state"/*/; do
    [ -d "$state_dir" ] || continue
    if [ -f "${state_dir}ralph-state.md" ]; then
      ACTIVE=$(grep -o 'active: true' "${state_dir}ralph-state.md" 2>/dev/null)
      if [ -n "$ACTIVE" ]; then
        TASK_NAME=$(basename "$state_dir")
        CONTEXT_PARTS+=("[Symbiote] Ralph Loop '${TASK_NAME}'이 중단되었습니다. ralph 연동으로 재개하거나 clean 워크플로우로 정리하세요.")
      fi
    fi
  done
fi

if [ -f "$STATE_DIR/context.md" ]; then
  CONTEXT_CONTENT=$(cat "$STATE_DIR/context.md" 2>/dev/null | head -50)
  if [ -n "$CONTEXT_CONTENT" ]; then
    CONTEXT_PARTS+=("[Symbiote Context] $CONTEXT_CONTENT")
  fi
fi

# 메신저 브릿지: pending 명령 확인
MESSENGER_CMD_DIR="$STATE_DIR/messenger/commands"
if [ -d "$MESSENGER_CMD_DIR" ]; then
  for cmd_file in "$MESSENGER_CMD_DIR"/*.json; do
    [ -f "$cmd_file" ] || continue
    CMD_STATUS=$(json_field "$(cat "$cmd_file")" "status")
    if [ "$CMD_STATUS" = "pending" ]; then
      CMD_TYPE=$(json_field "$(cat "$cmd_file")" "command")
      CMD_ARGS=""
      if command -v jq >/dev/null 2>&1; then
        CMD_ARGS=$(jq -r '.args | to_entries | map(.value) | join(", ")' "$cmd_file" 2>/dev/null)
      else
        CMD_ARGS=$(grep -o '"instruction"[[:space:]]*:[[:space:]]*"[^"]*"' "$cmd_file" | head -1 | sed 's/.*"instruction"[[:space:]]*:[[:space:]]*"//' | sed 's/"$//')
        [ -z "$CMD_ARGS" ] && CMD_ARGS=$(grep -o '"task"[[:space:]]*:[[:space:]]*"[^"]*"' "$cmd_file" | head -1 | sed 's/.*"task"[[:space:]]*:[[:space:]]*"//' | sed 's/"$//')
      fi
      ESCAPED_CMD=$(json_escape "[Messenger] 메신저 커맨드 수신: ${CMD_TYPE} - ${CMD_ARGS}")
      CONTEXT_PARTS+=("$ESCAPED_CMD")
    fi
  done
fi

# 메신저 브릿지: 미처리 승인 응답 확인
MESSENGER_APR_DIR="$STATE_DIR/messenger/approvals"
if [ -d "$MESSENGER_APR_DIR" ]; then
  for resp_file in "$MESSENGER_APR_DIR"/*_response.json; do
    [ -f "$resp_file" ] || continue
    RESP_ID=$(json_field "$(cat "$resp_file")" "id")
    RESP_DECISION=$(json_field "$(cat "$resp_file")" "decision")
    RESP_COMMENT=$(json_field "$(cat "$resp_file")" "comment")
    CONTEXT_PARTS+=("[Messenger] 승인 응답 수신: ${RESP_ID} - 결정: ${RESP_DECISION}, 코멘트: ${RESP_COMMENT}")
  done
fi

if [ ${#CONTEXT_PARTS[@]} -gt 0 ]; then
  JOINED=""
  for part in "${CONTEXT_PARTS[@]}"; do
    if [ -n "$JOINED" ]; then
      JOINED="$JOINED | $part"
    else
      JOINED="$part"
    fi
  done
  ESCAPED=$(json_escape "$JOINED")
  printf '{"continue":true,"systemMessage":"%s"}\n' "$ESCAPED"
else
  printf '{"continue":true}\n'
fi

exit 0
