---
name: tm-init
description: Initializes the Task Master global task graph state.
argument-hint: [--tag <tag>]
user-invocable: true
allowed-tools: [Read, Write, Bash]
---

# TM Init

Initializes the Task Master global task graph state.

## State Directory

`~/ai-symbiote/{slug}/taskmaster/`

## Behavior

1. Checks whether the `~/ai-symbiote/{slug}/taskmaster/` directory exists.
2. Creates the directory if it does not exist.
3. Generates `state.json` based on `${CODEX_PLUGIN_ROOT:-$CLAUDE_PLUGIN_ROOT}/taskmaster/state.template.json` and config.
4. If the directory already exists, displays the current state and asks whether to reinitialize.

## Initialization Script

```bash
SLUG=$(project path based slug)
STATE_DIR="$HOME/ai-symbiote/$SLUG/taskmaster"
mkdir -p "$STATE_DIR"
```

Copies state.template.json to create state.json.

## Principles

- Uses schema files as the source of truth.
- Uses template files as the initial state clone source.
- Does not touch the session state folder (`~/ai-symbiote/{slug}/state/*`).
- Avoids destructive overwrites when existing files are present.
