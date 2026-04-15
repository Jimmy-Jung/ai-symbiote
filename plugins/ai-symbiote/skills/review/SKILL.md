---
name: review
description: Runs a code review on current changes.
argument-hint: [file or directory]
user-invocable: true
allowed-tools: [Read, Glob, Grep, Bash, Agent]
---

# Review

Assembles the synapse orchestrator's review team to perform a code review.

## Team Composition

- Team template: `review`

### Phase-by-Phase Team Deployment

| Order | Role | Count | Purpose |
|-------|------|-------|---------|
| Wave 1 | Scout | 1 | Collect related code, dependencies, and tests for changed files |
| Wave 2 | Inspector | 2~3 (parallel) | Review from different perspectives |

### Inspector Allocation Strategy
- Inspector-001: Code quality (readability, complexity, duplication)
- Inspector-002: Pattern compliance (architecture, naming, conventions)
- Inspector-003: Potential bugs + performance (null references, boundary conditions, N+1)
- Inspector-004: Security review (when manifest.json enableSecurityReview = true)

## Change Collection

- Check changes with `git diff --staged` and `git diff`
- If a file/directory is specified as argument, review only that scope

## Result Report

Synapse aggregates all Inspector results into a unified review report:
- Sorted by severity: Critical > Warning > Suggestion
- Each item includes file path and line number
- Includes fix suggestions

## Outside Voice Option

모든 Inspector 리뷰 완료 및 통합 리포트 생성 후, Synapse Phase 8에 따라 Outside Voice를 제안한다.

### 제안 조건

Synapse Phase 8 Smart Activation 조건에 따라 제안한다.
리뷰 결과에 `severity: warning` 이상 항목이 존재하면서 PASS 판정된 경우에만 자동 제안.
모든 항목이 `suggestion` 이하이면 Outside Voice를 건너뛰고 사유를 안내한다.

### 제안 메시지

```text
[Review Complete] 리뷰가 완료되었습니다.
- Critical: {N}건 / Warning: {M}건 / Suggestion: {K}건

Warning 이상 항목이 {M+N}건 감지되었습니다.
독립적인 외부 모델의 교차 검증을 받아보시겠습니까?
```

### Review 특화 Outside Voice 프롬프트

Outside Voice 실행 시, Challenger에게 다음을 전달:
- Inspector들의 리뷰 결과 전체
- "Inspector들이 PASS로 판단한 영역"에 대한 재검증 요청
- 보안, 성능, 아키텍처 관점의 교차 검증

### 결과 통합

Outside Voice 결과는 기존 리뷰 리포트에 별도 섹션으로 추가:

```markdown
## Outside Voice Review ({provider})
- Verdict: {agree/partially-disagree/disagree}
- Additional findings:
  - [{severity}] {finding} ({file:line})
- Challenged items from original review:
  - {item}: {challenge rationale}
```
