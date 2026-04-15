---
name: plan
description: Creates an implementation plan. Analyzes requirements and generates a step-by-step implementation plan. This skill should be used when planning new features, refactoring, or analyzing codebase structure before implementation.
argument-hint: <task description>
user-invocable: true
allowed-tools: [Read, Glob, Grep, Bash, Agent]
---

# Plan

Assembles the synapse orchestrator's planning team to create an implementation plan.

## Team Composition

- Team template: `planning`

### Phase-by-Phase Team Deployment

| Order | Role | Count | Purpose |
|-------|------|-------|---------|
| Wave 1 | Scout | 2 (parallel) | Codebase structure + similar implementation search |
| Wave 2 | Architect | 1 | Detailed plan based on Scout results |

### Scout Allocation Strategy
- Scout-001: Codebase structure exploration (architecture, layers, dependencies)
- Scout-002: Similar feature/pattern search (existing implementations for reference)

## Plan Presentation

Synapse reads Architect results and, before presenting to the user via EnterPlanMode,
offers an Outside Voice review of the plan.

### Outside Voice Option (Phase 8)

Architect 결과가 완성된 후, 사용자에게 계획을 제시하기 전에 Outside Voice를 제안한다.

```text
[Plan Ready] 구현 계획이 준비되었습니다.

계획을 바로 보시겠습니까, 아니면 먼저 독립적인 외부 모델의
검토를 받아보시겠습니까?

1. Outside Voice 검토 후 계획 확인
2. 바로 계획 확인
```

### Planning 특화 Outside Voice 프롬프트

Outside Voice 실행 시, Challenger에게 다음을 포커스:
- 계획의 전제 조건 검증
- 빠진 단계 식별
- 리스크 평가 적절성
- 대안 접근법 제시
- Builder 할당 전략의 효율성

### 결과 통합

Outside Voice 결과가 있으면, EnterPlanMode에서 함께 제시:

```markdown
## 계획 (Architect)
{original plan}

## 독립 검토 (Outside Voice - {provider})
{outside voice feedback}

## 충돌점
{tension items if any}
```

After user approval, can transition to the implementation team.

## Planning Methodology

### Requirements Interview

Clarify goals with the following questions before implementation:

- What: What is being implemented/changed?
- Why: Why is it needed? What problem does it solve?
- How: Is there a preferred approach?
- Success criteria: When is it considered complete?

Do not guess; if ambiguous, confirm with the user.

### Required Information Gathering

#### Technical Context
- Language: single language or hybrid
- Framework: UI/backend frameworks in use
- Architecture pattern: MVVM, Clean, MVC, Layered, etc.
- Dependency management: package.json, Package.swift, requirements.txt, build.gradle, etc.

#### Existing Patterns
- How are similar features implemented?
- Naming conventions, file structure
- Test patterns

### Codebase Search Strategy

#### Parallel Search
Use Grep and Glob simultaneously:

- Grep: exact type names, method names, import relationships
- Glob: file lists matching specific patterns (e.g., *Repository*, *ViewModel*)
- subagent(explorer): when broad codebase exploration is needed

#### Search Targets
- Similar features: existing implementations for reference
- Naming conventions: class/function/file name rules
- Architecture patterns: layer structure, dependency direction
- Test patterns: existing test locations and structure

### Impact Assessment Matrix

| Item | Description | Verification Method |
|------|-------------|---------------------|
| Direct changes | Files to modify/add/delete | Trace references with Grep |
| Indirect impact | Dependent modules, calling code | Import analysis |
| Breaking change | API changes, signature changes | Full search of usage sites |
| Risk | Areas of potential unexpected impact | Boundary modules, external integrations |

### Implementation Plan Template

```
Goal
  - Clearly defined achievement objective

Impact Analysis
  - Direct change targets
  - Indirect impact scope
  - Breaking change assessment

Steps
  1. [Step name] - [Dependencies] - [Verification method]
  2. ...

Risks
  - Anticipated risks and mitigation strategies

Verification Plan
  - How to confirm completion
```

## Principles

- Does not create a task-folder
- Does not save intermediate files (Scout/Architect results are used temporarily then discarded)
- All analysis and plans are for user approval
- No guessing: Verify through codebase search.
- Parallel exploration: Use Grep, Glob, etc. simultaneously.
- Respect existing patterns: Follow existing patterns rather than creating new ones.
- Step-by-step verification: Include verification means for each step.
- Proactive risk identification: Identify risks before implementation.

## Role Injection: Architect

This section is injected into the prompt when the synapse orchestrator spawns an Architect sub-agent.

The Architect follows the requirements interview, required information gathering, impact assessment matrix, and implementation plan template above.
Read Scout result files to obtain codebase information, then create the implementation plan.
Clearly define work units to be allocated to Builders, and indicate whether parallel execution is possible.
Results must be written in markdown to the designated result file.
