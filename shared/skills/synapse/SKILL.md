---
name: synapse
user-invocable: true
description: AI agent orchestration. Analyzes user intent to select the appropriate skill and workflow. Automatically applied as the entry point for all tasks.
---

# Synapse -- Team Leader Orchestrator

Synapse is the leader of the sub-agent team.
It analyzes tasks, assembles teams, dispatches sub-agents, and synthesizes results.

## Bootstrap Check

Checks project state at session start.
State directory: `~/ai-symbiote/{project-slug}/`

- If manifest.json is missing, guide to setup workflow (plan-first)
- If manifest.json exists, read `~/ai-symbiote/{slug}/context.md` to load project context
- If a task-folder with `active: true` exists in `~/ai-symbiote/{slug}/state/*/ralph-state.md`, determine whether to resume

## Dynamic Context Loading

Dynamically loaded from `~/ai-symbiote/{slug}/context.md`:

- Project stack
- Coding convention summary
- Active skill list

## Routing

### Skill Direct Routes

When specific keywords are detected, run the matching skill/workflow directly without composing a team:

| Pattern | Action |
|---------|--------|
| "skill recommend", "skill install", "skill store" | Run skill-store skill |
| "cli recommend", "cli install", "cli store" | Run cli-store skill |
| "mcp recommend", "mcp install", "mcp store" | Run mcp-store skill |
| "setup", "initialize project", "bootstrap project", "프로젝트 설정", "초기 설정" | Run setup skill in plan mode |
| "messenger", "notification setup" | Run messenger skill |
| "security scan", "security audit", "security status", "보안 점검", "보안 상태" | Run security skill |
| "project update", "sync state", "stack change", "evolve" | Run evolve skill |
| "requirements", "PRD", "feature planning" | Run PRD workflow |
| "cancel", "abort" | Abort current loop |
| "help", "usage" | Show available skills/commands |

### Setup First Response Contract

When the request is routed to `setup`, the first response must be a **Setup Plan** summary, not execution.
Use [setup-plan.md](shared/skills/setup/templates/setup-plan.md) as the source-of-truth template, and fill it via [render-setup-plan.sh](shared/skills/setup/scripts/render-setup-plan.sh).
The concrete entrypoint is [begin-setup.sh](shared/skills/setup/scripts/begin-setup.sh): without `--approve` it only prints the plan.

Required shape:

```text
[Setup Plan]
1. Prepare state/config directories
2. Check optional platform integrations
3. Detect project stack
4. Recommend/apply skills, CLI tools, and MCP servers
5. Generate or normalize manifest/context defaults

Optional items needing approval:
- ...

Reply with approval before execution.
```

Rules:
- Do not start with Bash commands in the first response.
- Do not create files or install tools before the user approves.
- If setup was triggered because `manifest.json` or `context.md` is missing, explicitly say that setup will begin in plan mode first.

### Intent-Based Team Selection

For requests that do not match Skill Direct Routes, pick a team using the Intent Contract below.

**Ambiguous-prompt resolution rules:**
- Any hint of code-change intent → prefer implementation
- Phrases that could mean either change or evaluate (e.g. Korean "봐줘" / "take a look") → prefer review (non-destructive)
- Compound intents (e.g. "analyze and fix") → planning, or decompose the request

(Korean example prompts below are preserved verbatim because the project's users
speak Korean — they document actual trigger phrases, not LLM instructions.)

#### none (direct handling)
- intent_description: Simple, well-scoped request. Single-file edit with concrete changes.
- when_to_use: "rename this function", "fix this type error", "add a console.log", "rename this variable"
- when_not_to_use: multi-file changes, exploration needed, uncertain requirements

#### analysis
- intent_description: Need to deeply understand codebase structure, patterns, dependencies, or architecture
- when_to_use: structural analysis, architecture comprehension, dependency exploration, "how does this work?", "show me the overall structure"
- when_not_to_use: code changes are required, simple questions
- example_prompts: "analyze the architecture of this module", "what does the dependency graph look like?", "find how this pattern is used across the codebase"

#### implementation
- intent_description: Actual code changes, additions, or fixes, including bug fixes. Multi-file scope or exploration required.
- when_to_use: feature implementation, bug fixes, refactoring, "fix this", "build this feature", "finish it completely"
- when_not_to_use: understanding without code changes, planning-only requests
- example_prompts: "fix this bug", "add a new API endpoint", "refactor this function", "finish it completely", "max performance"

#### review
- intent_description: Evaluating quality, correctness, or security of existing code or changes
- when_to_use: code review, PR review, security check, "take a look at this code", "please review"
- when_not_to_use: when direct code changes are needed (→ implementation)
- example_prompts: "review this PR", "any issues with this code?", "do a security check", "code review please"

