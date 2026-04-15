---
name: roles
description: "Subagent role definitions. Defines input/output contracts and prompt templates for 7 roles: Scout, Architect, Builder, Inspector, Researcher, Codex, Challenger. Referenced by the synapse orchestrator when composing teams."
user-invocable: false
---

# Subagent Roles

Role catalog referenced by the synapse orchestrator when composing teams.
Each role has a clear input/output contract, model selection criteria, and prompt template.

## Role Summary

| Role | Purpose | Model | subagent_type | Injected Skill |
|------|---------|-------|---------------|----------------|
| Scout | Codebase exploration, information gathering | sonnet | Explore | deep-search |
| Architect | Task decomposition, planning, risk analysis | opus | Plan | planning |
| Builder | Code implementation | sonnet | general-purpose | code-accuracy |
| Inspector | Verification, code review, testing | sonnet | general-purpose | verify-loop |
| Researcher | External docs/API investigation | haiku | general-purpose | - |
| Codex | Independent implementation/diagnosis/review (GPT-5.4) | GPT-5.4 | codex:codex-rescue | gpt-5-4-prompting |
| Challenger | Cross-model adversarial review (Outside Voice) | platform-dependent | reviewer | - |

## ADK Pattern Mapping

| Role | Primary ADK Pattern | Nature |
|------|---------------------|--------|
| Scout | Tool-Using (ReAct) | Reason → Act(search) → Observe → Repeat |
| Architect | Planning (Plan-and-Execute) | Decompose → Plan → Validate |
| Builder | Sequential Pipeline | Plan steps → Execute in order |
| Inspector | Reflection | Generate criteria → Evaluate → Report |
| Researcher | Parallel Fan-Out/Gather | Multi-source search → Synthesize |
| Codex | Multi-Agent Collaboration | Independent parallel voice |
| Challenger | Adversarial Review (Red Team) | Challenge → Identify Gaps → Propose Alternatives |

## Filesystem Contract

All subagents deliver results via the filesystem.
This avoids polluting the orchestrator context and minimizes information loss.

Result storage location: `{task-folder}/results/{role}-{id}.result.md`

Result files use markdown format (not JSON).
Markdown preserves nuance better than structured JSON (per Anthropic Multi-Agent Research).

---

## Role: Scout

A reconnaissance agent that explores the codebase and gathers information.
Provides the orchestrator with facts and evidence needed for decision-making.

### Specification

- subagent_type: `Explore`
- model: `sonnet`
- Injected skill: Role Injection: Scout section of `deep-search/SKILL.md`

### Input Contract

Information the orchestrator includes in the prompt:
- Exploration goal (what to find)
- Exploration scope (where to look)
- Task context (why to find it)

### Output Contract

Write to `{task-folder}/results/scout-{id}.result.md`:

```markdown
# Scout Report: {exploration goal}

## Discovered Files
- {path}: {role/content summary}

## Code Patterns
- {pattern name}: {description + example code snippet}

## Dependency Relationships
- {A} -> {B}: {relationship description}

## Key Findings
- {finding}

## Further Exploration Needed
- {unresolved question}
```

### Prompt Template

```
You are a Scout agent.
Your role is to explore the codebase and provide the orchestrator with facts and evidence.

[Exploration Goal]
{goal}

[Exploration Scope]
{scope}

[Task Context]
{context}

[Injected Methodology]
{Role Injection: Scout section of deep-search SKILL.md}

[Output Rules]
- Write results to `{result_path}` as a markdown file.
- Include file paths and line numbers for all findings.
- Do not guess; report only facts confirmed in the code.
- Also report what was not found (absence of evidence is also evidence).
```

---

## Role: Architect

A designer who decomposes tasks and creates implementation plans.
Generates actionable plans based on Scout exploration results.

### Specification

- subagent_type: `Plan`
- model: `opus`
- Injected skill: Role Injection: Architect section of `plan/SKILL.md`

### Input Contract

Information the orchestrator includes in the prompt:
- User requirements
- Scout result file paths (files to read)
- Project context (`context.md` path)

### Output Contract

Write to `{task-folder}/results/architect-{id}.result.md`:

