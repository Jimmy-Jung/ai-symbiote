---
name: note
user-invocable: true
description: Compaction-resistant notepad. Persists important context, decisions, and progress status to a per-project state folder so information is preserved across context window overflow or session transitions. This skill should be used when persisting important context across compaction boundaries or session transitions.
---

# Note -- Compaction-Resistant Notepad

Persists important context to a per-project state folder so information is preserved across context window overflow (compaction).

## Storage Path

`~/ai-symbiote/{slug}/state/{task-folder}/notepad.md`

task-folder naming: `{ISO8601-basic}_{task-name}`
Example: `2026-02-13T1430_login-feature`

Path resolution:
1. If a task-folder already exists for the current task, use that folder
2. Otherwise, create a task-folder with the current time and task name

slug generation: `owner-repo` from git remote origin or directory name. 64-char limit.

## When to Use

- Recording key decisions during complex work
- Passing state between Ralph Loop / Autopilot iterations
- Accumulating clues discovered during debugging
- Recording important user requirements

## Storage Format

```markdown
# Notepad

## Task Context
- Current task: [description]
- Goal: [description]

## Key Decisions
- [timestamp] [decision]

## Findings
- [timestamp] [finding]

## Progress Status
- [x] Completed items
- [ ] Remaining items
```

## Workflow

### Save (Write)
1. If task-folder does not exist, create it via Bash: `mkdir -p ~/ai-symbiote/{slug}/state/{task-folder}`
2. Append new entries to `notepad.md` (preserve existing content)
3. Include timestamps for chronological tracking

### Read
1. Check for notepad.md existence at task start
2. If it exists, restore previous context via Read tool
3. If file does not exist, start fresh

### Clean
1. On task completion, delete entire task-folder via clean workflow

## Autonomous Loop Integration

During each Ralph Loop / Autopilot iteration:
- Iteration start: read notepad.md to restore previous state
- During iteration: record findings and fix history
- Iteration end: record state for the next iteration

## Principles

- Record concisely (key points only)
- Always append mode (never overwrite existing content)
- Include timestamps
- Clean up via clean workflow after task completion
