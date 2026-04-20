---
name: verify
description: "Write-time Verification Layer. Processes queued edits via cold-read reviewer + LLM judge to expose opaque decisions. Triggers on: verify, run verify, process verification, check reasoning, verify queue."
argument-hint: [--all | --sha <sha> | --file <path> | --dry-run]
user-invocable: true
allowed-tools: [Read, Write, Edit, Glob, Grep, Bash, Skill]
---

# Verify -- Write-time Verification Layer

AI가 작성한 코드의 opacity를 행동적으로 측정하고 제거하는 스킬. PostToolUse 훅이 edit 이벤트를 `~/.ai-symbiote/state/verify-queue.jsonl`에 큐잉하면, `/verify`가 이를 꺼내어 cold-read reviewer + LLM judge 파이프라인으로 검증한다.

자세한 설계 배경은 `docs/ARCHITECTURE.md`와 office-hours 디자인 문서(Stage 0/1) 참조.

## Entry Conditions

- `~/.ai-symbiote/state/verify-queue.jsonl`에 현재 프로젝트/브랜치의 pending entry가 1개 이상 존재
- OR `--sha`/`--file`로 명시적 target 지정
- `codex` CLI가 PATH에 존재하고 `codex login` 완료 상태
- 현재 디렉토리가 git 저장소

`codex`가 없으면 Claude 하위 에이전트로 fallback (degraded mode).

## Workflow

### Step 1: Queue 읽기 및 필터링

```bash
QUEUE_FILE="$HOME/.ai-symbiote/state/verify-queue.jsonl"
PROJECT=$(basename "$(git rev-parse --show-toplevel)")
BRANCH=$(git branch --show-current)
```

현재 project + branch로 필터링한 pending entries를 수집한다. `--sha`/`--file` 인자가 있으면 해당 항목만.

pending이 0개면:
```
No pending verifications for {project}/{branch}. Queue empty.
```
로 종료.

### Step 2: 사용자 확인

```
[Verify] {N} pending verifications for {project}/{branch}:
- SHA abc123 / file: src/foo.ts
- SHA def456 / file: src/bar.ts
...

Estimated: ~60s × {N} = ~{total}s, ~${cost} USD.
Proceed? [Y/n]
```

`Y` → Step 3 진행.
`n` → 종료 (queue 그대로 유지).
`--dry-run` → 큐 내용만 표시하고 종료.

### Step 3: Reviewer 호출 (per entry)

각 entry에 대해:

1. **Diff 수집**
   - `sha`가 uncommitted가 아니면: `git show <sha> -- <file>`
   - `uncommitted`면: `git diff HEAD -- <file>` (unstaged) 또는 `git diff --cached -- <file>` (staged)

2. **Reviewer prompt 조립** (아래 "Reviewer Prompt Template" 참조)
3. **Codex 호출**:
   ```bash
   source ~/.claude/skills/gstack/bin/gstack-codex-probe 2>/dev/null || true
   codex exec "$PROMPT" -C "$(git rev-parse --show-toplevel)" \
     -s read-only -c 'model_reasoning_effort="medium"' --json < /dev/null
   ```
   JSON 스트림에서 `item.completed` / `agent_message`만 파싱해 질문 수집.

4. 출력된 질문들을 저장 후 다음 단계로.

### Step 4: Author 답변 생성

현재 Claude 세션(이 스킬이 실행되는 컨텍스트 = 저자 모델)에 질문을 주고 답변 요청.

**답변 규칙** (반드시 명시):
- 특정 코드 라인/식별자 참조 필수
- 고려했던 대안 하나 이상 명시
- "모르겠음", "AI가 그냥 생성함"도 유효 (단, rewrite 트리거)

### Step 5: V1 Validator (Basic)

