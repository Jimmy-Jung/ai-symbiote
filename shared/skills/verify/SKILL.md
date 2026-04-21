---
name: verify
description: "Write-time Verification Layer. Processes queued edits via cold-read reviewer + LLM judge to expose opaque decisions. Triggers on: verify, run verify, process verification, check reasoning, verify queue."
argument-hint: [--all | --sha <sha> | --file <path> | --dry-run]
user-invocable: true
allowed-tools: [Read, Write, Edit, Glob, Grep, Bash, Skill, Agent]
---

# Verify -- Write-time Verification Layer

Measure and remove opacity in AI-authored code behaviorally. The PostToolUse hook
queues edit events into `~/.ai-symbiote/state/verify-queue.jsonl`; `/verify`
drains that queue through the cold-read reviewer + LLM judge pipeline.

Design background: `docs/02-아키텍처.md` ("Write-time Verification Layer" section)
and the office-hours design doc (Stage 0 / Stage 1).

## Entry Conditions

- One or more pending entries for the current project/branch exist in `~/.ai-symbiote/state/verify-queue.jsonl`
- OR `--sha` / `--file` specifies an explicit target
- The `codex` CLI is on PATH and `codex login` has completed
- The current directory is a git repository

If `codex` is unavailable, fall back to a Claude subagent (degraded mode).

## Workflow

### Step 1: Queue read + filtering

```bash
QUEUE_FILE="$HOME/.ai-symbiote/state/verify-queue.jsonl"
REPO_ROOT=$(git rev-parse --show-toplevel)
PROJECT=$(basename "$REPO_ROOT")
BRANCH=$(git branch --show-current)
```

Filter key priority:
1. **Schema v2 (preferred)**: `repo_root == $REPO_ROOT AND branch == $BRANCH`
2. **Schema v1 fallback**: legacy entries without a `repo_root` field match on `project == $PROJECT AND branch == $BRANCH`

`--sha` / `--file` AND additional conditions on top. `--sha` compares against
both `base_sha` and legacy `sha` fields.

When zero entries remain, exit with:
```
No pending verifications for {project}/{branch}. Queue empty.
```

### Step 2: User confirmation + batch cap

```
[Verify] {N} pending verifications for {project}/{branch}:
- SHA abc123 / file: src/foo.ts
- SHA def456 / file: src/bar.ts
...

Estimated: ~60s × {N} = ~{total}s, ~${cost} USD.
Proceed? [Y/n]
```

**Batch cap (cost safety)**:
- `N ≤ 10` → process everything with a single confirmation
- `N > 10` → process the first 10 only; leave the rest in the queue; user
  re-invokes for the next batch
