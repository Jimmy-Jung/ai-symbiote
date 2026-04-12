---
name: auto
description: "Autonomous task execution. Two modes: auto (loop until done) and autopilot (max parallel). Triggers on: auto-loop, autonomous, autopilot, max performance, parallel."
argument-hint: <task description> [--mode autonomous|parallel-max]
user-invocable: true
allowed-tools: [Read, Write, Edit, Glob, Grep, Bash, Agent]
---

# Auto -- Autonomous Task Execution

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

- Inspector PASS -> Complete
- Inspector FAIL + iterations remaining -> Issue analysis -> Re-dispatch Builder
- Inspector FAIL + same error 2x -> Change approach -> Re-dispatch Architect
- Iteration limit reached -> Escalation

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

- Inspector PASS -> Complete
- Inspector FAIL + iterations remaining -> Change approach -> Re-dispatch Architect
- 3 failures unresolved -> Escalation

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
- Latest result: [summary]
- Remaining issues: [list]
- Next action: [dispatch|synthesize|escalate]
```

## Post-Pipeline

- On "commit too" keyword, create commit via `git-commit` skill

## Cleanup on Completion

- Set `active` to false and `phase` to complete in `ralph-state.md`
- Record final state in `team-manifest.json`
- Send completion notification if messenger mode is active
- Completed task-folders can be cleaned up via the clean workflow
