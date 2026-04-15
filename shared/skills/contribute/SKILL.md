---
name: contribute
description: "Files a GitHub issue on the ai-symbiote repository when a bug, improvement idea, or problem is found. Collects environment info automatically."
argument-hint: <issue description>
user-invocable: true
allowed-tools: [Read, Grep, Glob, Bash]
---

# Contribute -- File a GitHub Issue

When you find a bug, problem, or improvement idea in ai-symbiote,
this skill collects the relevant context and files a GitHub issue on the upstream repository.

## Prerequisites

- `gh` CLI must be installed and authenticated (`gh auth status`)

If `gh` is not available: display "gh CLI not found. Install: https://cli.github.com/" and stop.
If not authenticated: display "Run `gh auth login` first." and stop.

## Workflow

### Step 1: Classify the Issue

Ask the user (or infer from the argument) what type of issue this is:

| Type | Label | When to use |
|------|-------|-------------|
| Bug | `bug` | A skill, hook, or build script doesn't work as expected |
| Improvement | `enhancement` | An existing feature could work better |
| New Feature | `feature` | Something that doesn't exist yet but should |

### Step 2: Collect Environment Info

Gather diagnostic context automatically (no user effort required):

```bash
# Plugin version
VERSION=$(grep '"version"' ~/ai-symbiote/{slug}/manifest.json 2>/dev/null | head -1 | grep -o '[0-9.]*')
[ -z "$VERSION" ] && VERSION="unknown"

# Platform
PLATFORM="unknown"
[ -n "$CURSOR_PLUGIN_ROOT" ] && PLATFORM="cursor"
[ -n "$CLAUDE_PLUGIN_ROOT" ] && PLATFORM="claude"
[ -n "$CODEX_PROJECT_DIR" ] && PLATFORM="codex"

# OS
OS=$(uname -s -r)

# Skill count
SKILL_COUNT=$(ls -d skills/*/SKILL.md 2>/dev/null | wc -l | tr -d ' ')

# Recent harness rules count
HARNESS_RULES=0
[ -f ~/ai-symbiote/{slug}/context.md ] && HARNESS_RULES=$(grep -c '^\[Harness #' ~/ai-symbiote/{slug}/context.md 2>/dev/null) || true
```

### Step 3: Draft Issue

Compose the issue from the user's description + auto-collected environment:

```markdown
## Description

{user's description of the problem or idea}

## Steps to Reproduce (if bug)

{user provides, or "N/A" for feature requests}

## Expected Behavior

{what should happen}

## Actual Behavior

{what actually happens, if bug}

## Environment

| Item | Value |
|------|-------|
| Plugin version | {VERSION} |
| Platform | {PLATFORM} |
| OS | {OS} |
| Skills | {SKILL_COUNT} |
| Harness rules | {HARNESS_RULES} |

---
*Filed via ai-symbiote contribute skill.*
```

For improvements and features, omit "Steps to Reproduce" and "Actual Behavior" sections.

### Step 4: User Review

Display the full draft to the user.

Ask for confirmation:
```
This issue will be filed on Jimmy-Jung/ai-symbiote.
Proceed? (yes/no/edit)
```

- **yes**: proceed to Step 5
- **no**: stop without filing
- **edit**: let the user modify the title or body, then re-confirm

### Step 5: File Issue

```bash
gh issue create \
  --repo Jimmy-Jung/ai-symbiote \
  --title "{concise title}" \
  --body "{issue body}" \
  --label "{bug|enhancement|feature}"
```

If the label doesn't exist, omit the `--label` flag.

Display the created issue URL to the user.

### Step 6: Record

Log the submission to prevent accidental duplicate filings in the same session:

```bash
STATE_DIR=~/ai-symbiote/{slug}
printf '{"ts":"%s","type":"issue_filed","title":"%s","url":"%s"}\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "{title}" "{issue_url}" \
  >> "$STATE_DIR/harness-log.jsonl"
```

## Principles

- **Privacy**: never include project file paths, code snippets, or project-specific data in the issue body
- **User confirms**: never file without explicit approval
- **Concise**: keep the title under 70 characters, body focused on the problem
- **Helpful**: auto-collect environment info so the user doesn't have to
