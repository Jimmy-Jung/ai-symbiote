---
name: setup
description: Project bootstrap. Analyzes the codebase to detect the project stack and initializes the shared Symbiote state.
argument-hint:
user-invocable: true
allowed-tools: [Read, Write, Edit, Glob, Grep, Bash, Agent]
default-mode: plan
---

# Setup Skill

Analyzes the project and prepares the shared state directory under `~/ai-symbiote/{slug}/`.

## Default Execution Mode

`setup` always starts in **plan mode** by default.

Before any file creation, installation, or shell execution:

1. Inspect the repository and current state
2. Present the setup plan/checklist to the user
3. Clarify optional choices that affect installation or configuration
4. Only execute the setup steps after the user confirms to proceed

Do not start with immediate Bash execution unless the user has already approved execution in the current turn.

## State Directory

All platforms share `~/ai-symbiote/{slug}/` as a common directory.

- `manifest.json`
- `context.md`
- `state/`
- `taskmaster/`
- `usage-data/`
- `messenger/`

## Slug Computation Rules

The project slug **must** be computed using the algorithm below. This follows the same rules as the hook scripts (`common.sh`).

```
1. git rev-parse --show-toplevel → basename → lowercase → keep only alphanumeric/_/- characters
2. If not a git repo, use the basename of the current directory
3. Example: /home/user/projects/MyApp → "myapp"
4. Example: /home/user/work/api-server → "api-server"
```

**Never include the full path in the slug.** A form like `users_jimmy_documents_github_carelog` is incorrect.

## Platform Detection

Detects the current execution platform at setup start:

```bash
# Claude environment detection
if command -v claude >/dev/null 2>&1; then
  PLATFORM="claude"
# Codex environment detection
elif command -v codex >/dev/null 2>&1 || [ -f "$HOME/.codex/config.toml" ]; then
  PLATFORM="codex"
else
  PLATFORM="unknown"
fi
```

Subsequent steps branch based on platform-specific commands.

## Workflow

**Plan-first rule:** treat the steps below as an execution checklist, not an immediate script.
When `setup` is invoked, summarize the relevant steps first, ask for confirmation on optional installs/config changes, then execute in order.

### Standard Plan Output

At the start of `setup`, use [setup-plan.md](shared/skills/setup/templates/setup-plan.md) as the source-of-truth template before executing.
Render it with [render-setup-plan.sh](shared/skills/setup/scripts/render-setup-plan.sh) so the placeholders are filled from the current project state.
Use [begin-setup.sh](shared/skills/setup/scripts/begin-setup.sh) as the actual entrypoint: default output is plan-only, and `--approve` starts execution.

Base shape:

```text
[Setup Plan]
1. Prepare state directories and baseline manifest/context
2. Check optional platform integrations
3. Detect project stack
4. Recommend/apply skills, CLI tools, and MCP servers
5. Generate or normalize manifest/context defaults

Optional items needing approval:
- project agent config generation (`.claude/`, `.codex/`, `.gitignore`)
- ralph workflow enable/check
- codex plugin install or integration check
- guided store selections (skill / cli / mcp)

Reply with approval before execution.
```

### Step 0: Environment Preparation

- Generate slug and create state directories:
  ```bash
  mkdir -p ~/ai-symbiote/{slug}/usage-data/skills
  mkdir -p ~/ai-symbiote/{slug}/usage-data/commands
  mkdir -p ~/ai-symbiote/{slug}/state
  mkdir -p ~/ai-symbiote/{slug}/taskmaster
  mkdir -p ~/ai-symbiote/{slug}/ralph
  mkdir -p ~/ai-symbiote/{slug}/messenger
  ```
- Record current ISO8601 timestamp in `~/ai-symbiote/{slug}/usage-data/.tracked-since`

### Step 0.1: Optional Project Agent Config Directories

This step is **optional**.

- Default `setup --approve` should **not** create `.claude/`, `.codex/`, or `.gitignore` entries.
- Run it only when the user explicitly wants project-scoped agent/tool settings committed to local workspace state.
- Use the `--project-agent-config` flag to opt in.

#### Execution (run this Bash block only after the user approves the setup plan and opts in)

