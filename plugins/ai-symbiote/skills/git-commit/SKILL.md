---
name: git-commit
user-invocable: true
description: Auto-generate commit messages matching project commit conventions. Analyzes git diff and generates in Conventional Commits format. This skill should be used when committing changes or when the user asks to commit.
---

# Git Commit

Auto-generates commit messages matching project commit conventions.

## Commit Type Table

| Type | Description | Example |
|------|-------------|---------|
| feat | New feature | feat(auth): add OAuth2 login flow |
| fix | Bug fix | fix(parser): improve null input handling |
| refactor | Code change with no behavior change | refactor(api): extract error handler |
| docs | Documentation change | docs: update API reference |
| test | Add/modify tests | test(auth): add login unit tests |
| chore | Build, tooling changes | chore: upgrade dependencies |
| style | Formatting, whitespace (no logic change) | style: fix indentation |
| perf | Performance improvement | perf(query): add user_id index |
| ci | CI config change | ci: add lint workflow |
| build | Build system change | build: migrate to new bundler |
| revert | Revert previous commit | revert: revert feat(auth) |

## Subject Rules

- type(scope) in English, subject in Korean
- Imperative/declarative tone (Korean: "추가", "수정", "개선" / English: add, fix, improve)
- No period
- 50 chars recommended, 72 chars absolute limit
- Concise but sufficiently descriptive

## Body Rules

- Blank line required between subject and body
- Written in Korean
- Explain WHY (WHAT is shown by the code)
- Line wrap at 72 chars

## Footer Rules

- BREAKING CHANGE: describe compatibility breakage
- Closes #issue-number
- Co-authored-by: Name <email>

## 6-Step Commit Workflow

1. Review staged changes (git diff --cached)
2. Determine type from change content
3. Identify scope (if applicable)
4. Write subject (imperative, concise)
5. Write body if needed (complex changes)
6. Execute commit

## Atomic Commit Principle

- One commit per logical change
- Each commit should be independently understandable

## Safety Considerations

- Never commit sensitive information: `.env`, `.env.*`, `credentials`, `secrets`, `*.key`, etc.
- Request user confirmation when warning patterns are detected
