---
name: autopilot
description: Automatically executes the 4-Phase workflow at maximum parallel performance.
argument-hint: <task description>
user-invocable: true
allowed-tools: [Read, Write, Edit, Glob, Grep, Bash, Agent]
---

# Autopilot

Runs the synapse orchestrator's implementation team in parallel-max mode.
Processes independent tasks in maximum parallelism for peak performance.

## Team Composition

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

### Differences from auto-loop

- Maximizes Builder count
- maxIterations limited to 3
- On loop failure, changes approach and retries

### Loop Behavior

- Inspector PASS -> Complete
- Inspector FAIL + iterations remaining -> Change approach -> Re-dispatch Architect
- 3 failures unresolved -> Escalation

## State Directory

`~/ai-symbiote/{slug}/state/{ISO8601-basic}_{task-name}/`

## Referenced Skills

Automatically referenced by synapse during team composition:

- `roles/SKILL.md`
- `team-templates/SKILL.md`
- `verify-loop/SKILL.md`
- `code-accuracy/SKILL.md`
- `~/ai-symbiote/{slug}/context.md`

## Post-Pipeline

- On "commit too" keyword, create commit via `git-commit` skill
- Completed task-folders can be cleaned up via the clean workflow

## Messenger Bridge Integration

Follows the same messenger bridge protocol as auto-loop.

Summary:

1. Check `messenger/config.json` + `bot.pid` right after team composition
2. Poll `messenger/commands/` at the start of each Phase
3. Write `messenger/approvals/{id}_request.json` on escalation
4. Send automatic notification on completion
