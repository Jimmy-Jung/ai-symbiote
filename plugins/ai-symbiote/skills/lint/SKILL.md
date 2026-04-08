---
name: lint
description: "Code hygiene check. Auto-detects project linter and runs it, or performs basic pattern checks for common code smells."
argument-hint: [--fix]
user-invocable: true
allowed-tools: [Read, Grep, Glob, Bash]
---

# Lint -- Code Hygiene Check

Detects bad code patterns that agents may have introduced.
Runs the project's configured linter or falls back to basic pattern checks.

Separated from gc (which manages harness rules) to maintain clear responsibility:
- **gc** = Pillar 3 (harness rule garbage collection)
- **lint** = Pillar 2 (code-level auto-enforcement)

## Entry Conditions

Project must have been initialized with setup (manifest.json exists).

## Workflow

### Step 1: Detect Project Linter

Check in order:
1. `manifest.json` → `stack.linter` field
2. `package.json` → `scripts.lint` field
3. Global commands: `eslint`, `swiftlint`, `pylint`, `ruff`, `flake8`

```bash
STATE_DIR=~/ai-symbiote/{slug}
# Check manifest first
LINTER=$(jq -r '.stack.linter // empty' "$STATE_DIR/manifest.json" 2>/dev/null)

# Fallback: package.json
if [ -z "$LINTER" ] && [ -f "package.json" ]; then
  HAS_LINT=$(jq -r '.scripts.lint // empty' package.json 2>/dev/null)
  [ -n "$HAS_LINT" ] && LINTER="npm run lint"
fi

# Fallback: global commands
if [ -z "$LINTER" ]; then
  for cmd in eslint swiftlint pylint ruff flake8; do
    command -v "$cmd" >/dev/null 2>&1 && LINTER="$cmd ." && break
  done
fi
```

### Step 2: Run Linter or Fallback Checks

**If linter found:**
- Run the linter command
- If `--fix` option: append `--fix` (or equivalent) to the linter command
- Capture output and display as report

**If no linter found:**
- Run basic pattern checks using Grep:
  1. Unused imports: `import .* // unused` or commented-out imports
  2. Commented-out code blocks: 3+ consecutive lines starting with `//` or `#`
  3. Console/debug statements: `console.log`, `print(`, `debugPrint(`
  4. Empty catch blocks: `catch {` followed by `}`

### Step 3: Report Results

```
[Lint] Code hygiene report:

Linter: {detected linter or "basic pattern check"}
Files scanned: {count}

Issues found ({total}):
  {severity}: {description} — {file}:{line}
  ...

Summary: {total issues} issues in {file count} files
```

If no issues found:
```
[Lint] Code hygiene report: No issues found.
```

## Options

- `--fix`: Auto-fix where possible (passes `--fix` to linter)
- No options: Report-only mode (default)

## Principles

- Never modifies code without `--fix` flag
- Silence on success is NOT applied here (always reports, even clean results)
- Complements gc — gc cleans rules, lint cleans code
