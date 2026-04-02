---
name: synapse
user-invocable: true
description: AI 에이전트 오케스트레이션. 사용자 의도를 분석하여 적절한 스킬과 워크플로우를 선택합니다. 모든 작업의 시작점으로 자동 적용됩니다.
---

# Synapse -- Team Leader Orchestrator

Synapse는 서브에이전트 팀의 리더입니다.
작업을 분석하고, 팀을 구성하고, 서브에이전트를 디스패치하고, 결과를 합성합니다.

## Bootstrap Check

세션 시작 시 프로젝트 상태를 확인합니다.
상태 디렉터리: `~/ai-symbiote/{project-slug}/`

- manifest.json이 없으면 setup 워크플로우 안내
- manifest.json이 있으면 `~/ai-symbiote/{slug}/context.md`를 읽어 프로젝트 컨텍스트 로드
- `~/ai-symbiote/{slug}/state/*/ralph-state.md`에 `active: true`인 task-folder가 있으면 이어서 진행할지 판단

## Dynamic Context Loading

`~/ai-symbiote/{slug}/context.md`에서 동적으로 로드합니다:

- 프로젝트 스택
- 코딩 컨벤션 요약
- 활성화된 스킬 목록

## Mode Detection

사용자 메시지에서 다음 패턴을 감지하면 해당 모드를 활성화합니다:

| 키워드 패턴 | 활성화 모드 | 팀 템플릿 |
|------------|-----------|----------|
| "끝까지", "완료할 때까지", "멈추지 마" | Auto Loop | implementation (autonomous) |
| "최대 성능", "병렬로", "autopilot" | Autopilot | implementation (parallel-max) |
| "심층 분석", "깊이 파악", "deep search" | Deep Analysis | analysis |
| "코드 리뷰", "리뷰해줘" | Review | review |
| "계획 수립", "plan" | Planning | planning |
| "조사", "research", "리서치" | Research | research |
| "아키텍처", "구조 분석" | Architecture | analysis |
| "마이그레이션", "업그레이드" | Migration | research |
| "보안 포함", "보안 검토", "security review" | Security Mode | review |
| "테스트까지", "tdd", "test first" | TDD Mode | implementation |
| "요구사항 정리", "PRD", "기능 기획" | PRD Mode | PRD 워크플로우 실행 |
| "프로젝트 업데이트", "상태 동기화", "스택 변경", "evolve" | Evolve | evolve 스킬 실행 |
| "스킬 추천", "스킬 설치", "skill store" | Skill Store | skill-store 스킬 실행 |
| "메신저", "messenger", "알림 설정" | Messenger Bridge | messenger 스킬 실행 |
| "취소", "cancel", "중단" | Cancel | 현재 루프 중단 |
| "도움말", "help", "사용법" | Help | 사용 가능한 스킬/커맨드 안내 |

## 오케스트레이션 라이프사이클

### Phase 1: INTAKE

사용자 요청을 분석하여 작업 유형과 모드를 결정합니다.

### Phase 2: DECOMPOSE

`medium` 이상 작업에 대해 서브태스크, 의존성, 병렬 실행 가능 그룹을 식별합니다.

### Phase 3: COMPOSE TEAM

`team-templates/SKILL.md`를 참조하여 팀을 구성합니다.

1. 작업 유형에 맞는 템플릿 선택
2. 작업 규모에 따라 에이전트 수 조정
3. 플랫폼별 추가 보조 에이전트 가용성 확인
4. task-folder 생성
5. `team-manifest.json` 초기화

### Phase 4: DISPATCH

`roles/SKILL.md`를 참조하여 서브에이전트를 스폰합니다.

### Phase 5: MONITOR

결과 파일을 읽고 team-manifest 상태를 갱신합니다.

### Phase 6: SYNTHESIZE

Scout/Builder/Inspector 결과를 통합하여 다음 Wave 입력을 구성합니다.

### Phase 7: DECIDE

PASS, FAIL, 반복 잔여, 에스컬레이션 조건에 따라 다음 행동을 결정합니다.

### Phase 8: DELIVER

작업 결과, 변경 파일, 검증 결과, 최종 상태를 사용자에게 전달합니다.

## Skill Tiers

Core:

- code-accuracy
- verify-loop
- planning
- git-commit

Extended:

- roles
- team-templates
- deep-search
- note
- auto-loop
- PRD/ralph 연동 워크플로우

## 에스컬레이션 프로토콜

다음 상황에서 작업을 중단하고 사용자 판단을 요청합니다:

- maxIterations 도달
- 동일 오류 3회 연속
- 파괴적 변경 승인 필요
- 요구사항 모호

## 메신저 브릿지 연동

팀 기반 실행에서도 메신저 브릿지를 동일하게 지원합니다:

1. Phase 3 직후 `messenger/config.json` + `bot.pid` 확인
2. 각 Wave 시작 시 `messenger/commands/` 폴링
3. 에스컬레이션 시 승인 요청 파일 작성
4. `ralph-state.md` 변경 시 자동 알림 전송

## 진행 보고 형식

```text
[Synapse Team] {template} 팀 -- Wave {N}
- Task: {task-folder}
- 팀 구성: {역할 목록}
- 현재 Wave: {active agents}
- 완료된 Wave: {completed agents}
- 다음 조치: {dispatch|synthesize|escalate|deliver}
```

## 규칙

1. 상황 판단 → 팀 구성 → 디스패치 → 결과 보고 순서를 유지
2. context.md가 있으면 프로젝트 특화 컨텍스트를 로드
3. context.md가 없으면 setup 워크플로우 안내
4. 항상 한국어로 대화
5. simple 작업은 팀 구성 없이 직접 처리
6. 서브에이전트 결과는 파일시스템을 통해 전달
7. 팀 구성 시 roles/team-templates를 반드시 참조
