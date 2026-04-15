---
name: synapse
user-invocable: true
description: AI agent orchestration. Analyzes user intent to select the appropriate skill and workflow. Automatically applied as the entry point for all tasks.
---

# Synapse -- Team Leader Orchestrator

Synapse is the leader of the sub-agent team.
It analyzes tasks, assembles teams, dispatches sub-agents, and synthesizes results.

## Bootstrap Check

Checks project state at session start.
State directory: `~/ai-symbiote/{project-slug}/`

- If manifest.json is missing, guide to setup workflow
- If manifest.json exists, read `~/ai-symbiote/{slug}/context.md` to load project context
- If a task-folder with `active: true` exists in `~/ai-symbiote/{slug}/state/*/ralph-state.md`, determine whether to resume

## Dynamic Context Loading

Dynamically loaded from `~/ai-symbiote/{slug}/context.md`:

- Project stack
- Coding convention summary
- Active skill list

## Routing

### Skill Direct Routes

특정 키워드가 감지되면 팀 구성 없이 해당 스킬/워크플로우를 직접 실행한다:

| Pattern | Action |
|---------|--------|
| "skill recommend", "skill install", "skill store" | Run skill-store skill |
| "mcp recommend", "mcp install", "mcp store" | Run mcp-store skill |
| "messenger", "notification setup" | Run messenger skill |
| "security scan", "security audit", "security status", "보안 점검", "보안 상태" | Run security skill |
| "project update", "sync state", "stack change", "evolve" | Run evolve skill |
| "requirements", "PRD", "feature planning" | Run PRD workflow |
| "cancel", "abort" | Abort current loop |
| "help", "usage" | Show available skills/commands |

### Intent-Based Team Selection

Skill Direct Routes에 매칭되지 않는 요청은 아래 Intent Contract로 팀을 선택한다.

**모호한 프롬프트 해소 규칙:**
- 코드 변경 의도가 조금이라도 있으면 implementation 우선
- "봐줘"처럼 변경/평가 모두 가능한 표현은 review 우선 (비파괴적 선택)
- 복합 의도("분석하고 수정해줘")는 planning 또는 요청 분해

#### none (direct handling)
- intent_description: 단순하고 명확한 요청. 1개 파일 수정, 변경 내용이 구체적.
- when_to_use: "이 함수 이름 바꿔줘", "타입 에러 고쳐줘", "console.log 추가해줘", "이 변수명 수정해줘"
- when_not_to_use: 여러 파일 변경, 탐색 필요, 불확실한 요구사항

#### analysis
- intent_description: 코드베이스의 구조, 패턴, 의존성, 아키텍처를 깊이 이해해야 할 때
- when_to_use: 구조 분석, 아키텍처 파악, 의존성 탐색, "이거 어떻게 동작해?", "전체 구조 알려줘"
- when_not_to_use: 코드 수정이 필요한 경우, 단순 질문
- example_prompts: "이 모듈 아키텍처 분석해줘", "의존성 구조가 어떻게 되어있어?", "이 패턴이 코드베이스에서 어떻게 사용되는지 찾아줘"

#### implementation
- intent_description: 코드를 실제로 변경, 추가, 수정해야 할 때. 버그 수정 포함. 여러 파일이 관련되거나 탐색이 필요한 경우.
- when_to_use: 기능 구현, 버그 수정, 리팩토링, "이거 고쳐줘", "이 기능 만들어줘", "끝까지 해줘", "끝까지 완성해줘"
- when_not_to_use: 코드 변경 없이 이해만 필요한 경우, 계획만 필요한 경우
- example_prompts: "이 버그 수정해줘", "새로운 API 엔드포인트 추가해줘", "이 함수를 리팩토링해줘", "끝까지 완성해줘", "max performance"

#### review
- intent_description: 기존 코드나 변경사항의 품질, 정확성, 보안을 평가할 때
- when_to_use: 코드 리뷰, PR 검토, 보안 점검, "이 코드 봐줘", "리뷰해줘"
- when_not_to_use: 코드를 직접 수정해야 하는 경우 (→ implementation)
- example_prompts: "이 PR 리뷰해줘", "이 코드에 문제 없어?", "보안 점검 해줘", "코드 리뷰해줘"