```bash
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

# 1. Create directories
mkdir -p "$PROJECT_ROOT/.claude"
mkdir -p "$PROJECT_ROOT/.codex"

# 2. .claude/settings.json (only if missing)
if [ ! -f "$PROJECT_ROOT/.claude/settings.json" ]; then
  cat > "$PROJECT_ROOT/.claude/settings.json" << 'SETTINGS_EOF'
{
  "permissions": {
    "allow": [
      "Bash(*)",
      "Read(*)",
      "Write(*)",
      "Edit(*)",
      "Glob(*)",
      "Grep(*)",
      "WebFetch(*)",
      "WebSearch(*)",
      "Agent(*)",
      "Skill(*)",
      "NotebookEdit(*)"
    ],
    "deny": []
  }
}
SETTINGS_EOF
  echo "[Step 0.1] .claude/settings.json created"
else
  echo "[Step 0.1] .claude/settings.json already exists -- skipped"
fi

# 3. .codex/config.toml (only if missing)
if [ ! -f "$PROJECT_ROOT/.codex/config.toml" ]; then
  cat > "$PROJECT_ROOT/.codex/config.toml" << 'CODEX_EOF'
# Codex project config (auto-generated by ai-symbiote setup)
model = "gpt-5.4"
approval_mode = "suggest"
CODEX_EOF
  echo "[Step 0.1] .codex/config.toml created"
else
  echo "[Step 0.1] .codex/config.toml already exists -- skipped"
fi

# 4. Register in .gitignore (prevent duplicates)
GITIGNORE="$PROJECT_ROOT/.gitignore"
[ ! -f "$GITIGNORE" ] && touch "$GITIGNORE"

add_to_gitignore() {
  local entry="$1"
  if ! grep -qxF "$entry" "$GITIGNORE" && ! grep -qxF "${entry%/}" "$GITIGNORE"; then
    [ -s "$GITIGNORE" ] && [ "$(tail -c1 "$GITIGNORE")" != "" ] && echo "" >> "$GITIGNORE"
    if ! grep -qF '# AI agent project config' "$GITIGNORE"; then
      echo '# AI agent project config (auto-generated by ai-symbiote setup)' >> "$GITIGNORE"
    fi
    echo "$entry" >> "$GITIGNORE"
    echo "[Step 0.1] Added $entry to .gitignore"
  fi
}

add_to_gitignore '.claude/'
add_to_gitignore '.codex/'

echo "[Step 0.1] Complete"
```

When this step is skipped, setup should continue normally after printing a short note that project agent config was not created.

### Step 0.5: PRD / Ralph Workflow Availability

Check whether the built-in `prd` / `ralph` workflow is available for the current platform.

#### Claude Environment

1. Check installation:
   ```bash
   claude plugin list 2>/dev/null | grep -q "ralph" && echo "installed" || echo "not-installed"
   ```

2. If missing and the user approved optional installs, install from marketplace:
   ```bash
   claude plugin marketplace add snarktank/ralph 2>/dev/null
   claude plugin install ralph-skills@ralph-marketplace
   ```

#### Codex Environment

Codex uses the Ralph workflow bundled inside `ai-symbiote` itself.

1. Check bundled skills:
   ```bash
   [ -f "$PLUGIN_ROOT/skills/prd/SKILL.md" ] && [ -f "$PLUGIN_ROOT/skills/ralph/SKILL.md" ] && echo "installed" || echo "not-installed"
   ```

2. Check bundled runner:
   ```bash
   [ -x "$PLUGIN_ROOT/skills/ralph/scripts/ralph-loop.sh" ] && echo "runner-ready" || echo "runner-missing"
   ```

3. If missing, rebuild and reinstall ai-symbiote instead of cloning `snarktank/ralph` directly:
   ```bash
   bash platforms/codex/install.sh
   ```

#### Common -- Failure Message

```
Ralph workflow is not available.
To install manually:
  [Claude] claude plugin marketplace add snarktank/ralph && claude plugin install ralph-skills@ralph-marketplace
  [Codex]  reinstall ai-symbiote so the bundled prd/ralph skills are synced
This workflow provides /prd (PRD generation) and /ralph (PRD->JSON conversion) commands.
```

Skills provided by the Ralph workflow:
- `/prd` - Generate PRD (Product Requirements Document)
- `/ralph` - Convert PRD to prd.json for headless autonomous execution

### Step 0.6: Codex Plugin Check (Optional)

Check if the openai/codex-plugin-cc plugin is installed.
Codex is an optional enhancement, so setup continues even if not installed.

#### Claude Environment

1. Check plugin installation:
   ```bash
   claude plugin list 2>/dev/null | grep -q "codex" && echo "installed" || echo "not-installed"
   ```

