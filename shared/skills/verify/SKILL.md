---
name: verify
description: "Write-time Verification Layer. Processes queued edits via cold-read reviewer + LLM judge to expose opaque decisions. Triggers on: verify, run verify, process verification, check reasoning, verify queue."
argument-hint: [--all | --sha <sha> | --file <path> | --dry-run]
user-invocable: true
allowed-tools: [Read, Write, Edit, Glob, Grep, Bash, Skill, Agent]
---

# Verify -- Write-time Verification Layer

AI가 작성한 코드의 opacity를 행동적으로 측정하고 제거하는 스킬. PostToolUse 훅이 edit 이벤트를 `~/.ai-symbiote/state/verify-queue.jsonl`에 큐잉하면, `/verify`가 이를 꺼내어 cold-read reviewer + LLM judge 파이프라인으로 검증한다.

자세한 설계 배경은 `docs/02-아키텍처.md`("Write-time Verification Layer" 섹션)와 office-hours 디자인 문서(Stage 0/1) 참조.

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
REPO_ROOT=$(git rev-parse --show-toplevel)
PROJECT=$(basename "$REPO_ROOT")
BRANCH=$(git branch --show-current)
```

필터링 기준 (우선순위 순):
1. **Schema v2 (권장)**: `repo_root == $REPO_ROOT AND branch == $BRANCH`
2. **Schema v1 호환**: `repo_root` 필드가 없는 legacy entry는 `project == $PROJECT AND branch == $BRANCH`로 매칭

`--sha`/`--file` 인자가 있으면 해당 조건을 추가로 AND. `--sha`는 엔트리의 `base_sha` 또는 legacy `sha` 둘 다와 비교한다.

pending이 0개면:
```
No pending verifications for {project}/{branch}. Queue empty.
```
로 종료.

### Step 2: 사용자 확인 + 배치 캡

```
[Verify] {N} pending verifications for {project}/{branch}:
- SHA abc123 / file: src/foo.ts
- SHA def456 / file: src/bar.ts
...