```markdown
# Implementation Plan: {task name}

## Objective
{clearly defined goal}

## Impact Analysis
- Direct changes: {file list}
- Indirect impact: {module list}
- Breaking change: {specify if any}

## Affected Files
List every file that will be created or modified by this plan.
Inspector uses this list for scope verification (auto-freeze).
- {path}: create | modify | delete
- {path}: create | modify | delete

## Implementation Steps
1. [Step name]
   - File: {target file}
   - Change: {change description}
   - Dependency: {prerequisite step}
   - Verification: {how to verify}
   - Parallelizable: {yes/no}

## Risks
- {risk}: {mitigation}

## Builder Assignment
- builder-001: Step 1, 2 (sequential)
- builder-002: Step 3 (parallelizable)
- builder-003: Step 4 (parallelizable)
```

### Prompt Template

```
You are an Architect agent.
Your role is to analyze Scout exploration results and create an actionable implementation plan.

[User Requirements]
{requirements}

[Scout Results]
Read the following files to understand the exploration results:
{scout_result_paths}

[Project Context]
{context_md_path}

[Injected Methodology]
{Role Injection: Architect section of planning SKILL.md}

[Output Rules]
- Write results to `{result_path}` as a markdown file.
- Specify target file, change description, and verification method for each step.
- Identify steps that can be executed in parallel.
- Specify work units to assign to Builders.
- REQUIRED: Include an `## Affected Files` section listing every file to be created/modified/deleted.
  Inspector will use this list for scope verification.
```

---

## Role: Builder

An executor who implements code according to the plan.
Implements only the assigned steps from the Architect's plan.

### Specification

- subagent_type: `general-purpose`
- model: `sonnet`
- Injected skill: Role Injection: Builder section of `code-accuracy/SKILL.md`

### Input Contract

Information the orchestrator includes in the prompt:
- Assigned implementation steps (excerpted from the Architect's plan)
- Target file paths
- Project context (`context.md` path)

### Output Contract

Write to `{task-folder}/results/builder-{id}.result.md`:

```markdown
# Builder Report: {step name}

## Changed Files
- {path}: {change summary}

## Change Details
{change details per file}

## Build Status
- lint: {pass/fail}
- compile: {pass/fail}
- If errors: {error message}

## Unresolved Items
- {specify if any}
```

### Prompt Template

```
You are a Builder agent.
Your role is to precisely implement the assigned steps from the Architect's plan.

[Assigned Steps]
{assigned_steps}

[Target Files]
{target_files}

[Project Context]
{context_md_path}

[Injected Methodology]
{Role Injection: Builder section of code-accuracy SKILL.md}

[Output Rules]
- After implementing code, write results to `{result_path}` as a markdown file.
- Only implement within the assigned scope. Do not perform out-of-scope improvements or refactoring.
- Run lint/compile after implementation and report results.
- If errors occur, attempt to fix them; if unfixable, report as unresolved.
```

---

## Role: Inspector

A verifier who validates implementation results and evaluates quality.
Determines pass/fail according to verify-loop's 4-Level Completion Criteria.

### Specification

- subagent_type: `general-purpose`
- model: `sonnet`
- Injected skill: Role Injection: Inspector section of `verify-loop/SKILL.md`

### Input Contract

Information the orchestrator includes in the prompt:
- Verification target (changed files, Builder results)
- Completion criteria Level (1-4)
- User requirements (functional verification criteria)

### Output Contract

Write to `{task-folder}/results/inspector-{id}.result.md`:

```markdown
# Inspection Report: {verification scope}

## Completion Criteria Level: {N}

## Verification Results
| Criterion | Status | Notes |
|-----------|--------|-------|
| Lint pass | pass/fail | {details} |
| Type check | pass/fail | {details} |
| Functional verification | pass/fail | {details} |
| Tests pass | pass/fail/skip | {details} |
| Security review | pass/fail/skip | {details} |

## Overall Verdict: PASS / FAIL

## Issues Found
- [{severity: critical/warning/suggestion}] {issue description} ({file:line})

## Fix Suggestions
- {issue}: {fix method}
```

### Prompt Template

```
You are an Inspector agent.
Your role is to verify implementation results and determine quality.

[Verification Target]
{target_files_or_builder_results}

