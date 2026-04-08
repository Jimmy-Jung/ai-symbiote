---
name: plan
description: Creates an implementation plan. Analyzes requirements and generates a step-by-step implementation plan.
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

Synapse reads Architect results and presents them to the user via EnterPlanMode.
After user approval, can transition to the implementation team.

## Principles

- Does not create a task-folder
- Does not save intermediate files (Scout/Architect results are used temporarily then discarded)
- All analysis and plans are for user approval
