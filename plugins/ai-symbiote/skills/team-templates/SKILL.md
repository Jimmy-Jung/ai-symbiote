---
name: team-templates
description: "Team composition templates. Referenced by the synapse orchestrator when composing subagent teams based on task types. Defines 6 templates: analysis, implementation, review, planning, research, dynamic."
user-invocable: false
---

# Team Templates

Templates referenced by the synapse orchestrator for composing optimal teams by task type.
Each template defines role placement, phase ordering, parallelization rules, and result synthesis strategy.

## Template: analysis

**ADK Patterns:** Parallel Fan-Out/Gather + Hierarchical

Deep analysis team. Explores the codebase from multiple angles and produces structured analysis results.

### Team Composition

| Order | Role | Count | Execution | Purpose |
|-------|------|-------|-----------|---------|
| Wave 1 | Scout | 2-3 | Parallel | Gather information with different exploration strategies |
| Wave 2 | Architect | 1 | Sequential | Synthesize Scout results into structured analysis |

### Parallelization Rules
- Wave 1: Scouts are assigned different search strategies and run in parallel
  - Scout-001: Grep-based exact matching (symbols, imports)
  - Scout-002: Glob-based file pattern exploration (structure, naming)
  - Scout-003: subagent(explorer)-based deep exploration (optional, for complex analysis)
- Wave 2: Architect runs after all Scouts complete

### Outside Voice Wave (Optional)

| Order | Role | Count | Execution | Purpose |
|-------|------|-------|-----------|---------|
| Wave 3 | Challenger | 1 | Sequential | Challenge analysis conclusions and assumptions |

- Trigger: After Wave 2 (Architect synthesis) completes; proposed to user per Synapse Phase 8
- Focus: Evidence sufficiency for the analysis, missed code patterns/dependencies, alternative interpretations

### Result Synthesis
The orchestrator reads the Architect's result file and reports to the user.
If Outside Voice was executed, Challenger's findings are appended as a separate section.

### Applicable Skills
- analyze workflow
- "deep analysis", "deep dive" natural language triggers

---

## Template: implementation

**ADK Patterns:** Sequential Pipeline + Reflection + Retry/Fallback

Implementation team. Handles the full process from analysis through implementation to verification.
Executes the auto 4-Phase pipeline on a team basis.

### Team Composition

| Order | Role | Count | Execution | Purpose |
|-------|------|-------|-----------|---------|
| Phase 0: Analyze | Scout | 1-2 | Parallel | Requirements analysis, codebase exploration |
| Phase 1: Plan | Architect | 1 | Sequential | Implementation plan based on Scout results |
| Phase 2: Execute | Builder | 1-3 | Parallel (independent steps) | Code implementation per Architect plan |
| Phase 3: Verify | Inspector | 1 | Sequential | Verify implementation results |

### Parallelization Rules
- Phase 0: Scouts run in parallel (requirements analysis + codebase exploration)
- Phase 1: Architect runs after collecting Scout results
- Phase 2: Steps marked as parallelizable by the Architect are assigned to separate Builders
- Phase 3: Inspector runs after all Builders complete

### Codex Integration (Optional)

When Codex is available, the implementation team utilizes it as follows:

| Situation | Codex Deployment |
|-----------|-----------------|
| Builder repeats same error twice | Deploy Codex as Builder replacement (second opinion from different model) |
| Inspector FAIL + unknown cause | Codex rescue for root cause diagnosis |
| Phase 3 Verify | Run Inspector and Codex review in parallel (dual verification) |
| Security review needed (Level 4) | Add Codex adversarial-review |

If Codex is unavailable, skip this section and proceed with Claude agents only.

### Outside Voice Phase (Optional)

| Order | Role | Count | Execution | Purpose |
|-------|------|-------|-----------|---------|
| Phase 4 | Challenger | 1 | Sequential | Independent review of completed implementation |

- Trigger: After Phase 3 (Inspector) PASS; proposed to user per Synapse Phase 8
- Focus: Alternative implementation approaches, performance/security/maintainability concerns, missed edge cases, architectural consistency
- Note: Distinct from the Codex Integration error-recovery deployment. Outside Voice is an independent review of completed, passing work.

### Mode Variants

#### autonomous mode (auto)
- Loop enabled: return to Phase 2 on Inspector FAIL
- maxIterations: 10 (default, overridable in manifest.json)
- completionLevel: 2 (default)
- Escalation: maxIterations reached, same error 3 times, destructive changes
- Codex deployment: automatic on 2 repeated errors (if available)

#### parallel-max mode (auto --mode parallel-max)
- Maximize Builder count (as many as independent steps)
- maxIterations: 3
- On loop failure, change approach and retry
- Codex deployment: immediate Codex rescue on first failure (if available)

### Result Synthesis
The orchestrator reads each Phase's results and decides whether to proceed to the next Phase.
On Inspector FAIL: issue analysis -> fix plan -> Builder redispatch.

### Applicable Skills
- auto (autonomous mode, default)
- auto --mode parallel-max (parallel-max mode)
- "to completion", "max performance" natural language triggers

---

## Template: review

**ADK Patterns:** Parallel Fan-Out/Gather + Multi-Agent Collaboration

Review team. Verifies code changes from multiple perspectives.

### Team Composition

| Order | Role | Count | Execution | Purpose |
|-------|------|-------|-----------|---------|
| Wave 1 | Scout | 1 | Sequential | Gather context around changes |
| Wave 2 | Inspector | 2-3 | Parallel | Review from different perspectives |

### Parallelization Rules
- Wave 1: Scout collects related code, dependencies, and tests for changed files
- Wave 2: Inspectors are assigned different review perspectives and run in parallel
  - Inspector-001: Code quality (readability, complexity, duplication)
  - Inspector-002: Pattern compliance (architecture, naming, conventions)
  - Inspector-003: Potential bugs + performance (null references, boundary conditions, N+1)
  - (if manifest.json enableSecurityReview = true) Inspector-004: Security review

