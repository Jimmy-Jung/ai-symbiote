---
name: gc
description: "Harness rule garbage collection. Cleans up unused rules, purges logs, and summarizes harness state."
argument-hint: [--dry-run | --force]
user-invocable: true
allowed-tools: [Read, Write, Edit, Glob, Grep, Bash]
---

# GC -- Harness Garbage Collection

Cleans up auto-generated harness rules and mistake logs.
Every time the agent makes a mistake, the `harness-learn.sh` hook appends a rule to context.md.
Over time, obsolete rules accumulate. gc periodically cleans them up.

## Entry Conditions

`~/ai-symbiote/{slug}/context.md` must exist.
If not found: display "context.md not found. Please initialize the project with the setup workflow."

## Workflow

### Step 1: Parse Harness Rules

Extracts all auto-generated rules with the `[Harness #` prefix from context.md.

```bash
STATE_DIR=~/ai-symbiote/{slug}
grep -n '^\[Harness #' "$STATE_DIR/context.md" 2>/dev/null
```

If no rules are found: output "No auto-generated harness rules found." and skip to Step 4.

Extract from each rule:
- Rule ID (`#N`)
- Description text
- Creation date (`auto-generated YYYY-MM-DD`)

### Step 2: Query Rule Trigger History

Queries the last trigger event for each rule from `harness-log.jsonl`.

Trigger determination criteria:
1. If a `rule_triggered` event exists, use that timestamp
2. If no `rule_triggered` event exists, use the `rule_created` event timestamp (never triggered since creation)

```bash
# Query last trigger per rule
grep '"rule_id":N' "$STATE_DIR/harness-log.jsonl" 2>/dev/null | tail -1
```

### Step 3: Identify Deletion Candidates

Marks rules that have not been triggered for 30+ days as deletion candidates.

Output format:
```
[GC] Harness rule analysis:

Active rules ({N}):
  [Harness #1] {description} — last triggered: {relative time}
  [Harness #3] {description} — last triggered: {relative time}

Deletion candidates ({M}, 30+ days untriggered):
  [Harness #2] {description} — last: {relative time} <- recommended for deletion
  [Harness #5] {description} — never triggered since creation <- recommended for deletion

context.md: {current line count}/300 lines
```

### Step 4: Log Cleanup Analysis

Analyzes the state of harness-log.jsonl:
- Total line count
- Number of entries older than 90 days
- Whether it exceeds 1000 lines

Output format:
```
[GC] Log analysis:
  harness-log.jsonl: {total lines} lines
  Older than 90 days: {N} lines (cleanup target)
```

### Step 5: Execute Cleanup

If `--dry-run` option is set, only display deletion candidates and exit.

Otherwise, ask the user for confirmation:
```
Delete {M} candidate rules and {N} log entries older than 90 days?
```

With `--force`, execute immediately without confirmation.

Cleanup actions:
1. Remove deletion candidate rule lines from context.md (using Edit tool)
2. Remove entries older than 90 days from harness-log.jsonl:
   ```bash
   # Preserve only entries within the last 90 days
   NINETY_DAYS_AGO=$(date -u -v-90d +%Y-%m-%dT 2>/dev/null || date -u -d '90 days ago' +%Y-%m-%dT)
   grep "$NINETY_DAYS_AGO\|$(date -u +%Y-%m)" "$STATE_DIR/harness-log.jsonl" > "$STATE_DIR/harness-log.jsonl.tmp"
   mv "$STATE_DIR/harness-log.jsonl.tmp" "$STATE_DIR/harness-log.jsonl"
   ```
3. If exceeding 1000 lines, keep only the most recent 800 lines

### Step 6: Report Results

```
[GC] Complete:
  Rules deleted: {M}
  Log entries cleaned: {N}
  context.md: {previous line count} -> {current line count} lines
  harness-log.jsonl: {previous line count} -> {current line count} lines
```

## Options

- `--dry-run`: Display deletion candidates only, no actual deletion
- `--force`: Execute cleanup immediately without confirmation

## Seed Rule Management

In addition to auto-generated `[Harness #N]` rules, gc also manages `[Seed #SN]` rules (loaded by setup).

- Parse seed rules: `grep -n '^\[Seed #' "$STATE_DIR/context.md"`
- Same 30-day untriggered deletion criteria as harness rules
- Display separately in Step 3 output:
  ```
  Seed rules ({N}):
    [Seed #S1] {description} — last triggered: {relative time}
  ```
- Include `rule_prevented` counts if available (see US-007)

## Rule Effectiveness Display

When `rule_prevented` events exist in harness-log.jsonl, display prevention counts:
```
[Harness #1] {description} — prevented: 5 times, last triggered: 3 days ago
[Harness #2] {description} — prevented: 0 times, never triggered <- deletion candidate
```

Tip: Run `lint` skill for code-level cleanup.

## Principles

- Manages harness rules and seed rules (dead code, documentation mismatches are out of scope)
- Never deletes without user confirmation (except with --force)
- Never deletes active rules (triggered within 30 days)
- Targets `[Harness #` and `[Seed #` prefixed lines only; does not touch manually added content
- Gracefully skips unknown event types in harness-log.jsonl (v2 schema compatibility)