2. If installed, verify CLI authentication:
   ```bash
   codex --version 2>/dev/null && echo "cli-ready" || echo "cli-not-ready"
   ```

3. If not installed, include this choice in the plan confirmation step:
   ```
   [Optional] Would you like to install the Codex plugin?
   Codex (GPT-5.4) can be used as a sub-agent for second opinions, adversarial reviews, and root cause analysis.
   An OpenAI account (ChatGPT Plus/Pro or API key) is required.
   To install, type "yes"; to skip, type "skip":
   ```
   - On "yes":
     ```bash
     claude plugin marketplace add openai/codex-plugin-cc 2>/dev/null
     claude plugin install codex@openai-codex
     ```
   - On "skip": Proceed without Codex

#### Codex Environment

In a Codex environment, Codex CLI is already the runtime, so openai/codex-plugin-cc installation is unnecessary.
Instead, check Claude integration availability:

1. Check Claude CLI:
   ```bash
   command -v claude >/dev/null 2>&1 && echo "claude-available" || echo "claude-not-available"
   ```

2. Guidance based on result:
   - Claude available: "Claude integration will be activated. Composing a cross-platform sub-agent team."
   - Claude not installed: "Proceeding in Codex standalone mode. Install Claude Code to enable cross-platform team composition."

4. Record platform state in manifest.json.

### Step 1: Project Detection

Run Glob, Grep, Read in parallel to comprehensively analyze the project stack.

#### Track A -- Language Detection
- Search file extensions with Glob: `*.swift`, `*.kt`, `*.ts`, `*.tsx`, `*.js`, `*.py`, `*.go`, `*.rs`, `*.java`, `*.rb`, `*.cs`, `*.cpp`
- Determine primary/secondary languages

#### Track B -- Package Manager Detection
- SPM: `Package.swift`
- Node: `package.json`
- Python: `requirements.txt`, `pyproject.toml`
- Gradle: `build.gradle`, `build.gradle.kts`
- Rust: `Cargo.toml`
- Go: `go.mod`

#### Track C -- Framework Detection
- Grep import patterns: `import UIKit`, `import SwiftUI`, `import React`, `from 'react'`, `import django`, etc.

#### Track D -- Architecture Detection
- Folder structure hints: `/features/`, `/domain/`, `/data/`, `/presentation/`, `/components/`

#### Track E -- CI/CD Detection
- `.github/workflows/*.yml`, `.gitlab-ci.yml`, `Jenkinsfile`, etc.

#### Track F -- Build Tool Detection
- Xcode: `*.xcodeproj`, Tuist: `Project.swift`, Web: `webpack`, `vite`, `next.config`

### Step 2: Community Skill Recommendation and Installation (skill-store)

Recommends relevant skills from the awesome-agent-skills catalog (1,060+) based on the detected stack.
Runs Skill Store's `--auto` mode.

### Step 3: CLI Tool Recommendation and Installation (cli-store)

Recommends relevant CLI tools based on the detected stack.
Runs CLI Store's `--auto` mode.

**Priority**: skill → **cli** → mcp. CLI tools are preferred over MCP servers when available.

1. Read detected stack from Step 1 results
2. Match against `stacks` and `services` in `skills/cli-store/catalog.json`
3. Run `checkCmd` for each matched CLI to detect install/auth status
4. Display CLI list grouped by status (Ready / Installable / Needs auth)
5. After user approval, install selected CLIs via platform package manager (brew/apt/npm/pip)
6. Record in manifest.json `cliTools` section
7. Export CLI-covered MCP IDs to `~/ai-symbiote/{slug}/state/cli-covered-mcps.json`

### Step 4: MCP Server Recommendation and Installation (mcp-store)

Recommends relevant MCP servers from the awesome-mcp-servers catalog (530+) based on the detected stack.
Runs MCP Store's `--auto` mode.
**Skips MCP servers already covered by CLI tools from Step 3.**

1. Read detected stack from Step 1 results
2. Read `~/ai-symbiote/{slug}/state/cli-covered-mcps.json` to get CLI-covered MCP IDs
3. Match against `stacks` and `services` in `skills/mcp-store/catalog.json`
4. Remove entries whose `id` is in the CLI-covered list
5. Check already installed MCPs via `claude mcp list`
6. Display recommended MCPs with required environment variables (only those NOT covered by CLIs)
7. After user approval, apply selected MCP configuration
8. Record in manifest.json `mcpServers` section

#### Execution — AI-driven two-phase flow (recommended, required for non-interactive environments)