- `--max-batch <n>` overrides the default of 10 (cap is the operator's judgment)
- `{cost}` estimate is ~$0.15 USD per entry (Codex medium-reasoning reviewer +
  judge), deliberately conservative

`Y` → proceed to Step 2.5.
`n` → exit (queue untouched).
`--dry-run` → print queue contents and exit.

### Step 2.5: Pre-flight machine checks

Before calling the reviewer, run the project's native machine checks against
each entry's diff. Inject results into the reviewer prompt's `INPUT` section so
the cold-read reviewer can convert AI-generated-code opacity patterns (unused
imports, any-type drift, failing tests, etc.) directly into sharper questions.

**Detection rules** (executed only when detected at repo root):
- `package.json` + `scripts.typecheck` → `npm run typecheck`
- `tsconfig.json` without a typecheck script → `npx tsc --noEmit`
- `pyproject.toml` or `setup.cfg` → `ruff check .` (if installed) + `python -m pytest --collect-only`
- `Cargo.toml` → `cargo check --message-format=short`
- `go.mod` → `go vet ./...`
- `.swiftlint.yml` → `swiftlint lint --quiet`
- Generic lint: run `npm run lint` / `eslint` / `shellcheck` / `bats` when detected

**Execution rules**:
- Each command has a 30-second timeout. On timeout, record `"(pre-flight: timeout)"` and continue
- Non-zero exit: capture the first 30 lines of stdout/stderr and pass to the reviewer prompt
- No detection: record `"(pre-flight: no machine checks configured)"`
- **Not a hard gate**. A failing check does NOT block the reviewer; the goal is to provide opacity hints.

**Output format** (inlined into the reviewer prompt's INPUT section):
```
PRE-FLIGHT MACHINE CHECKS:
- typecheck: PASS (0 errors)
- lint: FAIL (3 warnings; first: src/foo.ts:42 unused import)
- test: (pre-flight: timeout)
```

### Step 3: Reviewer call (per entry)

For each entry:

1. **Diff collection — base_sha contract**

   The queue's `base_sha` is the **pre-edit HEAD**. Do NOT use `git show <base_sha>`:
   it returns the **prior commit's** changes. The correct contract:

   - `base_sha == "uncommitted"` (repo has no commits yet)
     → `git diff --no-index /dev/null <file>` or `git diff -- <file>` (full working-tree state)

   - Current `HEAD == base_sha` (edit has not been committed yet)
     → `git diff <base_sha> -- <file>` (unstaged edit)
     → `git diff --cached <base_sha> -- <file>` (staged edit)
     → merge both outputs into what the reviewer sees

   - Current `HEAD != base_sha` (one or more commits landed after the edit)
     → `git diff <base_sha>..HEAD -- <file>` (committed change since base)
     → **ALSO** `git diff HEAD -- <file>` (unstaged) and `git diff --cached -- <file>` (staged):
       the queued edit may have been committed *and* then further modified.
       Concatenate all three diffs so the reviewer sees the current state of
       the file, not just the committed delta
     → optionally append `git log --oneline <base_sha>..HEAD -- <file>` as commit context

   - Legacy entries without `base_sha` (schema v1)
     → treat the `sha` field as `base_sha` and reapply the rules above

   **Edge case**: if the file was deleted or reverted and the diff is empty,
   record "`(no changes — file reverted or deleted)`" and skip to Step 7.

2. **Reviewer prompt assembly** (see "Reviewer Prompt Template" below).
   Pass the prompt via a temp file, not via argv interpolation, so diff
   content containing backticks, `$(...)`, or other shell metacharacters
   cannot affect the invocation:
   ```bash
   PROMPT_FILE=$(mktemp /tmp/verify-prompt-XXXXXX)
   printf '%s' "$PROMPT" > "$PROMPT_FILE"
   ```

3. **Codex invocation**. Do NOT `source` anything from `~/.claude/` before
   running Codex, the read-only sandbox depends on Codex's own workdir
   argument; sourcing arbitrary home files first gives uncontrolled code
   control over `$PROMPT`, `$PATH`, and the child's environment. Invoke
   Codex directly with an explicit workdir and pass the prompt via stdin:
   ```bash
   codex exec "$(cat "$PROMPT_FILE")" -C "$(git rev-parse --show-toplevel)" \
     -s read-only -c 'model_reasoning_effort="medium"' --json < /dev/null
   rm -f "$PROMPT_FILE"
   ```
   Parse only `item.completed` / `agent_message` from the JSON stream to
   harvest questions.

4. Persist the emitted questions and proceed to Step 3.5.

### Step 3.5: Random question subset selection (V2c gaming defense — required)

The reviewer emits 3 roles × 2-3 questions = **pool size N = 5~8**. The author
answers a **randomly selected K = 3** subset of that pool. This blocks the
attack where the author prepares answers to every possible question in advance
(seeding).

**Selection algorithm**:
1. Drop duplicate pairs flagged in the reviewer's "Diversity check"; the remainder is `pool`
2. `len(pool) < 3` → verification FAILS with `reviewer_underrun` status.
   Record the raw reviewer output in the artifact under `## Reviewer Errors`
   and leave the entry in the queue for retry. Do NOT skip to Step 7:
   a too-small pool usually means the reviewer parser hit an error, the
   reviewer hit a guardrail, or the reviewer produced near-duplicate output.
   Any of these would let an opaque edit bypass verification silently if we
   treated them as "trivial verification"
3. `len(pool) ≥ 3` → seed the RNG with `sha + current_timestamp` for deterministic reproducibility of logs. Pick 3 independent entries from `pool`
4. Pass only the K=3 to Step 4. Record unselected questions in the artifact's `skipped_by_v2c` section (transparency)

**Exception — `--all-questions` flag**:
- Use for debugging only, when answering the full pool is desired
- The artifact gets `v2c_bypassed: true` as a warning
- Forbidden in production runs (it is a declaration that gaming resistance has been dropped)

### Step 4: Author answer generation

Pass the questions to the current Claude session (the context this skill runs
in = the author model) and request answers.

**Answer rules** (make them explicit to the author):
- MUST reference a specific code line / identifier
- MUST mention at least one alternative that was considered
- "I don't know" or "the AI just generated it" are valid answers, but they trigger rewrite

### Step 5: V1 Validator (Basic)

For each answer:
- V1a length ≥ 50 chars
- V1b has a code-reference pattern (`[\w/.-]+:\d+` or a backticked identifier)
- V1c no "I don't know / no reason" keywords (Korean "모르겠음 / 그냥" also rejected)
- V1d mentions at least one alternative ("instead / could have / rejected / considered" — Korean "대신" also accepted)

V1 fail → enter the rewrite loop immediately (regenerate the answer only).

### Step 6: V2 Validator — LLM Judge Verifiability Check ⭐

**Required mechanism**. Codex adjudication detects gaming.

```
You are a strict LLM judge evaluating whether a code author's reasoning is
CAUSALLY linked to the code, or post-hoc fabrication paraphrased from the PR body.

PASS = claims verifiable from code/artifacts (benchmark file, comments, referenced
data, test case, or visible code structure).
FAIL = claims plausible-but-fabricated. Numerical claims, measurements, or
specific data without corresponding artifacts in the code = FAIL. Paraphrase of
PR body text without independent evidence = FAIL.

For each answer, output:
- VERDICT: PASS | FAIL
- REASON: one sentence explaining verifiability

Final line: OVERALL: GAMING_DETECTED | GENUINE
```

Judge call inputs: `(CODE, PR_BODY or commit_message, QUESTIONS, ANSWERS)`.

Judge model: default Codex (must differ in vendor from the author). Fall back
to a Claude subagent only when the author is Codex.

Judge returns `GAMING_DETECTED` → full rewrite loop.
Judge returns `GENUINE` + every V1 passes → verification PASS.

### Step 7: Artifact persistence

Path: `.ai-symbiote/qa/<project>/<YYYY-MM-DD>/<sha-or-timestamp>.md`

Format:
```markdown
# Verification — <sha> (<branch>)

Generated: <ts>
File(s): <list>
Reviewer: codex / <model>
Judge: codex / <model>
Result: PASS | FAIL

## Pre-flight Machine Checks
- typecheck: PASS | FAIL | (skipped)
- lint: ...
- test: ...

## Questions (answered, K=3 selected from pool of N)
Q1: ...
Q2: ...
Q3: ...

## Questions (skipped_by_v2c)
Q4: ...
Q5: ...

## Answers
A1: ...
A2: ...
A3: ...

## Validator Report
- V1a~d: PASS/FAIL per rule
- V2a bigram overlap: {%}
- V2b judge verdict:
  - A1: PASS — ...
  - A2: FAIL — ...
  - OVERALL: GENUINE | GAMING_DETECTED
- V2c pool size: N, answered: K, bypassed: false

## Rewrite Notes (if applicable)
<feedback to author>
```

### Step 8: Remove queue entry

Delete entries that finished as PASS. Leave FAIL entries in the queue for the
next `/verify` retry.

### Step 9: Results summary

```
[Verify] Completed {N} verifications:
  PASS: {p}  FAIL: {f}  ERROR: {e}

PASS artifacts:
  .ai-symbiote/qa/{project}/2026-04-20/abc123.md
  ...

FAIL artifacts (require rewrite):
  .ai-symbiote/qa/{project}/2026-04-20/def456.md
  ...

Next: review FAIL artifacts and refactor per feedback.
```

## Reviewer Prompt Template

```
IMPORTANT: Do NOT read or execute any files under ~/.claude/, ~/.agents/,
.claude/skills/, or agents/. Stay focused on the repository code only.

You are executing Stage 1 write-time verification. Generate probing "why?"
questions as THREE independent cold-read reviewers. You have NO conversation
context — only the diff + commit message below.

Rules (every question):
- Reference specific file + line/identifier (no generic questions)
- Must be specific enough that "I just wrote it that way" cannot pass
- Format: Qn: [question] — ref: path/file.ext:line

## Reviewer Roles

### Reviewer 1 — Intent Reviewer
Check commit-message vs diff alignment. Out-of-scope additions. Missing pieces
the message implies. Produce 2-3 questions.

### Reviewer 2 — Structural Reviewer
Check why new abstractions/structures exist. Could simpler inline code have
worked? Are existing utilities being re-implemented? Produce 2-3 questions.

### Reviewer 3 — Alternative Reviewer
Check whether an obvious boring alternative was skipped. Custom impl vs
stdlib/existing tooling. Produce 2-3 questions.

## Output

== Reviewer 1 (Intent) ==
Q1: ...
Q2: ...

== Reviewer 2 (Structural) ==
Q1: ...

== Reviewer 3 (Alternative) ==
Q1: ...

== Diversity check ==
List near-duplicate pairs as Rx-Qy ↔ Rz-Qw.

## Input

COMMIT MESSAGE:
<commit_message>

DIFF:
<diff>
```

## Validator Rules (Enhanced v2)

### V1 Basic (Necessary but not Sufficient)
- V1a length ≥ 50 chars
- V1b has code reference pattern
- V1c no "I don't know" keywords
- V1d mentions ≥ 1 alternative

### V2 Gaming Resistance (Required Defense)
- **V2a** PR body vs answer bigram overlap > 40% → seeding suspicion flag
- **V2b** LLM judge verifiability check → `GAMING_DETECTED` = fail (the real block)
- **V2c** Reviewer emits a pool of N=5~8; author answers only a random K=3 subset (see Step 3.5). Blocks predictive seeding. Only `--all-questions` can bypass.

Stage 0 empirical (2026-04-20): V1 alone let 3/3 gaming cases through. V2b judge
is the real block; V2c randomization raises the attacker's preparation cost.
**All three are required.**

## Platform Support

- **Claude**: both hook queue and `/verify` skill supported
- **Codex**: only the `/verify` skill is available (no Write|Edit PostToolUse hook, so no auto-queue). Use `/verify --sha <sha>` or `--file <path>` explicitly.

## Fallback Mode

Degraded mode when the `codex` CLI is absent from PATH or `codex login` has
not completed. **The Agent tool MUST be listed in this skill's frontmatter
`allowed-tools` for this mode to work.**

1. **Reviewer fallback**: spawn a Claude subagent via `Agent` as the cold-read reviewer. It generates the question pool using the same 3-roles prompt. Record a diversity-loss warning in the artifact.
2. **Judge fallback**: spawn a **separate** Claude subagent for the V2b verifiability check. Do NOT reuse the reviewer subagent (that would be outright collusion). Record a collusion-risk warning in the artifact.
3. **Artifact flags**: write `degraded_mode: true`, `reviewer: claude-subagent`, `judge: claude-subagent` into the Validator Report.
4. **User notice**: the results summary must include "⚠️ DEGRADED_MODE — reviewer and judge are both Claude-based. Recommend restoring Codex: `codex login`".

**Forbidden fallback patterns**:
- Calling reviewer and judge in the **same** session as the author (that is effectively self-review)
- Pasting the reviewer subagent's output directly into the judge subagent's prompt and handling both in one session (single-session collusion)

Principle: **conversation-context isolation between subagents**. Rely on the fact
that each `Agent` invocation is an independent session.

## Arguments

- `--all` (default): process every pending entry for the current project/branch (batch cap applies)
- `--sha <sha>`: process the matching sha only
- `--file <path>`: process entries related to the given file only
- `--dry-run`: print queue contents and exit without calling out to models
- `--max-batch <n>`: override the default 10-entry per-invocation cap (Step 2)
- `--all-questions`: bypass V2c randomization and answer the full pool. Debug-only, forbidden in production.

## Related Skills

- `gc` — prune stale queue entries / qa artifacts (future gc extension)
- `ship` / `pr` — attach qa/ artifacts to the PR body (future integration)
- `investigate` — reference when debugging a FAIL cause

## Important Rules

- **Never skip V2b judge check**. V1 alone cannot detect gaming (Stage 0 empirical).
- **Never skip V2c randomization**. `--all-questions` is debug-only; any production artifact carrying `v2c_bypassed: true` is an invalid verification.
- **Judge model MUST differ from the author's vendor**. Config override forbidden.
- **Every artifact lives under `.ai-symbiote/qa/`**. Permanent path that can be linked from a PR body.
- **Delete queue entries only after PASS**. FAIL stays in the queue and retries on the next `/verify`.
- **User-invoked only**. Never auto-run (would disrupt the edit flow).
- **Do not bypass the batch cap**. Pushing more than 10 entries in one call risks a cost incident. Chunk by 10.
- **Pre-flight is not a hard gate**. Continue the Q&A even when the machine checks fail; pass the failure text to the reviewer so it can ask sharper questions.
