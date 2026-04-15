---
name: evolve
description: "Detects project changes and synchronizes manifest.json and context.md."
argument-hint:
user-invocable: true
allowed-tools: [Read, Write, Edit, Glob, Grep, Bash, Agent]
---

# Evolve -- Project State Synchronization

Detects the current state of the project codebase and updates manifest.json and context.md to the latest.
If setup is a one-time initial snapshot, evolve is periodic synchronization.

## Entry Condition

`~/ai-symbiote/{slug}/manifest.json` must exist.
If it does not exist: guide with "Please initialize the project with the setup workflow first."

## Workflow

### Step 1: Load Baseline

Read the current manifest.json to establish the existing state as a baseline.

```
Baseline items:
- project.languages
- project.platforms (project target platforms: iOS, web, etc.)
- agentPlatforms (always keep ["claude", "codex"], not a change target)
- stack.packageManager
- stack.buildTool
- stack.frameworks
- stack.architecture
- stack.testFramework
- stack.cicd
- plugins.ralph.installed
- plugins.codex.installed
- plugins.codex.cliReady
```

### Step 2: 6-Track Parallel Re-detection

Re-run the same detection as setup's Step 1.
Run Glob, Grep, Read in parallel.

#### Track A -- Language Detection
- Glob for file extensions: `*.swift`, `*.kt`, `*.ts`, `*.tsx`, `*.js`, `*.py`, `*.go`, `*.rs`, `*.java`, `*.rb`, `*.cs`, `*.cpp`
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

### Step 3: Plugin Status Check

```bash
# ralph
(
  rg -l '"name"[[:space:]]*:[[:space:]]*"(ralph|ralph-skills)"' \
    "$HOME/.agents/plugins" \
    "$HOME/plugins" \
    ./.agents/plugins \
    ./plugins 2>/dev/null || true
) | head -1 | grep -q . && echo "ralph:installed" || echo "ralph:not-installed"

# codex runtime
codex --version 2>/dev/null && echo "codex-cli:ready" || echo "codex-cli:not-ready"
```

### Step 4: Generate Diff

Compare the baseline (Step 1) with re-detection results (Steps 2-3).

Change types:
- `[added]` Newly detected item (not in baseline)
- `[removed]` No longer detected item (was in baseline)
- `[changed]` Item with a different value

If no changes: output "Project state is up to date. No changes detected." and exit.

### Step 5: Change Report

Report only changed items to the user:

```
[Evolve] Project changes detected:

Languages:
  [added] Rust (Cargo.toml detected)

Frameworks:
  [added] Tailwind CSS (tailwind.config detected)
  [removed] Bootstrap (import pattern not detected)

Architecture:
  [changed] Layered -> Clean Architecture (/domain/, /data/ directories detected)

CI/CD:
  [added] GitHub Actions (.github/workflows/ci.yml detected)

Plugins:
  [changed] codex CLI ready (cliReady: false -> true)

Apply these changes to manifest.json and context.md? (yes/no):
```

### Step 6: Update (On User Approval)

1. Update manifest.json:
   - Update only changed fields
   - Set `lastEvolved` timestamp to current time
   - Preserve `security.sessionSummaryLevel` unless the evolve patch explicitly changes it
   - Preserve `agentPlatforms` as the union of existing values and `["claude", "codex", "cursor"]`

   Use the bundled helper to merge detected changes safely:

   ```bash
   PLUGIN_ROOT="${CURSOR_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-${CODEX_PLUGIN_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}}}"
   bash "$PLUGIN_ROOT/skills/evolve/scripts/manifest-merge.sh" \
     --manifest "$STATE_DIR/manifest.json" \
     --patch "$STATE_DIR/state/evolve-manifest-patch.json"
   ```

2. Regenerate context.md:
   - Rewrite context.md based on updated manifest
   - Preserve manually added sections in existing context.md (if any)
   - Project stack summary, coding conventions, file naming patterns, architecture patterns
   - Note: Harness/Seed rules are stored separately in harness-rules.md (not in context.md)

3. Completion report:
   ```
   [Evolve] Complete:
   - manifest.json updated
   - context.md updated
   - lastEvolved: {ISO8601}
   ```

## Auto-Recommendation (setup-check hook integration)

The setup-check hook recommends running evolve (not auto-run) under these conditions:

- `lastEvolved` is more than 7 days old
- Major dependency files (package.json, requirements.txt, etc.) have mtime newer than lastEvolved

Recommendation message:
```
Project state was last synchronized {N} days ago.
Run the evolve workflow to check for the latest state.
```

## Principles

- No auto-execution: always show the change report to the user and get approval
- Baseline preservation: show only changed items via diff (not full re-output)
- Manual additions preserved: retain content the user manually added to context.md
- Harness rules are in harness-rules.md (separate from context.md) — evolve does not touch harness-rules.md
- Minimal changes: do not touch files if there are no changes