When AI agents (Cursor/Claude) run the script via the Bash tool, stdin is not a TTY, so
`guided` mode cannot display `read` prompts and every selection silently falls back to `later`.
To avoid this, the AI must **ask the user directly and pass the answers through environment variables**.

**Phase 1 — Collect the recommendation list (`recommend` mode)**

```bash
PLUGIN_ROOT="${CURSOR_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-${CODEX_PLUGIN_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}}}"
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
STATE_DIR=~/ai-symbiote/{slug}

bash "$PLUGIN_ROOT/skills/setup/scripts/run-store-setup.sh" \
  --state-dir "$STATE_DIR" \
  --project-root "$PROJECT_ROOT" \
  --mode recommend
```

Results land in `$STATE_DIR/state/setup-store-summary.json` (manifest selections are NOT yet recorded).

**Phase 2 — Ask the user**

The AI renders `skills.items`, `cli.installable`, and `mcp.recommended` from
summary.json as a localized list (Korean by default for this project) and collects
a selection for each group.
Allowed answers: `all` / a numeric list (e.g. `1,3`) / `skip`.

**Phase 3 — Pass the answers into `guided` mode via environment variables**

```bash
SETUP_STORE_SKILLS_CHOICE="1,3" \
SETUP_STORE_CLI_CHOICE="all" \
SETUP_STORE_MCP_CHOICE="skip" \
bash "$PLUGIN_ROOT/skills/setup/scripts/run-store-setup.sh" \
  --state-dir "$STATE_DIR" \
  --project-root "$PROJECT_ROOT" \
  --mode guided
```

When the env vars are set, `prompt_or_default` skips `read` and uses those values verbatim.

#### Execution — direct terminal run (interactive)

When the user runs the script directly in a Cursor/Claude built-in terminal, stdin IS a TTY,
so `--mode guided` alone drives the interactive flow without env vars:

```bash
bash "$PLUGIN_ROOT/skills/setup/scripts/run-store-setup.sh" \
  --state-dir "$STATE_DIR" \
  --project-root "$PROJECT_ROOT" \
  --mode guided
```

**If `manifest.json` does not yet exist, the runner first creates a minimal bootstrap manifest and continues.**

#### Runner Modes

- `--mode guided` (default): produces recommendation files and then collects user selections. Requires either a TTY or the `SETUP_STORE_*_CHOICE` env vars.
- `--mode recommend`: writes only the recommendation and summary then exits. Does NOT record manifest selections; the AI uses this as the pre-question stage.
- `--mode fast`: records recommendations/state without asking and leaves every selection as `later`.
- `--mode dry-run`: emits the recommendation summary to a temp directory and never touches real state.

#### Guided Setup Rules

- Split questions into three groups so the user can pick directly: **skill / cli / mcp**.
- Default allowed answers per group: one of `all`, a numeric list (`1,2`), `skip`, `later`.
- In non-interactive runs, unanswered prompts default to `later`; AI agents MUST use the **AI-driven two-phase flow** above in that case.
- Forward the user's answers as `SETUP_STORE_SKILLS_CHOICE`, `SETUP_STORE_CLI_CHOICE`, `SETUP_STORE_MCP_CHOICE`.
- Record answers in `~/ai-symbiote/{slug}/state/setup-store-preferences.json` and in `manifest.json`'s `setupSelections`.
- Selected CLIs are installed immediately.
- Selected skills update `manifest.plugins` and state immediately.
- Selected MCPs update `manifest.mcpServers` and state immediately.

### Step 4.6: Security mode selection (guided)

Ask the user which AI-restriction hooks should run. The answer is stored under
`security.mode` in `manifest.json` and read by each hook at runtime.

Presets:

| Mode       | guard-shell | security-guard | harness-learn | comment-checker | verify-queue |
|------------|-------------|----------------|---------------|-----------------|--------------|
| `minimal`  | off | off | off | off | off |
| `balanced` (default) | on  | on  | on  | on  | on  |
| `strict`   | on  | on  | on  | on  | on  (reserved for future tightening)   |
| `custom`   | per-hook user choice | | | | |

Flow (AI-driven, works in both TTY and non-TTY environments):

1. Ask the user which preset to use via AskUserQuestion, with `balanced` recommended.
2. If the user chose `custom`, ask one more question per hook via AskUserQuestion
   (multi-select) to collect the on/off toggles.
3. Write the chosen mode (and, for custom, the per-hook booleans) into
   `~/ai-symbiote/{slug}/state/setup-security-mode.json` so Step 5 can merge
   it into the generated manifest. Helper: `scripts/security-mode-apply.sh`.

