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
- team members maintaining the project
- developers seeing the project for the first time

Output style:
- Korean by default
- Mermaid-heavy across all generated docs
- code is the source of truth
- manually written prose is preserved

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

Implement the work in three stages. Keep the stages conceptually separate even if the edits are small.

### 1. Scan

Build one shared repo snapshot. Do not rescan the repo independently for each document.

Scan these sources first:

```bash
README.md
docs/*.md
shared/skills/*/SKILL.md
shared/hooks/scripts/*
platforms/*/overlay/*
plugins/ai-symbiote/.claude-plugin/plugin.json
scripts/build-*.sh
tests/*
.github/workflows/*
```

Capture:
- top-level directory structure and roles
- build and install paths
- platform differences
- recurring workflow entrypoints
- existing docs and their marker state
- Mermaid candidates backed by code
- manual prose that may conflict with code-derived facts

### 2. Model

Produce one internal documentation model from the snapshot:
- document targets
- headings/section ids
- reusable repo facts
- Mermaid candidates
- conflict list

Also build a small document registry in-memory with:
- `id`
- `path`
- `title`
- `owned sections`
- `diagram policy`

Do not scatter per-document logic through ad hoc `if/else` blocks.

The first implementation may keep this model inside a shell script as explicit variables and content templates, as long as scan, model, and render responsibilities stay separated.

### 3. Render / Update

For each selected document:
- ensure the expected headings exist
- ensure the marker blocks exist
- render generated text + Mermaid blocks into the owned sections only
- preserve manual prose outside markers

Use the updater helper for marker-safe writes:

```bash
bash shared/skills/dev-docs/scripts/update-doc-section.sh \
  <file> <doc-id> <section-id> "<heading-line>" <content-file>
```

Use the generator entrypoint to update one or more docs from a repo snapshot:

```bash
bash shared/skills/dev-docs/scripts/generate-dev-docs.sh [repo-root] [all|readme|architecture|conventions|onboarding|dependencies|flows ...]
```

If code-derived facts conflict with manual prose:
- do not silently overwrite the manual prose
- add or update a generated `검토 필요` subsection in the relevant document
- summarize the mismatch briefly and point to the evidence path

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
