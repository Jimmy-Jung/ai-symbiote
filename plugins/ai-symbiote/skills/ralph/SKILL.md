---
name: ralph
description: "Convert a markdown PRD into Ralph's prd.json format and prepare the Codex-compatible autonomous loop. Triggers on: convert this prd, turn this into ralph format, create prd.json, ralph json, run ralph."
user-invocable: true
---

# Ralph PRD Converter

Convert an existing markdown PRD into `prd.json` for the Ralph-style autonomous loop and prepare the project-local state needed to run it in Codex.

## The Job

1. Read a PRD markdown file or PRD text.
2. Convert it into Ralph's `prd.json` structure.
3. Write the result to `~/ai-symbiote/{slug}/ralph/prd.json`.
4. Explain how to run the loop with `skills/ralph/scripts/ralph-loop.sh`.

## Output Format

```json
{
  "project": "Project Name",
  "branchName": "ralph/feature-name",
  "description": "Short summary of the feature",
  "userStories": [
    {
      "id": "US-001",
      "title": "Short title",
      "description": "As a [user], I want ...",
      "acceptanceCriteria": [
        "Concrete criterion",
        "Typecheck passes"
      ],
      "priority": 1,
      "passes": false,
      "notes": ""
    }
  ]
}
```

## Core Rules

### 1. One Story Per Iteration

Every story must be small enough to complete in one autonomous iteration.

Good size:

- Add one schema field and migration
- Add one UI component to an existing screen
- Add one server action or endpoint adjustment

Too large:

- Build the full dashboard
- Add all authentication
- Refactor the whole API layer

Split large stories aggressively.

### 2. Order by Dependency

Use priority order so earlier stories unblock later ones.

Preferred order:

1. Data / schema changes
2. Backend logic
3. UI that depends on that logic
4. Aggregate views or polish

### 3. Acceptance Criteria Must Be Verifiable

Always prefer checkable statements:

- Good: `Filter dropdown has options: All, High, Medium, Low`
- Bad: `Filtering works well`

Always include:

- `Typecheck passes`

Also include when applicable:

- `Tests pass`
- `Verify in browser using browser tooling`

### 4. Every Story Starts Incomplete

All generated stories must start with:

- `passes: false`
- `notes: ""`

## Archiving Rule

Before overwriting `~/ai-symbiote/{slug}/ralph/prd.json`:

1. Check whether a previous `prd.json` exists.
2. Compare the previous `branchName` to the new one.
3. If they differ and there is previous progress, preserve the old run under `~/ai-symbiote/{slug}/ralph/archive/YYYY-MM-DD-feature-name/`.

## Conversion Checklist

When converting:

1. Infer project name from the PRD title or repository.
2. Build `branchName` as `ralph/[feature-name-kebab-case]`.
3. Keep `priority` sequential and dependency-aware.
4. Normalize every acceptance criterion into plain strings.
5. Add missing `Typecheck passes` criteria.

## Running the Loop

After generating `prd.json`, the next step is:

```bash
bash "$PLUGIN_ROOT/skills/ralph/scripts/ralph-loop.sh" --project-root "<repo-root>"
```

Useful options:

```bash
bash "$PLUGIN_ROOT/skills/ralph/scripts/ralph-loop.sh" --project-root "<repo-root>" --tool codex --max-iterations 10
bash "$PLUGIN_ROOT/skills/ralph/scripts/ralph-loop.sh" --project-root "<repo-root>" --prepare-only
```

## Final Step

When done:

1. Save `prd.json` to the shared state directory.
2. Tell the user which PRD file was converted.
3. Tell the user the exact runner command that matches the current project.
