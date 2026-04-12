---
name: dev-docs
description: "Generates and updates Mermaid-heavy developer docs from code."
argument-hint: "[all|readme|architecture|conventions|onboarding|dependencies|flows]"
user-invocable: true
allowed-tools: [Read, Write, Edit, Glob, Grep, Bash]
---

# Dev Docs -- Mermaid-Heavy Developer Documentation

Generates and updates developer-facing documentation from the codebase.

Primary users:
- plugin users (user-facing explanations take priority)
- contributor-facing explanations live in manually written sections

Output style:
- Korean by default
- Mermaid-heavy across all generated docs
- code is the source of truth
- manually written prose is preserved

## Workflow Ownership

This SKILL.md workflow is the primary source for document generation.

- `generate-dev-docs.sh` is a baseline fallback only (Codex bundles, standalone execution).
- Do NOT run `generate-dev-docs.sh` after the workflow has enriched the docs (it would overwrite rich content with thin heredoc output).
- `update-doc-section.sh` is the marker-safe write utility, used by both the workflow and the fallback.

## Scope

Managed documents:

| id | path | purpose |
|----|------|---------|
| `readme` | `README.md` | Thin project hub, quick start, links to deeper docs |
| `architecture` | `docs/ARCHITECTURE.md` | System structure, subsystem boundaries, build path |
| `conventions` | `docs/CONVENTIONS.md` | Editing rules, naming, generated-output boundaries |
| `onboarding` | `docs/ONBOARDING.md` | First-day reading order and local workflow |
| `dependencies` | `docs/DEPENDENCIES.md` | External tools, plugins, platform-specific dependencies |
| `flows` | `docs/FLOWS.md` | Data flow, user flow, and operational flow |

Default invocation updates all six.

If the argument matches one or more ids above, update only those documents.

Examples:
- `dev-docs`
- `dev-docs flows`
- `dev-docs architecture onboarding`

## Ownership Contract

This skill only edits AI-owned sections. Preserve everything else.

Use explicit markers:

```markdown
<!-- AI-SYMBIOTE:START <doc-id>:<section-id> -->
...generated content...
<!-- AI-SYMBIOTE:END <doc-id>:<section-id> -->
```

Rules:
- If a target file does not exist, create it with the expected headings and marker blocks.
- If the file exists, only replace content inside matching marker blocks.
- If markers do not exist, add the missing block under the correct heading.
- Never rewrite or reorder manually written sections outside marker blocks.

## Fixed Section Contract

Each document has fixed generated slots. Do not invent new top-level sections unless the repo clearly needs one.

### `README.md`

- `overview`
- `quick-start`
- `docs-map`

`README.md` must stay thin. It is a hub, not the full manual.

### `docs/ARCHITECTURE.md`

- `system-overview`
- `subsystems`
- `build-flow`
- `platform-differences`

### `docs/CONVENTIONS.md`

- `editing-rules`
- `naming-layout`
- `generated-boundaries`
- `decision-tree`

### `docs/ONBOARDING.md`

- `first-day-path`
- `read-order`
- `local-checks`
- `common-tasks`

### `docs/DEPENDENCIES.md`

- `dependency-map`
- `runtime-dev-tools`
- `platform-dependencies`
- `update-path`

### `docs/FLOWS.md`

- `system-flow`
- `data-flow`
- `user-or-operator-flow`
- `operational-flow`

## Mermaid Policy

Mermaid is the default visualization format across all managed docs.

Use Mermaid when it clarifies structure or flow better than prose:
- `flowchart` for subsystem layout, dependency maps, decision trees, operational pipelines
- `sequenceDiagram` for step-by-step interactions
- `stateDiagram-v2` for state transitions when a state machine is explicit

Keep diagrams readable:
- prefer 7-10 nodes per diagram
- split complex topics into overview + detail diagrams
- label nodes with human concepts first, optionally adding file/module names in parentheses

Examples of where Mermaid belongs:
- `README.md`: one high-level system overview
- `ARCHITECTURE.md`: subsystem map, build flow
- `CONVENTIONS.md`: "where should I edit?" decision tree
- `ONBOARDING.md`: first-day path and local verification flow
- `DEPENDENCIES.md`: dependency map and platform split
- `FLOWS.md`: system/data/user/operational flows

## Confidence-Based Fallback

Do not generate confident-looking lies.

Before rendering a Mermaid block, decide whether the repo gives enough evidence.

Good evidence:
- clear scripts, configs, imports, folder boundaries, docs, or tests that support the flow
- existing Mermaid or prose that matches the code

Weak evidence:
- ambiguous naming
- multiple plausible flows with no single clear winner
- UI/screen flow requested in a repo with no visible UI surface

If confidence is high:
- render the Mermaid block normally

