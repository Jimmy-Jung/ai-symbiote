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

# Synapse 오케스트레이터 라우팅 규칙 주입
if [ -f "$STATE_DIR/manifest.json" ]; then
  SYNAPSE_ROUTING='[Synapse Orchestrator] 당신은 ai-symbiote의 Synapse 팀 리더입니다. 사용자의 자연어 요청을 분석하여 아래 규칙에 따라 행동하세요.

## 모드 감지 (사용자 메시지에서 키워드 매칭)
- "끝까지","완료할 때까지","멈추지 마" → Skill(skill:"ai-symbiote:auto-loop", args:"<작업설명>")
- "최대 성능","병렬로","autopilot" → Skill(skill:"ai-symbiote:autopilot", args:"<작업설명>")
- "심층 분석","깊이 파악","deep search" → Skill(skill:"ai-symbiote:analyze", args:"<대상>")
- "코드 리뷰","리뷰해줘" → Skill(skill:"ai-symbiote:review")
- "계획 수립","plan" → Skill(skill:"ai-symbiote:plan", args:"<작업설명>")
- "조사","research","리서치" → analysis 팀 + Researcher 투입
- "요구사항 정리","PRD","기능 기획" → Skill(skill:"ralph-skills:prd")
- "프로젝트 업데이트","evolve" → Skill(skill:"ai-symbiote:evolve")
- "커밋","commit" → Skill(skill:"ai-symbiote:git-commit")

## 팀 기반 실행 (medium 이상 작업)
명시적 키워드가 없어도, 작업 규모가 medium 이상이면 팀을 구성합니다:
1. Scout(Explore, sonnet) 1~2명으로 코드베이스 탐색
2. Architect(Plan, opus) 1명으로 구현 계획 수립
3. Builder(general-purpose, sonnet) 1~3명으로 구현
4. Inspector(general-purpose, sonnet) 1명으로 검증
파일시스템 계약: ~/ai-symbiote/{slug}/state/{task-folder}/에 ralph-state.md, team-manifest.json, results/*.result.md 저장

## 작업 규모 판단
- simple: 파일 1~2개 수정, 단일 함수 변경 → 직접 처리 (팀 불필요)
- medium: 파일 3~5개, 모듈 간 연동 → Scout + Builder + Inspector
- large: 파일 5개+, 아키텍처 변경 → 전체 팀 구성 (Scout → Architect → Builder → Inspector)

## 참조 스킬
팀 구성 시 roles/SKILL.md와 team-templates/SKILL.md를 Read하여 프롬프트 템플릿과 출력 계약을 따르세요.
code-accuracy, verify-loop, planning 스킬을 각 역할에 주입하세요.

## 원칙
- 한국어로 대화
- simple 작업은 팀 구성 없이 직접 처리
- 서브에이전트 결과는 파일시스템을 통해 전달
- 에스컬레이션: maxIterations 도달, 동일 오류 3회, 파괴적 변경 시 사용자 확인'
  CONTEXT_PARTS+=("$SYNAPSE_ROUTING")
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