### Codex Integration (Optional)

When Codex is available, the review team utilizes it as follows:

- Run `Skill(skill: "codex:review")` in parallel with Inspectors -> Claude + Codex dual review
- On security review request, add `Skill(skill: "codex:adversarial-review")` -> adversarial perspective review
- Combine Codex review results (JSON verdict) with Inspector results

If Codex is unavailable, review with Inspectors only.

### Outside Voice Wave (Optional)

| Order | Role | Count | Execution | Purpose |
|-------|------|-------|-----------|---------|
| Wave 3 | Challenger | 1 | Sequential | Cross-model adversarial review of completed review |

- Trigger: After Wave 2 (Inspectors) complete and results are aggregated; proposed to user per Synapse Phase 8
- Focus: Re-verification of "pass" items agreed by Inspectors, review blind spots, cross-cutting concerns
- Note: Distinct from the Codex Integration parallel dual review. Codex review runs in parallel with Inspector during Wave 2, whereas Outside Voice runs independently after all reviews complete.

### Result Synthesis
The orchestrator aggregates all Inspector + Codex results into a unified review report.
Sort by severity: critical > warning > suggestion.
Mark Codex findings with "[Codex]" source tag for distinction.
If Outside Voice was executed, Challenger's findings are appended with "[Outside Voice]" source tag.

### Applicable Skills
- review workflow

---

## Template: planning

**ADK Patterns:** Sequential Pipeline + Planning (Plan-and-Execute)

Planning team. Creates actionable plans before implementation.

### Team Composition

| Order | Role | Count | Execution | Purpose |
|-------|------|-------|-----------|---------|
| Wave 1 | Scout | 2 | Parallel | Codebase structure + similar implementation exploration |
| Wave 2 | Architect | 1 | Sequential | Detailed plan based on Scout results |

### Parallelization Rules
- Wave 1: Scouts run in parallel (structure exploration + similar pattern search)
- Wave 2: Architect runs after collecting Scout results

### Outside Voice Wave (Optional)

| Order | Role | Count | Execution | Purpose |
|-------|------|-------|-----------|---------|
| Wave 3 | Challenger | 1 | Sequential | Challenge plan assumptions and propose alternatives |

- Trigger: After Wave 2 (Architect plan) completes; Outside Voice is proposed before presenting the plan to the user
- Focus: Validity of plan premises, whether a simpler approach exists, adequacy of risk assessment, missing implementation steps, alternative architectures

### Result Synthesis
The orchestrator presents the Architect's result to the user via EnterPlanMode.
If Outside Voice was executed, Challenger's findings are included alongside the plan.
Can transition to the implementation team after user approval.

### Applicable Skills
- planning workflow

---

## Template: research

**ADK Patterns:** Parallel Fan-Out/Gather + Routing

Research team. Combines external information with internal codebase information.

### Team Composition

| Order | Role | Count | Execution | Purpose |
|-------|------|-------|-----------|---------|
| Wave 1 | Scout + Researcher | 2-4 | Parallel | Internal exploration + external research simultaneously |
| Wave 2 | Architect | 1 | Sequential | Synthesize internal/external results into report |

### Parallelization Rules
- Wave 1: Scout (codebase) and Researcher (external docs/APIs) run in parallel
- Wave 2: Architect synthesizes after all results are collected

### Outside Voice
Outside Voice is disabled by default in the research template. Run only when the user explicitly requests it.

### Applicable Skills
- "investigate", "research", "migration" natural language triggers

---

## Template: dynamic

**ADK Patterns:** Routing + ReAct (Tool-Using)

Dynamic team. For tasks that do not match any template above, synapse composes the team directly.

### Composition Rules
1. Always start with 1 Scout (understand the codebase)
2. Read Scout results and add additional roles as needed
3. Maintain max 5 agents limit
4. Use prompt templates from roles/SKILL.md when deploying each role

### Decision Tree
```
Scout result analysis
├─ Code change needed → Deploy Builder
├─ Planning needed → Deploy Architect
├─ Verification needed → Deploy Inspector
├─ External information needed → Deploy Researcher
└─ Further exploration needed → Deploy additional Scout
```

### Outside Voice
Outside Voice is disabled by default in the dynamic template. Run only when the user explicitly requests it.

---

## Common Protocols

### team-manifest.json

All teams create `team-manifest.json` in the task-folder to track team state.

```json
{
  "taskId": "{task-folder}",
  "template": "{template-name}",
  "phase": "{current-phase}",
  "agents": [
    {
      "id": "scout-001",
      "role": "scout",
      "model": "sonnet",
      "status": "complete",
      "resultPath": "results/scout-001.result.md"
    }
  ],
  "outsideVoice": {
    "offered": false,
    "accepted": false,
    "platform": null,
    "provider": null,
    "degraded": false,
    "status": "not-applicable",
    "resultPath": null,
    "tensionReportPath": null,
    "verdict": null,
    "tensionCount": 0,
    "adoptedCount": 0,
    "rejectedCount": 0,
    "reworkTriggered": false
  },
  "decisions": [
    {
      "timestamp": "ISO8601",
      "decision": "Decided to deploy 3 Builders in parallel based on Scout results"
    }
  ]
}
```

### Escalation
When an unresolvable situation arises within the team, the orchestrator escalates to the user.
If the messenger bridge is active, escalation occurs via messenger.
(Details: messenger bridge integration section of auto/SKILL.md)

### Result File Cleanup
After team completion, result files are preserved in the task-folder.
Can be cleaned up via the clean workflow.