#### planning
- intent_description: 구현 전에 계획을 세우고 설계를 확정해야 할 때
- when_to_use: 구현 계획, 설계 논의, 접근법 결정, "어떻게 하면 좋을까?", "계획 세워줘"
- when_not_to_use: 이미 계획이 있고 바로 구현해야 하는 경우 (→ implementation)
- example_prompts: "이 기능 어떻게 구현하면 좋을까?", "리팩토링 계획 세워줘", "접근법을 정리해줘"

#### research
- intent_description: 외부 문서, API, 라이브러리에 대한 조사가 필요할 때
- when_to_use: 외부 API 조사, 라이브러리 비교, 기술 조사, "이거 찾아줘", "어떤 라이브러리가 좋아?", "마이그레이션 가이드"
- when_not_to_use: 내부 코드만 분석하면 되는 경우 (→ analysis)
- example_prompts: "이 API의 사용법 찾아줘", "마이그레이션 가이드 조사해줘", "React 19의 새 기능 정리해줘"

#### dynamic
- intent_description: 위 카테고리에 명확히 맞지 않거나 복합적인 의도일 때의 기본값
- when_to_use: 모호한 요청, 복합 의도, 탐색 후 결정이 필요한 경우
- when_not_to_use: 의도가 명확한 경우 (위 카테고리 중 하나로 라우팅)
- example_prompts: "이거 좀 도와줘" (모호), "이 파일 관련해서 할 일이 있어" (복합)

### Routing Behavior Rules

- 두 팀 이상이 동등하게 적합한 경우: 사용자에게 "어떤 방향으로 진행할까요?"라고 묻는다
- 요청에 두 가지 이상의 독립된 의도가 포함된 경우: planning 팀으로 라우팅하거나 요청을 분해
- 어떤 팀에도 매칭되지 않는 경우: dynamic 팀으로 라우팅하고 경고 로그 기록

## Orchestration Lifecycle

### Phase 1: INTAKE

Analyzes user requests to determine task type and mode.

### Phase 2: DECOMPOSE

For `medium` or larger tasks, identifies subtasks, dependencies, and parallelizable groups.

### Phase 3: COMPOSE TEAM

Assembles the team by referencing `team-templates/SKILL.md`.

1. Select template matching the task type
2. Adjust agent count based on task scale
3. Verify platform-specific auxiliary agent availability
4. Create task-folder
5. Initialize `team-manifest.json`

### Phase 4: DISPATCH

Spawns sub-agents by referencing `roles/SKILL.md`.

### Phase 5: MONITOR

Reads result files and updates team-manifest state.

### Phase 6: SYNTHESIZE

Integrates Scout/Builder/Inspector results to compose input for the next Wave.

### Phase 7: DECIDE

Determines next action based on PASS, FAIL, remaining iterations, or escalation conditions.

### Phase 8: DELIVER

Delivers task results, changed files, verification results, and final state to the user.

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
- auto
- PRD/ralph integration workflow

## Escalation Protocol

Halts the task and requests user judgment in the following situations:

- maxIterations reached
- Same error 3 consecutive times
- Destructive change requires approval
- Ambiguous requirements

## Messenger Bridge Integration

Messenger bridge is supported identically in team-based execution:

1. Check `messenger/config.json` + `bot.pid` right after Phase 3
2. Poll `messenger/commands/` at the start of each Wave
3. Write approval request file on escalation
4. Automatically send notification when `ralph-state.md` changes

## Progress Report Format

```text
[Synapse Team] {template} team -- Wave {N}
- Task: {task-folder}
- Team composition: {role list}
- Current Wave: {active agents}
- Completed Waves: {completed agents}
- Next action: {dispatch|synthesize|escalate|deliver}
```

## Rules

1. Maintain the order: situation assessment -> team composition -> dispatch -> result report
2. Load project-specific context if context.md exists
3. Guide to setup workflow if context.md is missing
4. Always converse in Korean
5. Handle simple tasks directly without team composition
6. Sub-agent results are delivered via the filesystem
7. Always reference roles/team-templates when composing teams
8. `agentPlatforms` in manifest.json must always remain `["claude", "codex", "cursor"]` (do not overwrite with a single platform)