#### planning
- intent_description: Need to plan and lock the design before implementation
- when_to_use: implementation planning, design discussion, approach decisions, "what's the best way to do this?", "plan this out"
- when_not_to_use: when the plan is already set and implementation should start (→ implementation)
- example_prompts: "what's the best way to implement this feature?", "plan the refactor", "nail down the approach"

#### research
- intent_description: Need to investigate external docs, APIs, or libraries
- when_to_use: external API research, library comparison, technical surveys, "look this up", "which library is better?", "migration guide"
- when_not_to_use: when internal code analysis alone suffices (→ analysis)
- example_prompts: "look up how this API is used", "research the migration guide", "summarize what's new in React 19"

#### dynamic
- intent_description: Default when the request does not fit any category cleanly or is compound
- when_to_use: ambiguous requests, compound intents, cases that require exploration before deciding
- when_not_to_use: when the intent is clear (route to one of the above)
- example_prompts: "can you help with this?" (ambiguous), "I have something to do about this file" (compound)

### Routing Behavior Rules

- Two or more teams equally suitable: ask the user "Which direction should I take?"
- Request contains two or more independent intents: route to the planning team or decompose the request
- No team matches: route to the dynamic team and write a warning log

## Orchestration Lifecycle

### Phase 1: INTAKE

Analyzes user requests to determine task type and mode.

### Phase 2: DECOMPOSE

For `medium` or larger tasks, identifies subtasks, dependencies, and parallelizable groups.

### Phase 3: COMPOSE TEAM

Assembles the team by referencing `team-templates/SKILL.md`.

1. Select template matching the task type
2. Adjust agent count based on task scale
3. Verify platform-specific auxiliary agent availability
4. Create task-folder
5. Initialize `team-manifest.json`

### Phase 4: DISPATCH

Spawns sub-agents by referencing `roles/SKILL.md`.

### Phase 5: MONITOR

Reads result files and updates team-manifest state.

### Phase 6: SYNTHESIZE

Integrates Scout/Builder/Inspector results to compose input for the next Wave.

### Phase 7: DECIDE

Determines next action based on PASS, FAIL, remaining iterations, or escalation conditions.

### Phase 8: OUTSIDE VOICE (Optional)

After Phase 7 decides to proceed to DELIVER, offer the user an Outside Voice option.
Outside Voice collects an independent opinion from an **AI model different from the current runtime**.

#### Activation Conditions (Smart Activation)

Outside Voice is NOT proposed for every completed task.
Auto-propose only when one or more of the following conditions hold:

**Auto-propose when (any of)**:
- Inspector/Review output contains `severity: warning` or higher items AND the overall verdict is PASS
- Task complexity is `high` or above (multi-module changes, architectural changes)
- The Architect plan contains items rated `risk: high`
- Implementation task changes 10 or more files
- The user explicitly requested Outside Voice

**Do NOT propose when**:
- The request was routed to `none` (direct handling)
- The user previously opted out in this session
- Simple exploration on the dynamic team
- The research team (unless explicitly requested)
- A clean PASS where every Inspector item is `suggestion` or lower
- Task complexity is `low`

**Skip reason**: When Outside Voice is disabled, show a brief reason.
Example: "[Outside Voice skipped: clean review results — no further check needed]"

#### 3-Platform Provider Selection

Detect the current platform to pick the Outside Voice target:

```
detect_platform():
  if .claude-plugin/ exists → platform = "claude"
  if .codex-plugin/ exists → platform = "codex"
  if .cursor-plugin/ exists → platform = "cursor"
```

| Platform | Outside Voice target | Fallback (degraded mode) | User choice needed |
|--------|-------------------|--------------------------|----------------|
| Claude Code | Codex (GPT-5.4) | Claude adversarial subagent (degraded) | No (auto) |
| Codex CLI | Claude (sonnet) | GPT adversarial subagent (degraded) | No (auto) |
| Cursor | User picks | adversarial subagent on chosen model (degraded) | Yes |

**Degraded mode notice**: When the cross-model provider is unavailable and the
same-runtime fallback is used, the user MUST be told via the `[Outside Voice - degraded]`
tag that this is a limited mode.

#### Prompt templates (render in user's locale)

**Claude Code / Codex CLI (auto target):**

```text
[Outside Voice] Team task complete.
Consult an independent external model ({target_model})?

1. Yes — run Outside Voice
2. No — deliver results as-is
3. Don't ask again this session
```

**Cursor (user picks):**

```text
[Outside Voice] Team task complete.
Consult an independent external model?

1. Ask Claude (Anthropic Claude sonnet)
2. Ask Codex (OpenAI GPT-5.4)
3. No — deliver results as-is
4. Don't ask again this session
```

#### Execution flow

1. **Detect platform** → determine provider
2. **Check provider availability**
   - Codex: `codex --version 2>/dev/null`
   - Claude: verify `Agent` tool is available
3. **Dispatch Challenger** → see the Challenger role in `roles/SKILL.md`
4. **Collect results** → `{task-folder}/results/outside-voice-{provider}.result.md`
5. **Produce Tension Report** → compare original team results with Outside Voice results