Each hook (`guardShell` → `guard-shell.sh`, `securityGuard` → `security-guard.sh`,
`harnessLearn` → `harness-learn.sh`, `commentChecker` → `comment-checker.sh`,
`verifyQueue` → `verify-queue.sh`) checks `is_hook_enabled` from
`shared/hooks/scripts/lib/security-mode.sh` on every invocation. Switching
modes after setup does NOT require Claude Code restart — the cache under
`state/security-mode.cache` is rebuilt lazily when manifest mtime bumps.

Post-setup changes go through `/security mode [minimal|balanced|strict|custom]`
or by editing `manifest.json` directly.

### Step 5: Generate manifest.json

Run the bundled helper after writing the manifest to ensure ai-symbiote defaults are present:

```bash
PLUGIN_ROOT="${CURSOR_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-${CODEX_PLUGIN_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}}}"
bash "$PLUGIN_ROOT/skills/setup/scripts/manifest-defaults.sh" --manifest "$STATE_DIR/manifest.json"
```

Write to `~/ai-symbiote/{slug}/manifest.json`:

```json
{
  "version": "1.0.0",
  "created": "ISO8601",
  "lastEvolved": "ISO8601",
  "path": "/absolute/path/to/project",
  "agentPlatforms": ["claude", "codex", "cursor"],
  "defaults": {
    "completionLevel": 2,
    "maxRalphIterations": 10,
    "enableSecurityReview": false,
    "enableQA": true
  },
  "security": {
    "sessionSummaryLevel": "auto",
    "mode": "balanced",
    "hooks": {
      "guardShell": true,
      "securityGuard": true,
      "harnessLearn": true,
      "commentChecker": true,
      "verifyQueue": true
    }
  },
  "project": {
    "name": "auto-detected",
    "type": "mobile-app|web-app|library|cli|monorepo|backend",
    "languages": ["detected..."],
    "platforms": ["detected..."]
  },
  "stack": {
    "packageManager": "detected",
    "buildTool": "detected",
    "frameworks": ["detected..."],
    "architecture": "detected",
    "testFramework": "detected",
    "cicd": "detected"
  },
  "plugins": {
    "ralph": {
      "source": "builtin:ai-symbiote/ralph",
      "installed": true
    },
    "codex": {
      "source": "github:openai/codex-plugin-cc",
      "installed": true,
      "cliReady": true
    }
  },
  "cliTools": {
    "gh": {
      "cmd": "gh",
      "installed": "ISO8601",
      "mcpEquivalent": "github",
      "status": "ready"
    }
  },
  "mcpServers": {
    "context7": {
      "transport": "stdio",
      "installed": "ISO8601",
      "platform": "claude"
    }
  }
}
```

`path` is the project's absolute path and is used for slug collision detection. It must be included.

**agentPlatforms rules:**
- ai-symbiote is a multi-platform plugin that uses Claude, Codex, and Cursor together.
- Do not record only a single platform (`"claude"`, `"codex"`, or `"cursor"`).
- If `agentPlatforms` already exists in the manifest, merge rather than overwrite.
- Always maintain `["claude", "codex", "cursor"]` regardless of which platform the current session is running on.

### Step 6: Generate context.md

Write to `~/ai-symbiote/{slug}/context.md`:

- Project stack summary
- Coding conventions (extracted from existing code)
- File naming patterns
- Architecture patterns

### Step 6.5: Generate Security Baseline Automatically

Immediately after `context.md` is created, run the Security OS baseline scan once.

This is required for the Phase 2 public UX:
- setup should finish with a visible security score
- `security-baseline.json` should exist before the first `/security status`
- `context.md` should gain a synchronized `Security Baseline` block

Run:

```bash
PLUGIN_ROOT="${CURSOR_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-${CODEX_PLUGIN_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}}}"
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
STATE_DIR=~/ai-symbiote/{slug}

bash "$PLUGIN_ROOT/skills/security/scripts/security-scan.sh" scan \
  --project-root "$PROJECT_ROOT" \
  --state-dir "$STATE_DIR" \
  --context-file "$STATE_DIR/context.md" \
  --install-hints passive
```

Rules:
- Do not fail setup if the baseline scan fails
- Show only the score, severity counts, and top 3 risks in setup output
- If `gitleaks` / `semgrep` are missing, setup should recommend them but must not install them automatically

### Step 7: Load Harness Seed Rules

