---
name: instinct-status
description: "Displays learned instincts with confidence scores. Shows project-scoped and global patterns."
argument-hint: ""
user-invocable: true
allowed-tools: [Read, Glob, Grep, Bash]
---

# Instinct Status -- Learned Pattern Viewer

## Execution

1. Derive the project slug and STATE_DIR:
   ```bash
   PLUGIN_ROOT="${CURSOR_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-${CODEX_PLUGIN_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}}}"
   source "$PLUGIN_ROOT/hooks/scripts/lib/common.sh"
   STATE_DIR=$(get_state_dir)
   ```
2. Check `$STATE_DIR/instincts/` for project instinct YAML files.
3. Check `~/ai-symbiote/global-instincts/` for global instinct YAML files.

## Workflow

### Step 1: Collect Instincts

Scan for `.yaml` files in both directories:

- **Project instincts:** `$STATE_DIR/instincts/*.yaml`
- **Global instincts:** `~/ai-symbiote/global-instincts/*.yaml`

For each `.yaml` file, read and extract:
- `name` -- short identifier (e.g. `prefer-async-await`)
- `pattern` -- human-readable description of the observed pattern
- `confidence` -- float between 0.3 and 0.9
- `scope` -- `project` or `global`
- `last_observed` -- ISO-8601 date of the most recent observation

### Step 2: Sort and Display

Sort all instincts by `confidence` descending.

Display as a markdown table:

```
| Name | Confidence | Scope | Last Observed |
|------|-----------|-------|---------------|
| prefer-async-await | 0.8 | project | 2026-04-16 |
| use-conventional-commits | 0.7 | global | 2026-04-15 |
```

Color-code by confidence tier:
- **High** (>= 0.7): strong pattern, reliably observed
- **Medium** (0.5 -- 0.7): emerging pattern, needs more observations
- **Low** (< 0.5): weak pattern, may expire soon

### Step 3: Empty State

If no instincts exist in either directory:

> "No instincts recorded yet. Instincts are learned from repeated patterns across sessions."

## YAML Format

Each instinct is stored as a single YAML file named `{name}.yaml`:

```yaml
name: prefer-async-await
pattern: "User consistently chose async/await over completion handlers"
confidence: 0.7
scope: project
source: session-abc123
created: "2026-04-16T12:00:00Z"
last_observed: "2026-04-16T12:00:00Z"
```

### Field Reference

| Field | Type | Description |
|-------|------|-------------|
| name | string | Unique identifier, kebab-case |
| pattern | string | Human-readable description of the observed behavior |
| confidence | float | 0.3 -- 0.9; determines display tier and expiry |
| scope | string | `project` or `global` |
| source | string | Session ID where the instinct was first created |
| created | string | ISO-8601 UTC timestamp of creation |
| last_observed | string | ISO-8601 UTC timestamp of most recent observation |

## Confidence Mechanics

- **Increase:** +0.1 per repeated observation (max 0.9)
- **Decrease:** -0.2 per user rejection (min 0.3)
- **Expiry:** Instincts with confidence < 0.3 are removed during SessionStart cleanup

The confidence score reflects how reliably a pattern has been observed. Higher confidence means the AI should apply this instinct more assertively.

## Global Promotion

When invoked with `--promote`, run the global promotion workflow:

1. Scan all project instinct directories under `~/ai-symbiote/*/instincts/`.
2. For each instinct name, count how many distinct projects have it with confidence >= 0.7.
3. If 3 or more projects share the same instinct at high confidence:
   - Copy the instinct YAML to `~/ai-symbiote/global-instincts/`.
   - Change the `scope` field to `global`.
   - Log the promotion event.
4. Report promoted instincts and any that are close to the threshold.

This is a manual workflow triggered by the AI when the user runs `/instinct-status --promote`.
