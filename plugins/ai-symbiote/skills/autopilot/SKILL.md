---
name: autopilot
description: 4-Phase 워크플로우를 병렬 최대 성능으로 자동 실행합니다.
argument-hint: <task description>
user-invocable: true
allowed-tools: [Read, Write, Edit, Glob, Grep, Bash, Agent]
---

# Autopilot

synapse 오케스트레이터의 implementation 팀을 parallel-max 모드로 실행합니다.
독립 작업을 최대한 병렬로 처리하여 최대 성능을 발휘합니다.

## 팀 구성

- 팀 템플릿: `implementation`
- 모드: `parallel-max`
- maxIterations: 3
- completionLevel: 2

### 단계별 팀 투입

| Phase | 역할 | 수량 | 목적 |
|-------|------|------|------|
| Phase 0: Analyze | Scout | 2 (병렬) | 요구사항 분석 + 코드베이스 탐색 동시 진행 |
| Phase 1: Plan | Architect | 1 | Scout 결과 기반 구현 계획 + Builder 배분 |
| Phase 2: Execute | Builder | 최대 3 (병렬) | 병렬 가능 단계 동시 구현 |
| Phase 3: Verify | Inspector | 1 | 전체 구현 결과 통합 검증 |

### auto-loop과의 차이

- Builder 수를 최대화
- maxIterations가 3으로 제한
- Loop 실패 시 접근 방식 변경 후 재시도

### Loop 동작

- Inspector PASS → 완료
- Inspector FAIL + 반복 잔여 → 접근 변경 → Architect 재디스패치
- 3회 후 미해결 → 에스컬레이션

## 상태 디렉터리

`~/ai-symbiote/{slug}/state/{ISO8601-basic}_{task-name}/`

## 참조 스킬

synapse가 팀 구성 시 자동으로 참조합니다:

- `roles/SKILL.md`
- `team-templates/SKILL.md`
- `verify-loop/SKILL.md`
- `code-accuracy/SKILL.md`
- `~/ai-symbiote/{slug}/context.md`

## Post-Pipeline

- "커밋까지" 키워드 시 `git-commit` 스킬로 커밋 생성
- 완료 후 clean 워크플로우로 task-folder 정리 가능

## 메신저 브릿지 연동

auto-loop과 동일한 메신저 브릿지 프로토콜을 따릅니다.

요약:

1. 팀 구성 직후 `messenger/config.json` + `bot.pid` 확인
2. 각 Phase 시작 시 `messenger/commands/` 폴링
3. 에스컬레이션 시 `messenger/approvals/{id}_request.json` 작성
4. 완료 시 자동 알림 전송
