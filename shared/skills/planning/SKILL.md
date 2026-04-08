---
name: planning
user-invocable: true
description: Development planning methodology for new feature planning, refactoring, and codebase structure analysis. This skill should be used when planning new features, refactoring, or analyzing codebase structure before implementation.
---

# Development Planning

A software development planning methodology applicable regardless of language/platform.

## Requirements Interview

Clarify goals with the following questions before implementation:

- What: What is being implemented/changed?
- Why: Why is it needed? What problem does it solve?
- How: Is there a preferred approach?
- Success criteria: When is it considered complete?

Do not guess; if ambiguous, confirm with the user.

## Required Information Gathering

### Technical Context
- Language: single language or hybrid
- Framework: UI/backend frameworks in use
- Architecture pattern: MVVM, Clean, MVC, Layered, etc.
- Dependency management: package.json, Package.swift, requirements.txt, build.gradle, etc.

### Existing Patterns
- How are similar features implemented?
- Naming conventions, file structure
- Test patterns

## Codebase Search Strategy

### Parallel Search
Use Grep and Glob simultaneously:

- Grep: exact type names, method names, import relationships
- Glob: file lists matching specific patterns (e.g., *Repository*, *ViewModel*)
- subagent(explorer): when broad codebase exploration is needed

### Search Targets
- Similar features: existing implementations for reference
- Naming conventions: class/function/file name rules
- Architecture patterns: layer structure, dependency direction
- Test patterns: existing test locations and structure

## Impact Assessment Matrix

| Item | Description | Verification Method |
|------|-------------|---------------------|
| Direct changes | Files to modify/add/delete | Trace references with Grep |
| Indirect impact | Dependent modules, calling code | Import analysis |
| Breaking change | API changes, signature changes | Full search of usage sites |
| Risk | Areas of potential unexpected impact | Boundary modules, external integrations |

## Implementation Plan Template

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

1. No guessing: Verify through codebase search.
2. Parallel exploration: Use Grep, Glob, etc. simultaneously.
3. Respect existing patterns: Follow existing patterns rather than creating new ones.
4. Step-by-step verification: Include verification means for each step.
5. Proactive risk identification: Identify risks before implementation.

## Role Injection: Architect

This section is injected into the prompt when the synapse orchestrator spawns an Architect sub-agent.

The Architect follows the requirements interview, required information gathering, impact assessment matrix, and implementation plan template above.
Read Scout result files to obtain codebase information, then create the implementation plan.
Clearly define work units to be allocated to Builders, and indicate whether parallel execution is possible.
Results must be written in markdown to the designated result file.
