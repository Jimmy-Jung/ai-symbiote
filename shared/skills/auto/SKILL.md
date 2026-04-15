---
name: auto
description: "Autonomous task execution. Two modes: auto (loop until done) and autopilot (max parallel). Triggers on: auto-loop, autonomous, autopilot, max performance, parallel."
argument-hint: <task description> [--mode autonomous|parallel-max]
user-invocable: true
allowed-tools: [Read, Write, Edit, Glob, Grep, Bash, Agent]
---

# Auto -- Autonomous Task Execution

**ADK Patterns:** Sequential Pipeline + Reflection + Retry/Fallback

Runs the synapse orchestrator's implementation team in autonomous mode.
Accepts a free-form task description and autonomously completes it.

**Two execution modes:**
- **autonomous** (default, formerly auto-loop): Loop until task completion. maxIterations: 10.
- **parallel-max** (formerly autopilot): Maximize parallelism for peak performance. maxIterations: 3.

For PRD-based headless autonomous execution, use the separate PRD/ralph integration workflow.

---

## Mode: autonomous (default)

### Team Composition

- Team template: `implementation`
- Mode: `autonomous`
- maxIterations: 10 (default, overridable in manifest.json)
- completionLevel: 2 (default)

### Phase-by-Phase Team Deployment

| Phase | Role | Count | Purpose |
|-------|------|-------|---------|
| Phase 0: Analyze | Scout | 1~2 (parallel) | Requirements analysis, codebase exploration |
| Phase 1: Plan | Architect | 1 | Implementation plan based on Scout results |
| Phase 2: Execute | Builder | 1~3 (parallel) | Implementation per Architect plan |
| Phase 3: Verify | Inspector | 1 | Verification of implementation results |

### Loop Behavior

- Inspector PASS -> Outside Voice 제안 -> Complete
- Inspector FAIL + iterations remaining -> Issue analysis -> Re-dispatch Builder
- Inspector FAIL + same error 2x -> Change approach -> Re-dispatch Architect
- Iteration limit reached -> Escalation

### Outside Voice (Phase 8)

Inspector PASS 후, Synapse Phase 8 Smart Activation 조건에 해당하면 Outside Voice를 제안한다.
조건: Inspector 결과에 warning 이상 항목이 있거나, 변경 파일 10개 이상이거나, 고복잡도 작업인 경우.
조건 미충족 시 Outside Voice를 건너뛰고 바로 Complete한다.

```text
[Auto] Inspector PASS - 작업이 완료되었습니다. (iteration {N}/{M})
Inspector가 warning 이상 {W}건을 감지했습니다.

완료 전 독립적인 외부 검토를 받아보시겠습니까?

1. 예 - Outside Voice 실행 후 완료
2. 아니오 - 바로 완료
3. 이 세션에서 묻지 않기
```

#### Outside Voice verdict에 따른 분기

- **agree** → Complete (추가 코멘트와 함께)
- **partially-disagree** → 사용자에게 충돌점 제시
  - 수정 선택 시: 새로운 iteration으로 Builder 재배포
  - 유지 선택 시: Complete
- **disagree** → 상세 Tension Report 제시
  - 근본적 접근법 변경 시: Architect부터 재시작
  - 유지 선택 시: Complete

#### maxOutsideVoiceRework 제한

Outside Voice disagree/partially-disagree로 인한 재작업은 maxIterations와 별도로 관리하되,
**최대 1회**로 제한한다 (`maxOutsideVoiceRework: 1`).

- 1회 재작업 후 다시 Outside Voice를 실행하지 않는다 (바로 Complete)
- 이는 무한 루프를 방지하면서도 사용자의 의도적 수정을 허용한다
- manifest.json에서 `maxOutsideVoiceRework` 값을 재정의할 수 있다 (기본값: 1)

---

## Mode: parallel-max

### Team Composition

- Team template: `implementation`
- Mode: `parallel-max`
- maxIterations: 3
- completionLevel: 2

### Phase-by-Phase Team Deployment

| Phase | Role | Count | Purpose |
|-------|------|-------|---------|
| Phase 0: Analyze | Scout | 2 (parallel) | Requirements analysis + codebase exploration simultaneously |
| Phase 1: Plan | Architect | 1 | Implementation plan based on Scout results + Builder allocation |
| Phase 2: Execute | Builder | up to 3 (parallel) | Parallel implementation of parallelizable steps |
| Phase 3: Verify | Inspector | 1 | Integrated verification of all implementation results |

### Differences from autonomous mode

- Maximizes Builder count
- maxIterations limited to 3
- On loop failure, changes approach and retries

### Loop Behavior

- Inspector PASS -> Outside Voice 제안 -> Complete
- Inspector FAIL + iterations remaining -> Change approach -> Re-dispatch Architect
- 3 failures unresolved -> Escalation

Outside Voice는 autonomous 모드와 동일한 Phase 8 흐름을 따른다.

---

## State Directory

`~/ai-symbiote/{slug}/state/{task-folder}/`

### Files Created at Initialization

- `ralph-state.md`: Loop state tracking
- `team-manifest.json`: Team composition and agent state
- `dispatch/`: Sub-agent requests
- `results/`: Sub-agent results
- `notepad.md`: Compaction-resistant notes

### ralph-state.md Initial Values

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

## Referenced Skills

Automatically referenced by synapse during team composition:

- `roles/SKILL.md`
- `team-templates/SKILL.md`
- `verify-loop/SKILL.md`
- `plan/SKILL.md`
- `code-accuracy/SKILL.md`
- `deep-search/SKILL.md`
- `~/ai-symbiote/{slug}/context.md`

## Escalation Rules

Halts the loop and asks the user in the following situations:

- maxIterations reached
- Same error 3 consecutive times
- Architecture/destructive change requires user approval
- Ambiguous requirements / additional information needed

## Messenger Bridge Integration

### Step 1.5: Messenger Check

- Check for `~/ai-symbiote/{slug}/messenger/config.json` existence
- If present, activate messenger notification mode
- Check `messenger/bot.pid`
- messenger-notify hook sends notification when `ralph-state.md` changes

### Command Polling at Iteration Start

1. Check for `*.json` files in `~/ai-symbiote/{slug}/messenger/commands/`
2. If a file with `"status": "pending"` exists, inject into current iteration
3. Rename to `.done` after processing

### Messenger Escalation

When messenger mode is active:

1. Write `~/ai-symbiote/{slug}/messenger/approvals/{id}_request.json`
2. Poll for response file
3. Branch based on `approve`, `reject`, `modify`, `timeout`

## Progress Report Format

```text
[Auto Progress] iteration N/M
- Task: {task-folder}
- Mode: [autonomous|parallel-max]
- Phase: [current phase]
- Team: {active agent list}
- Outside Voice: [pending|running|complete|skipped]
- Latest result: [summary]
- Remaining issues: [list]
- Next action: [dispatch|synthesize|outside-voice|escalate]
```

## Post-Pipeline

- On "commit too" keyword, create commit via `git-commit` skill

## Cleanup on Completion

- Set `active` to false and `phase` to complete in `ralph-state.md`
- Record final state in `team-manifest.json`
- Send completion notification if messenger mode is active
- Completed task-folders can be cleaned up via the clean workflow
