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

- Inspector PASS -> Propose Outside Voice -> Complete
- Inspector FAIL + iterations remaining -> Issue analysis -> Re-dispatch Builder
- Inspector FAIL + same error 2x -> Change approach -> Re-dispatch Architect
- Iteration limit reached -> Escalation

### Outside Voice (Phase 8)

After Inspector PASS, propose Outside Voice if Synapse Phase 8 Smart Activation conditions are met.
Conditions: Inspector results contain warning-or-higher items, or 10+ changed files, or a high-complexity task.
When conditions are not met, skip Outside Voice and complete directly.

Prompt template (render in user's locale; Korean shown as example):

```text
[Auto] Inspector PASS - work is complete. (iteration {N}/{M})
Inspector detected {W} warning-or-higher items.

Run an independent external review before completing?

1. Yes - run Outside Voice, then complete
2. No - complete now
3. Don't ask again this session
```

#### Branching by Outside Voice verdict

- **agree** → Complete (append the reviewer's comment)
- **partially-disagree** → Surface the conflict to the user
  - If they choose to revise: start a new iteration by re-dispatching Builder
  - If they choose to keep the work: Complete
- **disagree** → Present a detailed Tension Report
  - If fundamental approach change is chosen: restart from Architect
  - If they choose to keep the work: Complete

#### maxOutsideVoiceRework limit

Rework triggered by Outside Voice disagree/partially-disagree is tracked
separately from maxIterations and capped at **1 pass** (`maxOutsideVoiceRework: 1`).

- After one rework cycle, do not run Outside Voice again (complete directly)
- This prevents infinite loops while still allowing the user's intentional revisions
- The `maxOutsideVoiceRework` value can be overridden in manifest.json (default: 1)

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

- Inspector PASS -> Propose Outside Voice -> Complete
- Inspector FAIL + iterations remaining -> Change approach -> Re-dispatch Architect
- 3 failures unresolved -> Escalation

Outside Voice follows the same Phase 8 flow as in autonomous mode.

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
