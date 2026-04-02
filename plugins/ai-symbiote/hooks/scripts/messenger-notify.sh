#!/bin/bash
# ai-symbiote PostToolUse hook: 메신저 알림 트리거
# ralph-state.md가 쓰여질 때 상태 변경을 감지하여 notification JSON을 작성한다.
#
# Author: JunyoungJung
# Date: 2026-04-02

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

INPUT=$(cat)

STATE_DIR=$(get_state_dir)
MESSENGER_DIR="$STATE_DIR/messenger"
NOTIFY_DIR="$MESSENGER_DIR/notifications"

# 메신저 설정이 없으면 스킵
[ -f "$MESSENGER_DIR/config.json" ] || exit 0

# 봇이 실행 중이 아니면 스킵
if [ -f "$MESSENGER_DIR/bot.pid" ]; then
  BOT_PID=$(cat "$MESSENGER_DIR/bot.pid" 2>/dev/null)
  if [ -n "$BOT_PID" ] && ! kill -0 "$BOT_PID" 2>/dev/null; then
    exit 0
  fi
else
  exit 0
fi

# 쓰여진 파일 경로 확인
TOOL_INPUT=$(json_field "$INPUT" "tool_input")
FILE_PATH=""

# Write 도구: file_path 필드
FILE_PATH=$(printf '%s' "$INPUT" | grep -o '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"file_path"[[:space:]]*:[[:space:]]*"//' | sed 's/"$//')

# ralph-state.md가 아니면 스킵
case "$FILE_PATH" in
  *ralph-state.md) ;;
  *) exit 0 ;;
esac

# ralph-state.md 파싱
[ -f "$FILE_PATH" ] || exit 0

ACTIVE=$(grep -o 'active: [a-z]*' "$FILE_PATH" | head -1 | awk '{print $2}')
PHASE=$(grep -o 'phase: [a-z]*' "$FILE_PATH" | head -1 | awk '{print $2}')
ITERATION=$(grep -o 'iteration: [0-9]*' "$FILE_PATH" | head -1 | awk '{print $2}')
MAX_ITER=$(grep -o 'maxIterations: [0-9]*' "$FILE_PATH" | head -1 | awk '{print $2}')
TASK_DESC=$(grep 'taskDescription:' "$FILE_PATH" | head -1 | sed 's/- taskDescription:[[:space:]]*//')

# task-folder 이름 추출
TASK_FOLDER=$(basename "$(dirname "$FILE_PATH")")

# 이전 상태 캐시 파일과 비교
CACHE_FILE="$MESSENGER_DIR/.ralph-state-cache"
PREV_PHASE=""
PREV_ACTIVE=""
if [ -f "$CACHE_FILE" ]; then
  PREV_PHASE=$(grep 'phase:' "$CACHE_FILE" 2>/dev/null | awk '{print $2}')
  PREV_ACTIVE=$(grep 'active:' "$CACHE_FILE" 2>/dev/null | awk '{print $2}')
fi

# 현재 상태를 캐시에 저장
printf "phase: %s\nactive: %s\niteration: %s\n" "$PHASE" "$ACTIVE" "$ITERATION" > "$CACHE_FILE"

# 이벤트 결정
EVENT=""
SUMMARY=""

if [ "$ACTIVE" = "true" ] && [ -z "$PREV_ACTIVE" ]; then
  EVENT="loop_start"
  SUMMARY="루프가 시작되었습니다"
elif [ "$ACTIVE" = "false" ] && [ "$PREV_ACTIVE" = "true" ]; then
  if [ "$PHASE" = "complete" ]; then
    EVENT="loop_complete"
    SUMMARY="작업이 완료되었습니다"
  elif [ "$PHASE" = "cancelled" ]; then
    EVENT="loop_complete"
    SUMMARY="작업이 취소되었습니다"
  else
    EVENT="error"
    SUMMARY="루프가 비정상 종료되었습니다"
  fi
elif [ "$PHASE" != "$PREV_PHASE" ] && [ -n "$PREV_PHASE" ]; then
  EVENT="phase_change"
  SUMMARY="단계가 ${PREV_PHASE}에서 ${PHASE}(으)로 전환됨"
fi

# 이벤트가 없으면 스킵
[ -n "$EVENT" ] || exit 0

# 알림 디렉터리 확인
mkdir -p "$NOTIFY_DIR" 2>/dev/null

# 타임스탬프 생성 (파일명 안전)
TS=$(date -u +"%Y-%m-%dT%H-%M-%S")

# notification JSON 작성
ESCAPED_SUMMARY=$(json_escape "$SUMMARY")
ESCAPED_TASK_DESC=$(json_escape "$TASK_DESC")
ESCAPED_TASK_FOLDER=$(json_escape "$TASK_FOLDER")

cat > "$NOTIFY_DIR/${TS}_${EVENT}.json" <<ENDJSON
{
  "event": "${EVENT}",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "taskFolder": "${ESCAPED_TASK_FOLDER}",
  "data": {
    "iteration": ${ITERATION:-0},
    "maxIterations": ${MAX_ITER:-10},
    "phase": "${PHASE}",
    "summary": "${ESCAPED_SUMMARY}",
    "taskDescription": "${ESCAPED_TASK_DESC}"
  }
}
ENDJSON

# Claude Code hook 프로토콜: 정상 계속
printf '{"continue":true}\n'
exit 0
