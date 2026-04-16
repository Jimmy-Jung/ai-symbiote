---
name: pr
description: Analyzes changes on the current branch and creates a Pull Request.
argument-hint: [base-branch]
user-invocable: true
allowed-tools: [Read, Glob, Grep, Bash]
---

# PR

Analyzes changes on the current branch and creates a Pull Request.

## Workflow

### 1. Load Context
- Read `~/ai-symbiote/{slug}/context.md` to understand project conventions

### 2. Analyze Changes
- Analyze changes with `git status`, `git diff`, `git log`
- If a base-branch is specified as argument, compare against that branch

### 3. Create PR
- PR title: under 70 chars, summarize changes
- PR body:
  ```
  ## Summary
  - Change summary (1-3 bullet points)

  ## Test Plan
  - Test plan checklist
  ```
- Push the branch and create PR with `gh pr create`

### 4. Result
- Return the PR URL to the user
