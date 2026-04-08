---
name: clean
description: Cleans up state folders for completed tasks.
argument-hint: [task-folder-name | --all | --force]
user-invocable: true
allowed-tools: [Read, Bash, Glob]
---

# Clean

Cleans up state folders for completed tasks.

## State Directory

`~/ai-symbiote/{slug}/state/`

## Workflow

1. Scans all task-folders under `~/ai-symbiote/{slug}/state/`.
2. Checks `ralph-state.md` in each folder:
   - `active: false` or no `ralph-state.md` -> completed task
   - `active: true` -> in progress (skipped)
3. Displays the list of completed tasks and asks the user for deletion confirmation.
4. Deletes the corresponding task-folders after confirmation.
5. Does not touch in-progress tasks.

## Options

- `--all`: Delete all completed task folders without confirmation
- `--force`: Delete everything including in-progress tasks (use with caution)
- Specify task name: Delete a specific task only (e.g., `clean 2026-02-13T1430_login-feature`)
