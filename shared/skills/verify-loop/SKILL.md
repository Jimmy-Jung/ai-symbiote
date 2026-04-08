---
name: verify-loop
user-invocable: true
description: Guidelines for self-correcting behavior in autonomous execution loops. Defines 4-Level Completion Criteria, retry strategies, and loop exit conditions. This skill should be used when running autonomous execution loops that need structured verify-fix cycles.
---

# Verify Loop

Guidelines for self-correcting behavior in autonomous execution loops.

## Self-Correction Loop Flow

```
Execute (implement)
    |
Verify (validate)
    |
[Issue found?] --Yes--> Analyze (root cause) --> Fix (patch) --> Execute (retry)
    |
    No
    |
Complete (done)
```

Each iteration reflects previous failure causes; never use the same approach twice.

## 4-Level Completion Criteria

### Level 1 (Minimal)
- Code changes complete
- Lint passes (run lint command via bash)
- Basic syntax/type checks pass
- No runtime errors
- Applies to: simple fixes, short tasks

### Level 2 (Standard)
- Level 1 satisfied
- Functional verification complete (behavior confirmed)
- Code review standards met
- Logical correctness confirmed
- Applies to: general tasks, bug fixes

### Level 3 (Thorough)
- Level 2 satisfied
- All tests pass
- Edge cases handled
- Documentation updated
- QA verification standards met
- Applies to: feature implementation, refactoring

### Level 4 (Production)
- Level 3 satisfied
- Security review
- Performance verification
- Integration tests
- Applies to: releases, pre-deployment

## Retry Strategy

### Root Cause Analysis Required
Do not fix immediately on verification failure; always analyze the cause first:
- What failed (symptom)
- Why it failed (root cause)
- What went wrong in the previous attempt
- What to do differently in the next attempt

### No Repeated Approaches
- Do not retry using the same method
- If the same error occurs twice, try a fundamentally different approach
- Example of approach change: direct implementation failed -> reference existing similar code

### Max Retries by Error Type
- Compile errors: up to 2 attempts with similar pattern
- Same error 3 times in a row: switch approach
- Total 5 retries: escalate to user

## Loop Exit Conditions

### Normal Termination
- All criteria for the selected Level are met

### Forced Termination (Escalation)
- Same error 3 times in a row -> switch approach
- Total 5 retries -> escalate to user
- Destructive changes needed: request user confirmation
- Ambiguous requirements: request user confirmation

### Forced Termination Report Format

```
[Verify Loop Forced Termination]

- Iteration count: N/M
- Exit reason: [reason]
- Final status: [achieved / not achieved]
- Issues found: [list]
- Recommended action: [suggestion to user]
```

## Failure Pattern Classification and Response

| Pattern | Possible Cause | Response |
|---------|---------------|----------|
| Compile error | Missing import, syntax | Fix import/syntax |
| Type error | Type mismatch | Check actual type definition, then fix |
| Logic error | Misunderstood requirements | Re-analyze requirements |
| Test failure | Expected value mismatch | Verify test expectations |
| Symbol not found | Hallucinated code | Search for actual symbol via Grep, then replace |

## Performance Principles

- Minimal changes: only make the smallest necessary changes during fix cycles
- No over-engineering: avoid over-design during fixes
- Fail Fast: skip unnecessary subsequent steps on early failure
- Verification scope: expand to higher Levels after Level 1 passes

## Role Injection: Inspector

This section is injected into the prompt when the synapse orchestrator spawns an Inspector subagent.

The Inspector follows the 4-Level Completion Criteria, Self-Correction Loop Flow, and Failure Pattern Classification above.
Verify against the completion criteria Level specified by the orchestrator.
The overall verdict must be explicitly stated as PASS or FAIL.
On FAIL, provide specific fix suggestions (file, line number, fix method).
Write results in markdown to the designated result file.