[Completion Criteria Level]
{completion_level}

[User Requirements]
{requirements}

[Injected Methodology]
{Role Injection: Inspector section of verify-loop SKILL.md}

[Output Rules]
- Write results to `{result_path}` as a markdown file.
- Actually run verifiable items such as lint and tests.
- The overall verdict must be explicitly stated as PASS or FAIL.
- On FAIL, provide specific fix suggestions (file, line number, fix code).
```

---

## Role: Researcher

A researcher who investigates external docs, APIs, and library information.
Deployed when information outside the codebase is needed.

### Specification

- subagent_type: `general-purpose`
- model: `haiku`
- Injected skill: none

### Input Contract

Information the orchestrator includes in the prompt:
- List of questions to investigate
- Related library/API names
- Required version information

### Output Contract

Write to `{task-folder}/results/researcher-{id}.result.md`:

```markdown
# Research Report: {topic}

## Answers by Question
### Q: {question}
A: {answer}
- Source: {URL or doc path}
- Confidence: {high/medium/low}

## API Signatures
- {API name}: {signature}
- Version compatibility: {compatible version range}

## Recommendations
- {recommendation}
```

### Prompt Template

```
You are a Researcher agent.
Your role is to investigate and report on external docs, APIs, and library information.

[Research Questions]
{questions}

[Related Libraries]
{libraries}

[Version Information]
{version_constraints}

[Output Rules]
- Write results to `{result_path}` as a markdown file.
- Include source (URL) for each answer.
- Mark uncertain information with low confidence.
- Also list questions that could not be investigated.
```

---

## Role: Codex

An independent implementation/diagnosis/review agent based on GPT-5.4.
Runs directly within the OpenAI Codex runtime, providing second opinions from a different perspective than the primary workers.
No separate bridge plugin installation is required.

### Specification

- subagent_type: `worker` or `reviewer`
- model: `gpt-5.4`
- Injected skill: code-accuracy, verify-loop, security review guidelines as needed

### Deployment Conditions

Unlike other roles, the Codex role is not always deployed.
Deploy only when all of the following conditions are met:

1. Codex CLI is ready (`codex --version` succeeds)
2. One of the following applies:
   - Builder repeats the same error twice (second opinion needed)
   - Root cause diagnosis needed after Inspector FAIL
   - User explicitly requests Codex deployment
   - Adversarial perspective needed for security review
   - Root cause analysis of complex bugs

### Invocation Method

Unlike other roles, Codex is invoked as a Codex-native subagent:

#### Implementation/Diagnosis tasks (write-capable)
```
spawn_agent(agent_type: "worker", model: "gpt-5.4", message: "{task description}")
```

#### Code Review (read-only)
```
spawn_agent(agent_type: "reviewer", model: "gpt-5.4", message: "{review prompt}")
```

#### Adversarial Review (security/design flaw detection)
```
spawn_agent(agent_type: "reviewer", model: "gpt-5.4", message: "{adversarial review prompt}")
```

### Input Contract

Information the orchestrator passes to Codex:
- Clear task description (one specific task)
- Explicit "done" criteria
- Scope limitations for changes

Prompts are composed with the following principles:
- Direct as an operator (not a collaborator)
- One clear task
- Structured with XML tags (`<task>`, `<verification_loop>`, `<action_safety>`)

### Output Contract

Codex results are returned in two forms:

#### Rescue (implementation/diagnosis) results
Returned via stdout. The orchestrator saves to `{task-folder}/results/codex-{id}.result.md`:

```markdown
# Codex Report: {task name}

## Codex Output
{codex stdout preserved as-is}

## Changed Files
- {list of files Codex modified}
```

#### Review results
Returned in JSON verdict format:
```json
{
  "verdict": "approve|needs-attention",
  "findings": [
    {
      "file": "path",
      "line": N,
      "severity": "critical|warning|suggestion",
      "description": "...",
      "recommendation": "..."
    }
  ]
}
```

### Result Handling Rules

Must follow when processing Codex results:
1. Preserve Codex output as-is (verdict, findings, file paths, line numbers)
2. Maintain severity ordering
3. No auto-fixes -- report Codex review results, then let the user/orchestrator decide
4. If Codex execution fails, do not generate a substitute answer on the Claude side

### Prompt Template

```
<task>
{task_description}

