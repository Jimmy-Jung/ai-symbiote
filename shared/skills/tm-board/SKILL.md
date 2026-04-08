---
name: tm-board
description: "Displays a summary of the task graph grouped by status."
argument-hint: "--tag <tag> --status <status>"
user-invocable: true
allowed-tools: [Read, Bash, Glob]
---

# TM Board

Displays a summary of the task graph grouped by status.

## State Directory

`~/ai-symbiote/{slug}/taskmaster/`

## Output Items

- Total number of tasks
- Count per status (pending, in_progress, review, done, blocked)
- Current `currentTaskId`
- List of `blocked` tasks
- Actionable `pending` candidates

## Behavior

1. Reads `~/ai-symbiote/{slug}/taskmaster/tasks.json`.
2. Reads `~/ai-symbiote/{slug}/taskmaster/state.json`.
3. Classifies tasks by status and outputs them in a board format.

## Principles

- Returns "not initialized" if the task graph does not exist.
- Board output is a status summary; detailed modifications are handled by the respective tm-* workflows.
