---
name: analyze
description: Performs deep analysis on a target.
argument-hint: <analysis target>
user-invocable: true
allowed-tools: [Read, Glob, Grep, Bash, Agent]
---

# Analyze

Assembles the synapse orchestrator's analysis team to perform deep analysis on a target.

## Team Composition

- Team template: `analysis`

### Phase-by-Phase Team Deployment

| Order | Role | Count | Purpose |
|-------|------|-------|---------|
| Wave 1 | Scout | 2~3 (parallel) | Information gathering with different strategies |
| Wave 2 | Architect | 1 | Synthesize Scout results into structured analysis |

### Scout Allocation Strategy
- Scout-001: Grep-based exact matching (symbols, imports, type references)
- Scout-002: Glob-based file pattern exploration (structure, naming conventions)
- Scout-003: subagent(explorer) deep exploration (selectively deployed for complex analysis)

## Analysis Result Structure

The Architect organizes analysis results in the following structure:
- Missing Questions
- Scope Risks
- Unvalidated Assumptions
- Edge Cases
- Recommendations

## Handoff

After analysis is complete, suggests planning workflow for plan creation if needed.