각 답변에 대해:
- V1a 길이 ≥ 50자
- V1b 코드 참조 패턴 (`[\w/.-]+:\d+` 또는 backtick identifier)
- V1c "모르겠음|don't know|그냥" 키워드 부재
- V1d 최소 1개 대안 언급 ("대신|instead|could have|rejected|considered")

V1 fail → 즉시 rewrite loop (answer만 재생성).

### Step 6: V2 Validator — LLM Judge Verifiability Check ⭐

**필수 메커니즘**. Codex 판정으로 gaming 탐지.

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

Judge 호출 시 전달: `(CODE, PR_BODY or commit_message, QUESTIONS, ANSWERS)`

Judge 모델: 기본 Codex (저자와 다른 벤더). 저자가 Codex일 경우에만 Claude subagent fallback.

Judge가 `GAMING_DETECTED` → 전체 rewrite loop.
Judge가 `GENUINE` + V1 전부 pass → verification pass.

### Step 7: Artifact 저장

경로: `.ai-symbiote/qa/<project>/<YYYY-MM-DD>/<sha-or-timestamp>.md`

포맷:
```markdown
# Verification — <sha> (<branch>)

Generated: <ts>
File(s): <list>
Reviewer: codex / <model>
Judge: codex / <model>
Result: PASS | FAIL

## Questions
Q1: ...
Q2: ...

## Answers
A1: ...
A2: ...

## Validator Report
- V1a~d: PASS/FAIL per rule
- V2b judge verdict:
  - A1: PASS — ...
  - A2: FAIL — ...
  - OVERALL: GENUINE | GAMING_DETECTED

## Rewrite Notes (if applicable)
<feedback to author>
```

### Step 8: Queue entry 제거

성공 처리된 entry를 queue에서 삭제. Fail로 끝난 entry는 queue에 남겨 다음 `/verify`에서 재시도.

### Step 9: 결과 요약

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
- **V2b** LLM judge verifiability check → `GAMING_DETECTED` = fail
- **V2c** (optional) reviewer generates N=5 questions, author answers randomly selected K=3

Stage 0 실측(2026-04-20): V1만으로는 3/3 gaming case 전부 통과. V2b judge가 실 차단선. 반드시 필수로 실행.

## Platform Support

- **Claude**: hook queue + `/verify` skill 둘 다 지원
- **Codex**: `/verify` skill만 수동 호출 (Write|Edit post-hook 부재로 queue 자동 append 불가). `/verify --sha <sha>` 또는 `--file <path>`로 수동 지정 사용.

## Fallback Mode

`codex` CLI 없거나 `codex login` 안 된 경우:
1. Reviewer는 Claude subagent (Agent tool)로 fallback — diversity 손실 경고
2. Judge는 별도 Claude subagent — collusion risk 경고
3. 최종 결과에 `DEGRADED_MODE` 표시

사용자에게 `codex login` 권장 메시지 출력.

## Arguments

- `--all` (default): 현재 project/branch의 모든 pending entry 처리
- `--sha <sha>` : 특정 sha만 처리
- `--file <path>` : 특정 파일과 관련된 entry만
- `--dry-run` : queue 내용만 표시하고 실제 호출 없이 종료

## Related Skills

- `gc` — 오래된 queue entry / qa artifact 정리 (향후 gc 확장)
- `ship` / `pr` — PR 생성 시 qa/ artifact를 본문에 첨부하는 통합 (향후)
- `investigate` — FAIL 원인 디버깅 시 참조

## Important Rules

- **Never skip V2b judge check**. V1만으로는 gaming 완전 탐지 불가 (Stage 0 실측).
- **Judge 모델은 저자와 반드시 다름**. config override 금지.
- **모든 artifact는 `.ai-symbiote/qa/` 저장**. PR 본문에 링크 가능한 영구 경로.
- **Queue entry 삭제는 PASS 후에만**. FAIL은 queue 유지 → 다음 /verify에서 재시도.
- **사용자 요청 시에만 실행**. 자동 강제 실행 없음 (edit flow 방해 금지).
