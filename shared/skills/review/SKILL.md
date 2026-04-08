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
