---
name: taskmaster
description: "Task Master task graph management. Subcommands: init (initialize), board (status summary), parse-prd (PRD to tasks)."
argument-hint: <init|board|parse-prd> [options]
user-invocable: true
allowed-tools: [Read, Write, Bash, Glob]
---

# Task Master

Task graph management for ai-symbiote projects.

**Subcommands:**
- `/taskmaster init` — Initialize the task graph
- `/taskmaster board` — Display task status summary
- `/taskmaster parse-prd` — Convert PRD to task drafts

## State Directory

`~/ai-symbiote/{slug}/taskmaster/`

---

## Subcommand: init

Initializes the Task Master global task graph state.

### Behavior

1. Checks whether the `~/ai-symbiote/{slug}/taskmaster/` directory exists.
2. Creates the directory if it does not exist.
3. Generates `state.json` based on `${CURSOR_PLUGIN_ROOT:-${CODEX_PLUGIN_ROOT:-$CLAUDE_PLUGIN_ROOT}}/taskmaster/state.template.json` and config.
4. If the directory already exists, displays the current state and asks whether to reinitialize.

### Initialization Script

```bash
SLUG=$(project path based slug)
STATE_DIR="$HOME/ai-symbiote/$SLUG/taskmaster"
mkdir -p "$STATE_DIR"
```

Copies state.template.json to create state.json.

### Principles

- Uses schema files as the source of truth.
- Uses template files as the initial state clone source.
- Does not touch the session state folder (`~/ai-symbiote/{slug}/state/*`).
- Avoids destructive overwrites when existing files are present.

---

## Subcommand: board

Displays a summary of the task graph grouped by status.

### Output Items

- Total number of tasks
- Count per status (pending, in_progress, review, done, blocked)
- Current `currentTaskId`
- List of `blocked` tasks
- Actionable `pending` candidates

### Behavior

1. Reads `~/ai-symbiote/{slug}/taskmaster/tasks.json`.
2. Reads `~/ai-symbiote/{slug}/taskmaster/state.json`.
3. Classifies tasks by status and outputs them in a board format.

### Principles

- Returns "not initialized" if the task graph does not exist.
- Board output is a status summary; detailed modifications are handled by other subcommands.

---

## Subcommand: parse-prd

Reads prd.json and generates or updates per-task task.json drafts.

### Behavior

1. Locates the target `prd.json` (`~/ai-symbiote/{slug}/taskmaster/prd.json`).
2. Prepares task.json based on `${CURSOR_PLUGIN_ROOT:-${CODEX_PLUGIN_ROOT:-$CLAUDE_PLUGIN_ROOT}}/taskmaster/tasks.template.json`.
3. Interprets `userStories[]` as top-level task or subtask candidates.
4. Converts `dependsOn[]` to `dependencies[]`.
5. Converts `acceptanceCriteria[]` to `testStrategy` or subtask verification items.

### Principles

- Preserves `prd.json` as the original requirements source.
- `task.json` is the normalized result for execution.
- Does not lose `userStories` linkage during conversion.