Loads stack-appropriate harness seed rules into harness-rules.md to prevent known agent mistakes from the first session.

**Skip if `--no-seed` option is provided.**

#### Seed Selection

Match the detected stack (from Step 1) to seed files in the plugin's `harness-seeds/` directory:

| Detected Stack | Seed Files |
|---------------|------------|
| Swift/iOS (SwiftUI, UIKit) | `swift.md` + `generic.md` |
| Next.js / React | `nextjs.md` + `generic.md` |
| Python (Django, Flask, FastAPI) | `python.md` + `generic.md` |
| Other | `generic.md` only |

#### Execution

```bash
PLUGIN_ROOT="${CURSOR_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-${CODEX_PLUGIN_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}}}"
SEEDS_DIR="$PLUGIN_ROOT/harness-seeds"
STATE_DIR=~/ai-symbiote/{slug}
RULES_FILE="$STATE_DIR/harness-rules.md"
HARNESS_LOG="$STATE_DIR/harness-log.jsonl"

# Append seed rules to harness-rules.md
SEED_COUNT=0
for seed_file in generic.md {stack-specific}.md; do
  if [ -f "$SEEDS_DIR/$seed_file" ]; then
    echo "" >> "$RULES_FILE"
    cat "$SEEDS_DIR/$seed_file" >> "$RULES_FILE"
    COUNT=$(grep -c '^\[Seed #' "$SEEDS_DIR/$seed_file")
    SEED_COUNT=$((SEED_COUNT + COUNT))
  fi
done

# Record seed_loaded event
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
printf '{"v":2,"ts":"%s","type":"seed_loaded","seed":"{stack}","count":%d}\n' \
  "$NOW" "$SEED_COUNT" >> "$HARNESS_LOG"
```

Output: `[Setup] Loaded {N} harness seed rules for {stack} stack.`

### Step 8: Generate Project CLAUDE.md

**Warning: Required step after approval.**
Without `CLAUDE.md` at the project root, Claude Code cannot recognize the project context and ai-symbiote skills.

#### Condition
- If `CLAUDE.md` already exists, **skip** (preserve user customization).
- Create new file with the Write tool only when it does not exist.

#### Content Structure (Write to `{PROJECT_ROOT}/CLAUDE.md` using the Write tool)

Include the following sections based on information detected in Steps 1-4:

```markdown
# {Project Name} - Claude Code Instructions

## Project Overview
- Summary of project type, platform, and build tool detected in Step 1

## ai-symbiote Plugin Usage
- State directory: `~/ai-symbiote/{slug}/`
- Autonomous execution: `/auto <task description>`
- Parallel execution: `/auto <task description> --mode parallel-max`
- PRD-based: `/prd` -> `/ralph`
- Analysis: `/analyze <target>`
- Planning: `/plan <task>`
- Code review: `/review`
- Commit: `/git-commit`
- Deep search: `/deep-search <keyword>`
- Note: `/note <content>`
- Task Master: `/taskmaster init`, `/taskmaster board`, `/taskmaster parse-prd`

## Coding Conventions
- Coding conventions detected in Step 1 (file naming, commit patterns, etc.)

## Key Dependencies
- Framework/library table detected in Step 1

## Module Structure
- Directory structure tree detected in Step 1
```

**`CLAUDE.md` is different from the optional `.claude/` directory in Step 0.1.**
- `.claude/settings.json` = Claude Code tool permission settings (machine-readable)
- `CLAUDE.md` = Project context + skill guide (AI-readable)

`CLAUDE.md` is part of the project guidance. `.claude/settings.json` is only needed when the user wants project-scoped Claude tool settings.

### Step 9: Report

Output setup summary to the user:
- Detected stack
- Generated file paths
- Project config directories: created/already exists/skipped
- State directory location
- Installed integration plugins:
  - Ralph workflow: installed / not installed
  - openai/codex: installed (CLI ready) / installed (CLI not authenticated) / not installed (skipped)
- Sub-agent team composition:
  - Claude agents: Scout, Architect, Builder, Inspector, Researcher
  - Codex agents: active/inactive (second opinion, adversarial review, root cause analysis)
- Available workflows:
  - In-session autonomous execution: `/auto <task description>`
  - Maximum parallel performance: `/auto <task description> --mode parallel-max`
  - PRD-based headless execution: `/prd` -> `/ralph` -> `ralph.sh`
  - Security baseline and audit: `/security status`, `/security scan`
- Recommended next steps
