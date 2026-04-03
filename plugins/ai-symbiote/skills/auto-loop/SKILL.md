---
name: auto-loop
description: "완료까지 멈추지 않는 세션 내 자율 실행 루프를 시작합니다. Analyze->Plan->Execute->Verify를 반복하여 작업을 자율 완료합니다. Triggers on: 끝까지, 완료할 때까지, 멈추지 마, auto-loop, autonomous, 자율 실행."
argument-hint: <task description>
user-invocable: true
allowed-tools: [Read, Write, Edit, Glob, Grep, Bash, Agent]
---

# Auto Loop -- 세션 내 자율 실행

synapse 오케스트레이터의 implementation 팀을 autonomous 모드로 실행합니다.
자유 형식의 작업 설명을 받아 자율적으로 완료합니다.

PRD 기반 헤드리스 자율 실행은 별도 PRD/ralph 연동 워크플로우를 사용하세요.

## 팀 구성

synapse의 오케스트레이션 라이프사이클에 따라 implementation 팀을 구성합니다.
팀 템플릿과 역할 정의는 synapse가 자동으로 참조합니다.

- 팀 템플릿: `implementation`
- 모드: `autonomous`
- maxIterations: 10 (기본값, manifest.json에서 오버라이드 가능)
- completionLevel: 2 (기본값)

### 단계별 팀 투입

| Phase | 역할 | 수량 | 목적 |
|-------|------|------|------|
| Phase 0: Analyze | Scout | 1~2 (병렬) | 요구사항 분석, 코드베이스 탐색 |
| Phase 1: Plan | Architect | 1 | Scout 결과 기반 구현 계획 |
| Phase 2: Execute | Builder | 1~3 (병렬) | Architect 계획에 따른 구현 |
| Phase 3: Verify | Inspector | 1 | 구현 결과 검증 |

### Loop 동작

- Inspector PASS → 완료
- Inspector FAIL + 반복 잔여 → 이슈 분석 → Builder 재디스패치
- Inspector FAIL + 동일 오류 2회 → 접근 방식 변경 → Architect 재디스패치
- 반복 한도 도달 → 에스컬레이션

## 상태 디렉터리

`~/ai-symbiote/{slug}/state/{task-folder}/`

### 초기화 시 생성 파일

- `ralph-state.md`: 루프 상태 추적
- `team-manifest.json`: 팀 구성 및 에이전트 상태
- `dispatch/`: 서브에이전트 요청
- `results/`: 서브에이전트 결과
- `notepad.md`: compaction 내성 메모

### ralph-state.md 초기값

```markdown
# Ralph State

- active: true
- iteration: 0
- maxIterations: 10
- phase: analyze
- taskDescription: ...
- completionLevel: 2
- startedAt: {ISO8601}
```

## 참조 스킬

synapse가 팀 구성 시 자동으로 참조합니다:

- `roles/SKILL.md`
- `team-templates/SKILL.md`
- `verify-loop/SKILL.md`
- `planning/SKILL.md`
- `code-accuracy/SKILL.md`
- `deep-search/SKILL.md`
- `~/ai-symbiote/{slug}/context.md`

## 에스컬레이션 규칙

다음 상황에서 루프를 중단하고 사용자에게 질문합니다:

- maxIterations 도달
- 동일 오류 3회 연속
- 아키텍처/파괴적 변경이 사용자 승인 필요
- 요구사항 모호/추가 정보 필요

## 메신저 브릿지 연동

### Step 1.5: 메신저 확인

- `~/ai-symbiote/{slug}/messenger/config.json` 존재 여부 확인
- 존재하면 메신저 알림 모드 활성화
- `messenger/bot.pid` 확인
- `ralph-state.md` 변경 시 messenger-notify 훅이 알림을 전송

### 반복 시작 시 명령 폴링

1. `~/ai-symbiote/{slug}/messenger/commands/` 내 `*.json` 파일 확인
2. `"status": "pending"` 인 파일이 있으면 현재 반복에 주입
3. 처리 완료 후 `.done`으로 rename

### 메신저 에스컬레이션

메신저 모드가 활성화되어 있으면:

1. `~/ai-symbiote/{slug}/messenger/approvals/{id}_request.json` 작성
2. 응답 파일 폴링
3. `approve`, `reject`, `modify`, `timeout`에 따라 분기

## 진행 보고 형식

```text
[Auto Loop 진행] iteration N/M
- Task: {task-folder}
- Phase: [현재 단계]
- 팀: {활성 에이전트 목록}
- 최근 결과: [요약]
- 남은 이슈: [목록]
- 다음 조치: [dispatch|synthesize|escalate]
```

## 완료 시 정리

- `ralph-state.md`의 `active`를 false, `phase`를 complete로 변경
- `team-manifest.json` 최종 상태 기록
- 메신저 모드 활성 시 완료 알림 전송
- 완료된 task-folder는 clean 워크플로우로 정리 가능