If confidence is medium or low:
- do not force a diagram
- instead render a generated `확인 필요` block with:
  - what is known
  - what is ambiguous
  - which files or modules should be checked next

The first implementation may use simple evidence gates such as:
- build flow diagrams require `scripts/build-*.sh` or equivalent pipeline evidence
- platform diagrams require overlay/config evidence
- operator flow diagrams require repeatable script or command evidence

## Internal Pipeline

This workflow runs inside a Claude Code session. Claude reads source files directly and generates rich contextual descriptions.

Execute the three stages in order. Do not interleave other work between stages.

### 1. Scan (Deep Scan)

Build one shared repo snapshot. Do not rescan per document.

Read these sources in order:

**Skill catalog:**
1. `Glob: shared/skills/*/SKILL.md` to get file list
2. Read each SKILL.md with `limit=10` to extract frontmatter (name, description, user-invocable, argument-hint)
3. Classify skills into categories:
   - Orchestration: synapse, team-templates, roles, auto, verify-loop
   - Code work: git-commit, code-accuracy, deep-search, analyze, review, lint
   - Documentation: dev-docs, note, contribute
   - Store/discovery: cli-store, mcp-store, skill-store
   - Project management: taskmaster, setup, evolve, clean, plan, planning
   - Execution/integration: messenger, gc, update, stats, pr

**Hook architecture:**
4. `Read: platforms/claude/overlay/hooks/hooks.json` for full event-matcher-script mapping
5. `Read: platforms/codex/overlay/hooks/hooks.json` for Codex limitations comparison
6. Read each file in `shared/hooks/scripts/*.sh` with `limit=30` to extract role and key behavior from header comments

**Intent routing:**
7. `Read: shared/skills/synapse/SKILL.md` focusing on Mode Detection / Intent Contract. Extract 7 intent types (none, analysis, implementation, review, planning, research, dynamic) and Skill Direct Routes
8. `Read: shared/skills/team-templates/SKILL.md` to extract 6 team templates with ADK patterns, phases, role composition
9. `Read: shared/skills/roles/SKILL.md` to extract 6 roles (Scout, Architect, Builder, Inspector, Researcher, Codex) with models, subagent types, injected skills

**Build/deploy:**
10. `Read: scripts/build-*.sh` (each with `limit=20`) to extract build pipeline steps
11. `Read: plugins/ai-symbiote/.claude-plugin/plugin.json` for plugin name and skill paths

**Existing doc state:**
12. Read each file in `docs/*.md` to identify existing marker block positions and manually written sections

### 2. Model

Map scan results to 23 sections. Keep in context only, no intermediate file output.

For each section, determine:
- which scan sources provide the information
- Mermaid diagram type (flowchart / sequenceDiagram / none)
- prose focus (user-facing: "what does this feature do")
- confidence level (high / medium / low)

**Section mapping:**

| Doc | Section ID | Primary sources | Diagram |
|-----|-----------|----------------|---------|
| README | overview | plugin.json, skill catalog summary | none |
| README | quick-start | setup skill, build scripts | none |
| README | docs-map | docs/ listing | none |
| ARCHITECTURE | system-overview | full directory structure, skill count, hook count | flowchart (system layers) |
| ARCHITECTURE | subsystems | skill categories list, hook table | flowchart (category to skills) |
| ARCHITECTURE | build-flow | build scripts, overlay structure | flowchart (shared to overlay to bundle) |
| ARCHITECTURE | platform-differences | Claude hooks.json vs Codex hooks.json | none (comparison table) |
| CONVENTIONS | decision-tree | directory structure, build artifact boundaries | flowchart (decision tree) |
| CONVENTIONS | editing-rules | shared/ vs plugins/ vs docs/ roles | none |
| CONVENTIONS | naming-layout | SKILL.md frontmatter required fields, file patterns | none |
| CONVENTIONS | generated-boundaries | marker system, build artifact boundaries | none |
| ONBOARDING | first-day-path | doc reading order, environment setup | flowchart (read to setup to verify) |
| ONBOARDING | read-order | each doc's role and what to look for | none |
| ONBOARDING | local-checks | test and build commands | sequenceDiagram |
| ONBOARDING | common-tasks | add skill, update docs, modify hooks procedures | none |
| DEPENDENCIES | dependency-map | external tool list | flowchart (tool relationships) |
| DEPENDENCIES | runtime-dev-tools | bash, rsync, grep/sed/awk, jq with usage context | none |
| DEPENDENCIES | platform-dependencies | Claude vs Codex bundle differences | flowchart (shared to bundles) |
| DEPENDENCIES | update-path | build-all.sh, platform-specific builds | none |
| FLOWS | system-flow | synapse Intent Contract, team composition, role execution | flowchart (request to intent to team to roles) |
| FLOWS | data-flow | manifest.json to context.md to harness-log flow | flowchart |
| FLOWS | user-or-operator-flow | skill invocation to result verification experience | sequenceDiagram |
| FLOWS | operational-flow | code change to build to install | flowchart |

