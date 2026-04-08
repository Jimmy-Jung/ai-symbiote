---
name: stats
description: Analyzes usage frequency of skills and commands.
argument-hint: [--reset]
user-invocable: true
allowed-tools: [Read, Glob, Grep, Bash]
---

# Stats -- Usage Statistics

## Workflow

### Step 1: Collect Usage Data

Reads tracking data from the `~/ai-symbiote/{slug}/usage-data/` directory.

Data format: each file contains `{count}|{ISO8601 timestamp}`.

```
~/ai-symbiote/{slug}/usage-data/
  .tracked-since          # tracking start date
  skills/{name}           # per-skill counter
  commands/{name}         # per-command counter
```

If no tracking data exists, display a guidance message.

### Step 2: Scan All Items

Collects all existing items from directories:

- Skills: `skills/*/SKILL.md` in the current plugin root -- search via Glob
- Commands: slash command list (skills with argument-hint)

### Step 3: Merge and Sort Data

For each item:
1. If a counter file exists in usage-data, read count and lastUsed
2. If not, treat as count=0
3. Sort by count in descending order within each category

### Step 4: Output Statistics

```
[Usage Stats] Tracking period: {start date} ~ now ({N} days)

Skills ({total}, {1+ uses} active):
  #1  {name}          {count} uses  (last: {relative time})
  ...
  --- Unused (0 uses) ---
  {name}              0 uses

Commands ({total}, {1+ uses} active):
  #1  {name}          {count} uses  (last: {relative time})
  ...
```

### Step 5: Harness Evolution Metrics

Analyzes harness state from `~/ai-symbiote/{slug}/harness-log.jsonl` and `context.md`.

If harness-log.jsonl does not exist, skip this section.

```
[Harness Evolution Metrics]

Auto-generated rules:
  Active: {N}  |  Total created: {M}  |  GC removed: {M-N}

Mistake frequency (last 30 days):
  This week: {N}  |  Last week: {M}  |  Trend: {up/down/flat}

TOP 5 mistake types:
  #1  {error_type} @ {file}    {count} times
  #2  {error_type} @ {file}    {count} times
  ...

Harness effectiveness:
  Same mistake recurrence after rule creation: {N}/{M} ({percent}%)
  (Lower recurrence rate = more effective harness)

Rule prevention stats (v2):
  Total preventions: {N}
  Top 5 most effective rules:
    #1  [Harness #{id}] {description}    prevented: {count} times
    #2  [Seed #{id}] {description}       prevented: {count} times
    ...
  Rules with 0 preventions: {N} (gc candidates)

Guard blocked commands (v2):
  Total blocks: {N}
  Top patterns: {command pattern} x{count}

context.md: {line count} lines ({harness rules} + {seed rules})
harness-log.jsonl: {line count} lines
```

Analysis method:
1. Count `[Harness #` prefixed lines in context.md -> active harness rule count
2. Count `[Seed #` prefixed lines in context.md -> active seed rule count
3. Count `rule_created` events in harness-log.jsonl -> total created rule count
4. Count mistake events in harness-log.jsonl for last 7/14 days -> weekly trend
5. Aggregate frequency by error_type + file combination -> TOP 5
6. Check recurrence of same {error_type, file} after rule_created -> recurrence rate
7. Count `rule_prevented` events per rule_id -> prevention stats (v2 events)
8. Count `guard_blocked` events -> guard stats (v2 events)
9. Gracefully skip unknown event types (forward-compatible with future schema versions)

### Step 5.5: Baseline Measurement (--baseline)

When `--baseline` is provided, calculate and display the current repeat rate for tracking improvement:

```
[Harness Baseline] Measured on {date}

Repeat rate (same {error_type, file} within 7 days):
  Total unique error patterns: {N}
  Patterns that recurred: {M}
  Repeat rate: {M/N * 100}%

Save this baseline to track improvement after harness evolution changes.
```

### Step 6: Reset Tracking (--reset)

When the user requests "reset tracking", "stats --reset", etc.:
1. Confirm the scope of reset
2. Display current statistics summary
3. Delete corresponding counter files after confirmation
4. Report results