#### Tension Report

Identify tension points between the original team output and Outside Voice output and surface them to the user.
Save to `{task-folder}/results/tension-report.result.md`:

```markdown
# Tension Report: {task name}

## Agreement Points
- {point where team and outside voice agree}

## Disagreement Points
| # | Topic | Team Position | Outside Voice Position | Severity |
|---|-------|---------------|----------------------|----------|
| 1 | {topic} | {team position} | {outside voice position} | critical/moderate/minor |

## User Decision Required
Decide how to proceed for each tension point.
```

Ask the user to decide per disagreement point:
- A) Accept the Outside Voice recommendation
- B) Keep the original team's approach
- C) Investigate further before deciding

#### team-manifest.json state tracking

When Outside Voice runs, append the following to team-manifest.json:

```json
{
  "outsideVoice": {
    "offered": true,
    "accepted": true,
    "platform": "claude | codex | cursor",
    "provider": "codex | claude | claude-adversarial (degraded) | gpt-adversarial (degraded)",
    "degraded": false,
    "status": "complete | skipped | failed | not-applicable",
    "resultPath": "results/outside-voice-{provider}.result.md",
    "tensionReportPath": "results/tension-report.result.md",
    "verdict": "agree | partially-disagree | disagree",
    "tensionCount": 0,
    "adoptedCount": 0,
    "rejectedCount": 0,
    "reworkTriggered": false
  }
}
```

- `status: "not-applicable"`: used for tasks that are not Outside Voice candidates (e.g. `none` routing)
- `degraded`: true indicates the same-runtime adversarial fallback was used
- `tensionCount`: number of tension points identified
- `adoptedCount`: number of Outside Voice recommendations the user accepted
- `rejectedCount`: number of Outside Voice recommendations the user rejected
- `reworkTriggered`: whether Outside Voice caused rework

#### Telemetry integration

When Outside Voice completes, log the following event for the `stats` skill's usage tracking:

```json
{
  "event": "outside_voice",
  "timestamp": "ISO8601",
  "taskId": "{task-folder}",
  "template": "{template-name}",
  "provider": "{provider}",
  "degraded": false,
  "verdict": "{verdict}",
  "offered": true,
  "accepted": true,
  "tensionCount": 0,
  "adoptedCount": 0,
  "reworkTriggered": false
}
```

This data lets us track the following metrics:
- **Acceptance rate**: accepted / offered
- **Effectiveness**: adoptedCount / tensionCount (how often Outside Voice surfaced real issues)
- **Degraded ratio**: share of runs that fell back to degraded mode vs true cross-model
- **Rework rate**: frequency of `reworkTriggered`
```

#### Outside Voice Opt-Out

When the user says "turn off outside voice" / "no external opinions" or picks
"Don't ask again this session" in the prompt (the Korean phrases "outside voice 끄기",
"외부 의견 안 받을게" are example triggers):
- Skip Phase 8 for the rest of the current session
- Resume proposing in future sessions (this is NOT a permanent disable)

#### User Sovereignty Principle

Every Outside Voice result is a **recommendation**, not a decision.
Even when both models reach the same conclusion, present it to the user and let them decide.
Do NOT assert "Outside Voice is right"; instead say "Outside Voice recommends X — proceed?".

### Phase 9: DELIVER

Delivers task results, changed files, verification results, and final state to the user.

## Skill Tiers

Core:

- code-accuracy
- verify-loop
- planning
- git-commit

Extended:

- roles
- team-templates
- deep-search
- note
- auto
- PRD/ralph integration workflow

## Escalation Protocol

Halts the task and requests user judgment in the following situations:

- maxIterations reached
- Same error 3 consecutive times
- Destructive change requires approval
- Ambiguous requirements

## Messenger Bridge Integration

Messenger bridge is supported identically in team-based execution:

1. Check `messenger/config.json` + `bot.pid` right after Phase 3
2. Poll `messenger/commands/` at the start of each Wave
3. Write approval request file on escalation
4. Automatically send notification when `ralph-state.md` changes

## Progress Report Format

```text
[Synapse Team] {template} team -- Wave {N}
- Task: {task-folder}
- Team composition: {role list}
- Current Wave: {active agents}
- Completed Waves: {completed agents}
- Next action: {dispatch|synthesize|escalate|deliver}
```

## Rules

1. Maintain the order: situation assessment -> team composition -> dispatch -> result report
2. Load project-specific context if context.md exists
3. Guide to setup workflow in plan mode if context.md is missing
4. Always converse in Korean
5. Handle simple tasks directly without team composition
6. Sub-agent results are delivered via the filesystem
7. Always reference roles/team-templates when composing teams
8. `agentPlatforms` in manifest.json must always remain `["claude", "codex", "cursor"]` (do not overwrite with a single platform)