Estimated: ~60s × {N} = ~{total}s, ~${cost} USD.
Proceed? [Y/n]
```

**배치 캡 규칙** (비용 안전장치):
- `N ≤ 10` → 단일 확인으로 전체 처리
- `N > 10` → 기본 첫 10건만 처리. 나머지는 queue에 유지. 사용자 재호출로 다음 배치 진행
- `--max-batch <n>` 인자로 기본 10을 override 가능 (상한은 자기 판단)
- `{cost}` 산정은 entry당 ~$0.15 USD (Codex medium reasoning reviewer + judge) 보수적 추정

`Y` → Step 2.5 진행.
`n` → 종료 (queue 그대로 유지).
`--dry-run` → 큐 내용만 표시하고 종료.

### Step 2.5: Pre-flight 기계검증

Reviewer 호출 전에 각 entry의 diff에 대해 프로젝트 네이티브 기계검증을 먼저 실행한다. 결과는 reviewer 프롬프트의 `INPUT` 섹션에 포함되어 cold-read reviewer가 AI-generated 코드의 전형적 opacity 패턴(unused import, any-type drift, 실패 test 등)을 직접 질문으로 전환할 수 있게 한다.

**감지 규칙** (repo root 기준, 감지된 것만 실행):
- `package.json` + `scripts.typecheck` → `npm run typecheck`
- `tsconfig.json` 존재, typecheck 스크립트 없으면 → `npx tsc --noEmit`
- `pyproject.toml` 또는 `setup.cfg` → `ruff check .` (있으면) + `python -m pytest --collect-only`
- `Cargo.toml` → `cargo check --message-format=short`
- `go.mod` → `go vet ./...`
- `.swiftlint.yml` → `swiftlint lint --quiet`
- 공통 lint: `npm run lint` / `eslint` / `shellcheck` / `bats` 감지 시 실행

**실행 규칙**:
- 각 명령은 30초 timeout. 초과 → `"(pre-flight: timeout)"` 기록 후 계속
- exit code 비零 → stdout/stderr 앞 30줄만 캡처해 reviewer 프롬프트에 전달
- 감지 실패 → `"(pre-flight: no machine checks configured)"` 기록
- **Hard gate 아님**. 실패해도 reviewer 호출은 진행. opacity 힌트 제공 목적.

**출력 형식** (reviewer 프롬프트 INPUT 섹션에 삽입):
```
PRE-FLIGHT MACHINE CHECKS:
- typecheck: PASS (0 errors)
- lint: FAIL (3 warnings; first: src/foo.ts:42 unused import)
- test: (pre-flight: timeout)
```

### Step 3: Reviewer 호출 (per entry)

각 entry에 대해:

1. **Diff 수집 — base_sha 계약**

   큐의 `base_sha`는 **편집 직전 HEAD**다. `git show <base_sha>`는 **이전 커밋**의 변경을 보여주므로 절대 사용 금지. 올바른 계약:

   - `base_sha == "uncommitted"` (repo에 커밋 전혀 없음)
     → `git diff --no-index /dev/null <file>` 또는 `git diff -- <file>` (현재 작업 상태 전체)

   - 현재 `HEAD == base_sha` (편집 후 아직 커밋 안 함)
     → `git diff <base_sha> -- <file>` (unstaged edit)
     → `git diff --cached <base_sha> -- <file>` (staged edit)
     → 두 결과를 합쳐 reviewer에게 전달

   - 현재 `HEAD != base_sha` (편집 후 하나 이상의 커밋이 있음)
     → `git diff <base_sha>..HEAD -- <file>` (base 이후 누적 변경)
     → 선택적으로 `git log --oneline <base_sha>..HEAD -- <file>`로 커밋 목록도 첨부

   - `base_sha` 필드가 없는 legacy entry (schema v1)
     → `sha` 필드를 `base_sha`로 간주하고 위 규칙 재적용

   **경계 케이스**: file이 이미 삭제됐거나 reverted된 경우 diff가 비면 "`(no changes — file reverted or deleted)`"로 표기하고 Step 7으로 스킵.

2. **Reviewer prompt 조립** (아래 "Reviewer Prompt Template" 참조)
3. **Codex 호출**:
   ```bash
   source ~/.claude/skills/gstack/bin/gstack-codex-probe 2>/dev/null || true
   codex exec "$PROMPT" -C "$(git rev-parse --show-toplevel)" \
     -s read-only -c 'model_reasoning_effort="medium"' --json < /dev/null
   ```
   JSON 스트림에서 `item.completed` / `agent_message`만 파싱해 질문 수집.

4. 출력된 질문들을 저장 후 Step 3.5로.

### Step 3.5: 질문 랜덤 Subset 선택 (V2c Gaming 방어 — 필수)

Reviewer가 3개 role × 2-3 질문 = **N = 5~8개** 생성한다. 저자는 그 중 **K = 3개**를 무작위로 선택해서만 답변한다. 저자가 예상 질문 전체에 답변을 미리 준비/seeding 하는 공격을 차단한다.

**선택 알고리즘**:
1. Reviewer 출력에서 "Diversity check"의 중복 쌍 제거 후 남은 유효 질문 = `pool`
2. `len(pool) < 3` → verification trivial로 판정 후 Step 7로 스킵 (질문이 너무 적으면 randomization 의미 없음)
3. `len(pool) ≥ 3` → 시드를 `sha + current_timestamp`로 고정해 결정적 무작위성 확보 (로그 재현성 유지). `pool`에서 3개 독립 선택
4. 선택된 K=3만 Step 4로 전달. 미선택 질문은 artifact에 `skipped_by_v2c` 섹션으로 기록 (투명성)

**예외 - `--all-questions` 플래그**:
- 디버깅 용도로 전체 pool에 답변하고 싶을 때만 사용
- artifact에 `v2c_bypassed: true` 경고 포함
- Production 실행에서는 사용 금지 (gaming 저항성 포기 선언)

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
- **V2b** LLM judge verifiability check → `GAMING_DETECTED` = fail (실 차단선)
- **V2c** Reviewer가 pool N=5~8 생성, 저자는 K=3 랜덤 subset에만 답변 (Step 3.5 참조). 예측 seeding 방해. `--all-questions` 플래그로만 bypass 가능.

Stage 0 실측(2026-04-20): V1만으로는 3/3 gaming case 전부 통과. V2b judge가 실 차단선. V2c 랜덤화로 seeding 공격의 사전 준비 비용 증가. **셋 모두 필수**.

## Platform Support

- **Claude**: hook queue + `/verify` skill 둘 다 지원
- **Codex**: `/verify` skill만 수동 호출 (Write|Edit post-hook 부재로 queue 자동 append 불가). `/verify --sha <sha>` 또는 `--file <path>`로 수동 지정 사용.

## Fallback Mode

`codex` CLI가 PATH에 없거나 `codex login`이 안 된 경우의 degraded 모드. **이 모드에서 Agent tool 사용은 이 스킬의 `allowed-tools`에 `Agent`가 명시되어 있어야 작동한다** (frontmatter 참조).

1. **Reviewer fallback**: Claude subagent를 `Agent` tool로 띄워 cold-read reviewer 역할 수행. 질문 pool 생성 (3 roles 통합 프롬프트 그대로). Diversity 손실 경고를 artifact에 기록
2. **Judge fallback**: Reviewer와 **별개의** Claude subagent를 새로 띄워 V2b verifiability check 수행. 동일 subagent 재사용 금지 (의심의 여지 없이 collusion). Collusion risk 경고를 artifact에 기록
3. **Artifact 플래그**: `degraded_mode: true`, `reviewer: claude-subagent`, `judge: claude-subagent`를 Validator Report에 각인
4. **사용자 알림**: 결과 요약에 "⚠️ DEGRADED_MODE — reviewer/judge 모두 Claude 기반. Codex 복구 권장: `codex login`" 출력

**허용되지 않는 fallback 패턴**:
- 저자 모델과 **같은** 세션 컨텍스트로 reviewer/judge 역할만 바꿔 호출 (= 사실상 self-review)
- Reviewer subagent의 출력을 judge subagent 프롬프트에 그대로 붙여넣고 한 번에 처리 (= 단일 세션 collusion)

Subagent 간 **대화 컨텍스트 격리**가 원칙. Agent tool의 각 호출이 독립 세션임을 이용한다.

## Arguments

- `--all` (default): 현재 project/branch의 모든 pending entry 처리 (배치 캡 적용)
- `--sha <sha>` : 특정 sha만 처리
- `--file <path>` : 특정 파일과 관련된 entry만
- `--dry-run` : queue 내용만 표시하고 실제 호출 없이 종료
- `--max-batch <n>` : 1회 호출당 처리할 entry 최대값 (기본 10, Step 2 배치 캡 참조)
- `--all-questions` : V2c 랜덤화 bypass. 전체 질문 pool에 답변. 디버깅 전용, production 금지

## Related Skills

- `gc` — 오래된 queue entry / qa artifact 정리 (향후 gc 확장)
- `ship` / `pr` — PR 생성 시 qa/ artifact를 본문에 첨부하는 통합 (향후)
- `investigate` — FAIL 원인 디버깅 시 참조

## Important Rules

- **Never skip V2b judge check**. V1만으로는 gaming 완전 탐지 불가 (Stage 0 실측).
- **Never skip V2c randomization**. `--all-questions`는 디버깅 전용. production 실행에서 artifact에 `v2c_bypassed: true`가 남으면 그 검증은 무효.
- **Judge 모델은 저자와 반드시 다름**. config override 금지.
- **모든 artifact는 `.ai-symbiote/qa/` 저장**. PR 본문에 링크 가능한 영구 경로.
- **Queue entry 삭제는 PASS 후에만**. FAIL은 queue 유지 → 다음 /verify에서 재시도.
- **사용자 요청 시에만 실행**. 자동 강제 실행 없음 (edit flow 방해 금지).
- **배치 캡 우회 금지**. N > 10일 때 한 번에 밀어붙이는 것은 비용 사고 위험. 10건씩 잘라 진행.
- **Pre-flight는 hard gate 아님**. 기계검증 실패해도 Q&A는 진행. 실패 정보를 reviewer에게 전달해 더 날카로운 질문 유도.
