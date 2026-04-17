---
name: prd
description: "Generate a Product Requirements Document (PRD) for a new feature. Use when planning a feature, starting a new project, or when asked to create a PRD. Triggers on: create a prd, write prd for, plan this feature, requirements for, spec out."
user-invocable: true
---

# PRD Generator

Create a detailed Product Requirements Document that is explicit enough for a junior developer or an autonomous coding loop to execute without guessing.

## The Job

1. Receive the feature description from the user.
2. Ask 3-5 essential clarifying questions only when the request is still ambiguous.
3. Generate a structured PRD in markdown.
4. Save it to `tasks/prd-[feature-name].md`.

Important:

- Do not start implementing.
- Do not leave TODOs or vague placeholders in the PRD.
- Keep user stories small enough to finish in one focused implementation session.

## Step 1: Clarifying Questions

Ask only the minimum questions needed to remove ambiguity. Focus on:

- Problem / goal
- Target user
- Core workflow
- Out-of-scope boundaries
- Success criteria

Use a compact answerable format:

```text
1. What is the primary goal?
   A. Improve onboarding
   B. Reduce support burden
   C. Increase retention
   D. Other: [specify]

2. Who is the target user?
   A. New users
   B. Existing users
   C. Admins
   D. All users
```

This allows short answers such as `1B, 2D`.

## Step 2: PRD Structure

Generate the PRD with these sections:

### 1. Introduction / Overview

Explain the feature and the problem it solves in a short paragraph.

### 2. Goals

Use a bullet list of concrete objectives.

### 3. User Stories

Each story must include:

- Title
- Description in `As a [user], I want [feature] so that [benefit]` form
- Acceptance Criteria as a verifiable checklist

Each story must be small enough to implement in one focused session.

Required format:

```markdown
### US-001: [Title]
**Description:** As a [user], I want [feature] so that [benefit].

**Acceptance Criteria:**
- [ ] Specific verifiable criterion
- [ ] Another verifiable criterion
- [ ] Typecheck or lint passes
- [ ] Tests pass (if applicable)
- [ ] Verify in browser using browser tooling (for UI stories)
```

Rules:

- Acceptance criteria must be testable and concrete.
- For any UI change, include browser verification.
- Avoid vague phrases like "works correctly" or "good UX".

### 4. Functional Requirements

Numbered requirements:

- `FR-1: ...`
- `FR-2: ...`

Be explicit about behaviors and triggers.

### 5. Non-Goals

List what this feature will not include.

### 6. Design Considerations

Optional section for reuse expectations, UI constraints, mockups, or linked references.

### 7. Technical Considerations

Optional section for dependencies, migrations, APIs, performance constraints, or rollout notes.

### 8. Success Metrics

Describe how success will be measured.

### 9. Open Questions

Capture any unresolved questions that remain after clarification.

## Writing Rules

- Be explicit and unambiguous.
- Prefer numbered and checklist-based structure.
- Explain jargon if needed.
- Use concrete examples when they help remove ambiguity.
- Do not skip file naming and output path.

## Output

- Format: markdown
- Location: `tasks/`
- File name: `prd-[feature-name].md`

## Final Step

When the PRD is complete:

1. Save it to `tasks/prd-[feature-name].md`.
2. Tell the user which file was created.
3. Suggest the next step: convert it with the `ralph` workflow or implement manually.
