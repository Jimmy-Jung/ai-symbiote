---
name: tm-parse-prd
description: "Reads prd.json and generates or updates per-task task.json drafts."
argument-hint: "task-folder --append"
user-invocable: true
allowed-tools: [Read, Write, Bash]
---

# TM Parse PRD

Reads prd.json and generates or updates per-task task.json drafts.

## State Directory

`~/ai-symbiote/{slug}/taskmaster/`

## Behavior

1. Locates the target `prd.json` (`~/ai-symbiote/{slug}/taskmaster/prd.json`).
2. Prepares task.json based on `${CODEX_PLUGIN_ROOT:-$CLAUDE_PLUGIN_ROOT}/taskmaster/tasks.template.json`.
3. Interprets `userStories[]` as top-level task or subtask candidates.
4. Converts `dependsOn[]` to `dependencies[]`.
5. Converts `acceptanceCriteria[]` to `testStrategy` or subtask verification items.

## Principles

- Preserves `prd.json` as the original requirements source.
- `task.json` is the normalized result for execution.
- Does not lose `userStories` linkage during conversion.
