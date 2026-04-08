---
name: roles
description: Subagent role definitions. Defines input/output contracts and prompt templates for 5 roles: Scout, Architect, Builder, Inspector, Researcher. Referenced by the synapse orchestrator when composing teams.
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
- Injected skill: Role Injection: Architect section of `planning/SKILL.md`

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

## Orchestrator Notes

### Model Cost Optimization
- Opus (Architect): Use only for planning that requires complex reasoning
- Sonnet (Scout, Builder, Inspector): Use for most execution tasks
- Haiku (Researcher): Use for simple lookup/search tasks
- GPT-5.4 (Codex): Use for second opinions, adversarial reviews, root cause analysis

### Parallel Execution Rules
- Agents of the same role can run in parallel (Scout x3, Builder x3)
- Different roles can run in parallel if no dependencies exist
- Dependent roles run sequentially (Scout -> Architect -> Builder -> Inspector)
- Codex can run in parallel with Inspector (independent review from a different model)
- Codex can run in parallel with Builder (simultaneous implementation with different approaches)

### Team Size Guidelines
- Optimal: 2-5 agents (based on Anthropic research)
- Not all agents need to be active simultaneously (deploy by phase)
- Beyond 5, coordination overhead outweighs parallelism benefits
- Codex runs on a separate runtime, so it can be excluded from team size count

### Codex Availability Check
Always verify before deploying the Codex role:
```bash
codex --version 2>/dev/null && echo "available" || echo "unavailable"
```
If unavailable, skip the Codex role and compose the team with default agents only.
All workflows must function normally without Codex (Codex is an optional enhancement).