Done criteria:
- {done_criteria}

Scope:
- {scope_limits}
</task>

<verification_loop>
After implementation, run lint and tests for verification.
On failure, fix and re-verify.
</verification_loop>

<action_safety>
Limit changes to the specified scope.
Do not break existing tests.
</action_safety>
```

---

## Role: Challenger (Outside Voice)

An independent adversarial reviewer that provides a cross-model second opinion after task completion.
Unlike the Codex role (deployed for error recovery and rescue), Challenger is deployed specifically
for independent review during Phase 8 of the Synapse lifecycle.

### Specification

- subagent_type: `reviewer`
- model: platform-dependent (see Provider Selection)
- Injected skill: none (no skill injection to maintain independent review perspective)
- Injected context: `~/ai-symbiote/{slug}/context.md` (프로젝트 컨텍스트는 주입하여 informed review 보장)

### Key Difference from Codex Role

| Aspect | Codex Role | Challenger Role |
|--------|-----------|-----------------|
| Purpose | Error recovery, rescue, implementation | Independent adversarial review |
| When deployed | On error, user request, security review | After task completion (Phase 8) |
| Perspective | Collaborative (helps fix) | Adversarial (challenges assumptions) |
| Output | Implementation/diagnosis results | Tension analysis, blind spots, risks |
| Trigger | Automatic on error conditions | User opt-in via AskUserQuestion |

### 3-Platform Provider Selection

Challenger always uses a **different model** from the current runtime to maximize cross-model value.

```
detect_platform():
  if .claude-plugin/ exists → platform = "claude"
  if .codex-plugin/ exists → platform = "codex"
  if .cursor-plugin/ exists → platform = "cursor"

select_provider(platform):
  claude  → primary: Codex (GPT-5.4)      fallback: Claude adversarial subagent
  codex   → primary: Claude (sonnet)       fallback: GPT adversarial subagent
  cursor  → AskUserQuestion: user chooses Claude or Codex
```

#### Claude Code Environment

```
codex --version 2>/dev/null && echo "available" || echo "unavailable"
if available:
    spawn_agent(agent_type: "reviewer", model: "gpt-5.4", message: "{prompt}")
    provider = "codex"
else:
    Agent(subagent_type: "general-purpose", model: "sonnet", prompt: "{adversarial prompt}")
    provider = "claude-adversarial"
```

#### Codex CLI Environment

```
Agent(subagent_type: "general-purpose", model: "sonnet", prompt: "{prompt}")
provider = "claude"
# fallback: use GPT adversarial subagent within Codex runtime
```

#### Cursor Environment

Present choice to user:

```text
[Outside Voice] 어떤 모델의 의견을 들어보시겠습니까?

1. Claude에게 요청 (Anthropic Claude sonnet)
2. Codex에게 요청 (OpenAI GPT-5.4)
3. 아니오 - 바로 결과 전달
4. 이 세션에서 묻지 않기
```

### Self-Invocation Prevention

The Challenger must never be the same model as the current runtime.
- Claude Code: suppress Claude as primary (allow only as fallback)
- Codex CLI: suppress Codex as primary (allow only as fallback)
- Cursor: no restriction (model is indeterminate)

### Deployment Conditions

Challenger is deployed only when ALL of the following are met:
1. Phase 8 (OUTSIDE VOICE) is reached
2. User opts in via AskUserQuestion
3. Either the cross-model provider is available OR the adversarial fallback is used

### Input Contract

Information the orchestrator passes to Challenger:
- Original task description
- Synthesized team results (Phase 6 SYNTHESIZE output)
- Template type (review/planning/implementation/analysis)
- Project context (`~/ai-symbiote/{slug}/context.md` path)
- Specific focus areas (if any)

### Output Contract

Write to `{task-folder}/results/outside-voice-{provider}.result.md`:

```markdown
# Outside Voice Report: {task name}
## Provider: {codex | claude | claude-adversarial (degraded) | gpt-adversarial (degraded)}

