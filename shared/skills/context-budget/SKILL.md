---
name: context-budget
description: "Audits token consumption across agents, skills, MCP tools, and rules. Reports optimization opportunities."
argument-hint: "[--verbose]"
user-invocable: true
allowed-tools: [Read, Glob, Grep, Bash]
---

# Context Budget -- Token Consumption Audit

Audits the token footprint of every component that the AI agent loads into its context window.
Identifies optimization opportunities and reports a breakdown by category.

## Workflow

Execute the following four phases sequentially.

### Phase 1: Inventory

Scan and count estimated tokens for each component type.

#### 1-A. CLAUDE.md Files

Glob for CLAUDE.md in:
- Project root: `./CLAUDE.md`
- User home: `~/.claude/CLAUDE.md`

For each file found:
```bash
wc -w < "$FILE"
```
Estimated tokens = word count × 1.3

#### 1-B. Skills

Glob for all SKILL.md files inside the plugin's skills directory:
```bash
PLUGIN_ROOT="${CURSOR_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-${CODEX_PLUGIN_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}}}"
find "$PLUGIN_ROOT/skills" -name "SKILL.md" -type f
```
For each file: estimated tokens = word count × 1.3

#### 1-C. Hooks

Read the hooks configuration from `.claude/settings.json` or `.claude/settings.local.json` (whichever exists).
Count the number of hook entries (keys under `"hooks"`).

Each hook entry ≈ 50 tokens (JSON schema overhead + output injection).

#### 1-D. MCP Tools

Check `.claude/settings.json` and `.claude/settings.local.json` for `mcpServers`.
Count the number of MCP servers and, if possible, the number of tools per server.

Each MCP tool ≈ 500 tokens (tool name + JSON schema + description).

#### 1-E. Agents

Glob for agent definition files (`.md` files with YAML frontmatter containing `model:` or `tools:` fields):
```bash
find "$PLUGIN_ROOT/agents" -name "*.md" -type f 2>/dev/null
```
If no agents directory, check `.claude/agents/` or `agents/` in the project root.

For each agent file: estimated tokens = word count × 1.3.
Flag agent descriptions exceeding 30 words (these load into every Agent tool invocation).
Flag agent files exceeding 200 lines.

#### 1-F. Harness Rules

Read `~/ai-symbiote/{slug}/harness-rules.md` (derive slug from project directory name).
Count lines in the file.

Approximately 15 tokens per rule line.

### Phase 2: Classify

Categorize each component by load frequency:

| Category | Description | Examples |
|-----------|-------------|---------|
| **always** | Loaded every session automatically | CLAUDE.md, hooks output, MCP tool schemas, harness rules |
| **sometimes** | Loaded only when explicitly invoked | Skills, agents |
| **rarely** | Loaded for specific edge-case scenarios | Infrequently used skills |

### Phase 3: Detect Issues

Flag the following problems:

- **CLAUDE.md files** totaling > 300 lines
- **MCP servers** with > 20 tools each
- **More than 10** MCP servers enabled
- **harness-rules.md** > 100 lines
- **Individual skill files** > 200 lines

### Phase 4: Report

Output the report in this exact format:

```
## Context Budget Report

### Component Breakdown
| Component | Files | Est. Tokens | Category |
|-----------|-------|-------------|----------|
| CLAUDE.md | {N} | ~{tokens} | always |
| Skills | {N} | ~{tokens} | sometimes |
| Hooks output | {N} | ~{tokens} | always |
| MCP tools | {N} | ~{tokens} | always |
| Harness rules | {N} lines | ~{tokens} | always |
| **Total** | | **~{total}** | |

### Warnings ({count})
- ⚠ {description of each detected issue with token cost}

### Top 3 Optimizations
1. **{action}** — {details} to save ~{tokens} tokens
2. **{action}** — {details} to save ~{tokens} tokens
3. **{action}** — {details} to save ~{tokens} tokens

Potential recovery: ~{tokens} tokens ({percent}% of always-loaded budget)
```

If no warnings are found, output:
```
### Warnings (0)
No issues detected. Context budget is healthy.
```

## --verbose Mode

When the user passes `--verbose` as an argument, append a detailed per-file breakdown after the main report:

```
### Detailed Breakdown
| File | Lines | Words | Est. Tokens |
|------|-------|-------|-------------|
| ~/.claude/CLAUDE.md | {lines} | {words} | ~{tokens} |
| ./CLAUDE.md | {lines} | {words} | ~{tokens} |
| skills/{name}/SKILL.md | {lines} | {words} | ~{tokens} |
| ... | | | |
```

Sort the table by estimated tokens descending so the largest consumers appear first.

## Principles

- Read-only audit: never modify any files
- Gracefully handle missing files (e.g. no harness-rules.md, no hooks)
- Use word count × 1.3 as the standard token estimation heuristic
- Round token estimates to the nearest integer
- Report should be actionable: every warning must suggest a concrete fix
