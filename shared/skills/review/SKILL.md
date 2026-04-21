---
name: review
description: Runs a code review on current changes.
argument-hint: [file or directory]
user-invocable: true
allowed-tools: [Read, Glob, Grep, Bash, Agent]
---

# Review

Assembles the synapse orchestrator's review team to perform a code review.

## Team Composition

- Team template: `review`

### Phase-by-Phase Team Deployment

| Order | Role | Count | Purpose |
|-------|------|-------|---------|
| Wave 1 | Scout | 1 | Collect related code, dependencies, and tests for changed files |
| Wave 2 | Inspector | 2~3 (parallel) | Review from different perspectives |

### Inspector Allocation Strategy
- Inspector-001: Code quality (readability, complexity, duplication)
- Inspector-002: Pattern compliance (architecture, naming, conventions)
- Inspector-003: Potential bugs + performance (null references, boundary conditions, N+1)
- Inspector-004: Security review (when manifest.json enableSecurityReview = true)

## Change Collection

- Check changes with `git diff --staged` and `git diff`
- If a file/directory is specified as argument, review only that scope

## Result Report

Synapse aggregates all Inspector results into a unified review report:
- Sorted by severity: Critical > Warning > Suggestion
- Each item includes file path and line number
- Includes fix suggestions

## Outside Voice Option

After all Inspector reviews finish and the aggregated report is produced, propose Outside Voice per Synapse Phase 8.

### Trigger conditions

Propose based on Synapse Phase 8 Smart Activation criteria.
Auto-propose only when review results contain `severity: warning` or higher items AND the overall verdict is PASS.
If every item is `suggestion` or lower, skip Outside Voice and explain why.

### Prompt template (render in user's locale)

```text
[Review Complete] Review finished.
- Critical: {N} / Warning: {M} / Suggestion: {K}

Detected {M+N} warning-or-higher items.
Run independent cross-model verification?
```

### Review-specific Outside Voice prompt

When Outside Voice runs, pass the Challenger:
- The full aggregated Inspector review results
- A request to re-verify areas the Inspectors marked PASS
- A cross-model check focused on security, performance, and architecture perspectives

### Result integration

Append Outside Voice output as a separate section of the existing review report:

```markdown
## Outside Voice Review ({provider})
- Verdict: {agree/partially-disagree/disagree}
- Additional findings:
  - [{severity}] {finding} ({file:line})
- Challenged items from original review:
  - {item}: {challenge rationale}
```