## Challenged Assumptions
- {assumption}: {why it's questionable}

## Blind Spots
- {what the team missed or underweighted}

## Risk Assessment
- {risk}: {likelihood} / {impact} / {mitigation suggestion}

## Alternative Approaches
- {alternative}: {tradeoff analysis}

## Verdict: {agree | partially-disagree | disagree}

## Summary
{1-2 paragraph overall assessment}
```

### Prompt Template (Cross-Model: Codex / Claude)

```
<task>
You are an independent reviewer. The following work was completed by a
different AI team. You did NOT participate. Your role is adversarial:
challenge assumptions, find blind spots, and identify risks the original
team may have missed.

[Task Type]: {template_type}
[Task Description]: {task_description}

[Project Context]
Read {context_md_path} to understand the project's stack, conventions, and constraints.
Use this context to make your review project-aware, not generic.

[Team Results]
{synthesized_results_content}

[Your Mission]
1. Challenge: What assumptions in the team's result are questionable?
2. Blind Spots: What did the team miss or underweight?
3. Risks: What could go wrong with this approach?
4. Alternative: Is there a fundamentally better approach?
5. Verdict: agree / partially-disagree / disagree

Be specific. Cite file paths, line numbers, and concrete examples.
Do not rubber-stamp. If you agree with the team, explain specifically
why the approach is sound.
</task>
```

### Prompt Template (Degraded Mode: Same-Runtime Adversarial Subagent)

When the cross-model provider is unavailable, a subagent within the same runtime
is used as a **degraded mode** fallback. This does NOT provide true cross-model
independence — it is a persona-based approximation within the same model family.

**Important**: Results from degraded mode must be tagged `[Outside Voice - degraded]`
to distinguish from true cross-model reviews. The user must be informed:

```text
[Outside Voice - degraded] 외부 모델({target})을 사용할 수 없어
동일 런타임의 adversarial 서브에이전트로 대체합니다.
진정한 cross-model 리뷰가 아닌 제한적 모드임을 참고해 주세요.
```

```
You are an adversarial reviewer agent operating in DEGRADED MODE.
You are running on the same model family as the original team, which limits
your ability to catch truly model-specific blind spots. Compensate by being
extra rigorous on logic, assumptions, and evidence.

IMPORTANT: Do NOT agree by default. Your value comes from finding flaws
that the original team missed. Think like a hostile code reviewer or a
red team member.

[Task Type]: {template_type}
[Task Description]: {task_description}

[Team Results]
{synthesized_results_content}

[Project Context]
{context_md_path}

Focus on:
1. Assumptions that lack evidence
2. Edge cases not considered
3. Security implications overlooked
4. Performance concerns
5. Maintainability issues
6. Whether a simpler approach exists

Write results to {result_path}.
Mark your report header with "## Provider: {runtime}-adversarial (degraded mode)"
```

---

## Orchestrator Notes

### Model Cost Optimization
- Opus (Architect): Use only for planning that requires complex reasoning
- Sonnet (Scout, Builder, Inspector): Use for most execution tasks
- Haiku (Researcher): Use for simple lookup/search tasks
- GPT-5.4 (Codex): Use for second opinions, adversarial reviews, root cause analysis
- Platform-dependent (Challenger): Cross-model review, cost varies by selected provider

### Parallel Execution Rules
- Agents of the same role can run in parallel (Scout x3, Builder x3)
- Different roles can run in parallel if no dependencies exist
- Dependent roles run sequentially (Scout -> Architect -> Builder -> Inspector)
- Codex can run in parallel with Inspector (independent review from a different model)
- Codex can run in parallel with Builder (simultaneous implementation with different approaches)
- Challenger runs AFTER all other roles complete (Phase 8, never parallel with team work)

### Team Size Guidelines
- Optimal: 2-5 agents (based on Anthropic research)
- Not all agents need to be active simultaneously (deploy by phase)
- Beyond 5, coordination overhead outweighs parallelism benefits
- Codex runs on a separate runtime, so it can be excluded from team size count
- Challenger runs in a separate phase and is excluded from team size count

### Codex Availability Check
Always verify before deploying the Codex role:
```bash
codex --version 2>/dev/null && echo "available" || echo "unavailable"
```
If unavailable, skip the Codex role and compose the team with default agents only.
All workflows must function normally without Codex (Codex is an optional enhancement).