### 3. Render

Render all 23 sections in order.

**New sections (no existing marker or heading) must place headings first:**

1. Check if the heading exists in the file via Grep
2. If missing, use the Edit tool to insert the heading at the correct position:
   - README: `## Overview` right after `# ` title line, `## Quick Start` after Overview
   - ARCHITECTURE: `## System Overview` right after `# ` title line, `## Platform Differences` after Build Flow section
3. After placing the heading, call `update-doc-section.sh`

**Existing sections (marker already present):**
1. Call `update-doc-section.sh` directly (marker replacement path)

**Render invocation per section:**

```bash
# 1. Write content to temp file
TMP_CONTENT=$(mktemp)
cat > "$TMP_CONTENT" << 'SECTION_EOF'
(prose + Mermaid + detail list)
SECTION_EOF

# 2. Call update-doc-section.sh
bash shared/skills/dev-docs/scripts/update-doc-section.sh \
  <file> <doc-id> <section-id> "<heading-line>" "$TMP_CONTENT"

# 3. Cleanup
rm -f "$TMP_CONTENT"
```

**Content structure per section:**

1. **Prose explanation** (2-5 sentences): what this section covers and why it matters. Written from the plugin user perspective.
2. **Mermaid diagram** (when applicable): type determined in Model stage. 7-10 nodes. Korean labels in generated output.
3. **Detail table or list**: specific items (skill names+descriptions, hook events+behavior, dependencies+usage, etc.)
4. **Context annotations** (when applicable): e.g. "Changed from keyword routing to Intent Contract in v0.8.0"

**When code-derived facts conflict with manual prose:**
- Do not overwrite manual prose
- Add a `검토 필요` subsection inside the generated section
- Briefly summarize the mismatch and point to the evidence path

**When confidence is low:**
- Do not force a Mermaid diagram
- Generate a `확인 필요` block with:
  - what is currently known
  - why the evidence is ambiguous
  - which files or modules to check next

### Fallback: generate-dev-docs.sh

For environments where the workflow is unavailable (Codex, CI/CD, standalone), use the existing `generate-dev-docs.sh`:

```bash
bash shared/skills/dev-docs/scripts/generate-dev-docs.sh [repo-root] [all|readme|architecture|conventions|onboarding|dependencies|flows ...]
```

This script covers only 19 of 23 sections and produces baseline heredoc content. It cannot replace the rich content generated by the workflow.

## Content Rules by Document

### README

`README.md` should contain:
- short project overview
- shortest useful setup path
- links to deeper docs in `docs/`

Do not duplicate the detailed content from `ARCHITECTURE`, `DEPENDENCIES`, `ONBOARDING`, or `FLOWS`.

### ARCHITECTURE

Must explain:
- what lives in `shared/`, `platforms/`, `plugins/`, `dist/`, `scripts/`, `docs/`
- which directories are sources of truth
- how build output is produced

Include Mermaid:
- subsystem overview
- build/copy flow

### CONVENTIONS

Must explain:
- where to edit versus generated output
- naming/layout expectations already visible in the repo
- how to decide where a new change belongs

Include Mermaid:
- decision tree for "which directory should I touch?"

### ONBOARDING

Must optimize for a new developer.

Include:
- what to read first
- what command to run first
- how to verify the local environment
- which files explain the repo fastest

Include Mermaid:
- first-day flow

### DEPENDENCIES

Explain:
- external CLIs and platform tooling
- plugin/runtime dependencies
- repo-local build dependencies
- which dependencies are optional vs required

Include Mermaid:
- dependency map

### FLOWS

This is the most diagram-heavy document.

Always include:
- system overview flow
- data flow if data movement is visible
- user flow if UI exists, otherwise operator/developer flow
- operational flow such as build/install/update/release

## Test Expectations

When you implement or update this skill, keep tests aligned with the repo's shell-based integration pattern.

Required test categories:
- fixture/golden regression test for marker-only updates
- Mermaid two-layer test:
  - valid Mermaid block generation
  - fallback to `확인 필요` when confidence is insufficient
- selective update isolation test:
  - `dev-docs flows` only changes `docs/FLOWS.md`
  - `dev-docs architecture` only changes `docs/ARCHITECTURE.md`
- updater integration test for replace / insert / append behavior
- generator integration smoke test for all six docs on a temp repo fixture
- selective update isolation test for `flows` and `architecture`
- low-confidence fallback test that emits `확인 필요` instead of Mermaid

## Completion Report

When the skill finishes, report:
- which documents were created
- which were updated
- which Mermaid diagrams were generated
- which sections were left as `확인 필요`
- any manual prose conflicts surfaced for review
