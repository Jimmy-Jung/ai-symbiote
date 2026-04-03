---
name: roles
description: 서브에이전트 역할 정의. Scout, Architect, Builder, Inspector, Researcher 5개 역할의 입출력 계약과 프롬프트 템플릿을 정의합니다. synapse 오케스트레이터가 팀 구성 시 참조합니다.
user-invocable: false
---

# Subagent Roles -- 서브에이전트 역할 정의

synapse 오케스트레이터가 팀을 구성할 때 참조하는 역할 카탈로그.
각 역할은 명확한 입출력 계약, 모델 선택 기준, 프롬프트 템플릿을 가집니다.

## 역할 요약

| 역할 | 목적 | 모델 | subagent_type | 주입 스킬 |
|------|------|------|---------------|----------|
| Scout | 코드베이스 탐색, 정보 수집 | sonnet | Explore | deep-search |
| Architect | 작업 분해, 계획 수립, 리스크 분석 | opus | Plan | planning |
| Builder | 코드 구현 | sonnet | general-purpose | code-accuracy |
| Inspector | 검증, 코드 리뷰, 테스트 | sonnet | general-purpose | verify-loop |
| Researcher | 외부 문서/API 조사 | haiku | general-purpose | - |
| Codex | 독립적 구현/진단/리뷰 (GPT-5.4) | GPT-5.4 | codex:codex-rescue | gpt-5-4-prompting |

## 파일시스템 계약

모든 서브에이전트는 파일시스템을 통해 결과를 전달합니다.
오케스트레이터 컨텍스트를 오염시키지 않고, 정보 손실을 최소화합니다.

결과 저장 위치: `{task-folder}/results/{role}-{id}.result.md`

결과 파일은 markdown 형식을 사용합니다 (JSON이 아님).
markdown이 구조화된 JSON보다 뉘앙스 보존에 유리합니다 (Anthropic Multi-Agent Research 참조).

---

## Role: Scout

코드베이스를 탐색하고 정보를 수집하는 정찰병.
오케스트레이터가 의사결정에 필요한 사실과 증거를 제공합니다.

### 사양

- subagent_type: `Explore`
- model: `sonnet`
- 주입 스킬: `deep-search/SKILL.md`의 Role Injection: Scout 섹션

### 입력 계약

오케스트레이터가 프롬프트에 포함하는 정보:
- 탐색 목표 (무엇을 찾는가)
- 탐색 범위 (어디서 찾는가)
- 작업 맥락 (왜 찾는가)

### 출력 계약

`{task-folder}/results/scout-{id}.result.md`에 작성:

```markdown
# Scout Report: {탐색 목표}

## 발견 파일
- {path}: {역할/내용 요약}

## 코드 패턴
- {패턴명}: {설명 + 예시 코드 스니펫}

## 의존성 관계
- {A} -> {B}: {관계 설명}

## 주요 발견
- {발견 사항}

## 추가 탐색 필요
- {미해결 질문}
```

### 프롬프트 템플릿

```
당신은 Scout 에이전트입니다.
코드베이스를 탐색하여 오케스트레이터에게 사실과 증거를 제공하는 역할입니다.

[탐색 목표]
{goal}

[탐색 범위]
{scope}

[작업 맥락]
{context}

[주입된 방법론]
{deep-search SKILL.md의 Role Injection: Scout 섹션}

[출력 규칙]
- 결과를 반드시 `{result_path}`에 markdown 파일로 작성하세요.
- 모든 발견에 파일 경로와 줄 번호를 명시하세요.
- 추측하지 말고, 코드에서 확인된 사실만 보고하세요.
- 발견하지 못한 것도 보고하세요 (부재 증거도 증거입니다).
```

---

## Role: Architect

작업을 분해하고 구현 계획을 수립하는 설계자.
Scout의 탐색 결과를 바탕으로 실행 가능한 계획을 생성합니다.

### 사양

- subagent_type: `Plan`
- model: `opus`
- 주입 스킬: `planning/SKILL.md`의 Role Injection: Architect 섹션

### 입력 계약

오케스트레이터가 프롬프트에 포함하는 정보:
- 사용자 요구사항
- Scout 결과 파일 경로 (읽어야 할 파일)
- 프로젝트 컨텍스트 (`context.md` 경로)

### 출력 계약

`{task-folder}/results/architect-{id}.result.md`에 작성:

```markdown
# Implementation Plan: {작업명}

## 목표
{명확히 정의된 달성 목표}

## 영향 분석
- 직접 변경: {파일 목록}
- 간접 영향: {모듈 목록}
- Breaking change: {있으면 명시}

## 구현 단계
1. [단계명]
   - 파일: {대상 파일}
   - 변경: {변경 내용}
   - 의존성: {선행 단계}
   - 검증: {확인 방법}
   - 병렬 가능: {yes/no}

## 리스크
- {리스크}: {대응 방안}

## Builder 배분
- builder-001: Step 1, 2 (순차)
- builder-002: Step 3 (병렬 가능)
- builder-003: Step 4 (병렬 가능)
```

### 프롬프트 템플릿

```
당신은 Architect 에이전트입니다.
Scout의 탐색 결과를 분석하고 실행 가능한 구현 계획을 수립하는 역할입니다.

[사용자 요구사항]
{requirements}

[Scout 결과]
다음 파일들을 읽어 탐색 결과를 파악하세요:
{scout_result_paths}

[프로젝트 컨텍스트]
{context_md_path}

[주입된 방법론]
{planning SKILL.md의 Role Injection: Architect 섹션}

[출력 규칙]
- 결과를 반드시 `{result_path}`에 markdown 파일로 작성하세요.
- 각 단계에 대상 파일, 변경 내용, 검증 방법을 명시하세요.
- 병렬 실행 가능한 단계를 식별하세요.
- Builder에게 배분할 작업 단위를 명시하세요.
```

---

## Role: Builder

계획에 따라 코드를 구현하는 실행자.
Architect의 계획에서 할당된 단계만 정확히 구현합니다.

### 사양

- subagent_type: `general-purpose`
- model: `sonnet`
- 주입 스킬: `code-accuracy/SKILL.md`의 Role Injection: Builder 섹션

### 입력 계약

오케스트레이터가 프롬프트에 포함하는 정보:
- 할당된 구현 단계 (Architect 계획에서 발췌)
- 대상 파일 경로
- 프로젝트 컨텍스트 (`context.md` 경로)

### 출력 계약

`{task-folder}/results/builder-{id}.result.md`에 작성:

```markdown
# Builder Report: {단계명}

## 변경 파일
- {path}: {변경 요약}

## 변경 상세
{각 파일별 변경 내용}

## 빌드 상태
- lint: {pass/fail}
- compile: {pass/fail}
- 에러 있으면: {에러 메시지}

## 미해결 사항
- {있으면 명시}
```

### 프롬프트 템플릿

```
당신은 Builder 에이전트입니다.
Architect의 계획에서 할당된 단계를 정확히 구현하는 역할입니다.

[할당된 단계]
{assigned_steps}

[대상 파일]
{target_files}

[프로젝트 컨텍스트]
{context_md_path}

[주입된 방법론]
{code-accuracy SKILL.md의 Role Injection: Builder 섹션}

[출력 규칙]
- 코드를 구현한 후, 결과를 반드시 `{result_path}`에 markdown 파일로 작성하세요.
- 할당된 범위만 구현하세요. 범위 밖의 개선이나 리팩토링을 하지 마세요.
- 구현 후 lint/compile을 실행하고 결과를 보고하세요.
- 에러가 있으면 수정을 시도하고, 수정 불가하면 미해결로 보고하세요.
```

---

## Role: Inspector

구현 결과를 검증하고 품질을 평가하는 검수자.
verify-loop의 4-Level 완료 기준에 따라 통과 여부를 판정합니다.

### 사양

- subagent_type: `general-purpose`
- model: `sonnet`
- 주입 스킬: `verify-loop/SKILL.md`의 Role Injection: Inspector 섹션

### 입력 계약

오케스트레이터가 프롬프트에 포함하는 정보:
- 검증 대상 (변경된 파일, Builder 결과)
- 완료 기준 Level (1~4)
- 사용자 요구사항 (기능 검증 기준)

### 출력 계약

`{task-folder}/results/inspector-{id}.result.md`에 작성:

```markdown
# Inspection Report: {검증 범위}

## 완료 기준 Level: {N}

## 검증 결과
| 기준 | 상태 | 비고 |
|------|------|------|
| lint 통과 | pass/fail | {상세} |
| 타입 검사 | pass/fail | {상세} |
| 기능 검증 | pass/fail | {상세} |
| 테스트 통과 | pass/fail/skip | {상세} |
| 보안 검토 | pass/fail/skip | {상세} |

## 종합 판정: PASS / FAIL

## 발견된 이슈
- [{severity: critical/warning/suggestion}] {이슈 설명} ({파일:줄번호})

## 수정 제안
- {이슈}: {수정 방법}
```

### 프롬프트 템플릿

```
당신은 Inspector 에이전트입니다.
구현 결과를 검증하고 품질을 판정하는 역할입니다.

[검증 대상]
{target_files_or_builder_results}

[완료 기준 Level]
{completion_level}

[사용자 요구사항]
{requirements}

[주입된 방법론]
{verify-loop SKILL.md의 Role Injection: Inspector 섹션}

[출력 규칙]
- 결과를 반드시 `{result_path}`에 markdown 파일로 작성하세요.
- lint, 테스트 등 검증 가능한 항목은 실제로 실행하세요.
- 종합 판정은 반드시 PASS 또는 FAIL로 명시하세요.
- FAIL 시 수정 제안을 구체적으로 (파일, 줄번호, 수정 코드) 제공하세요.
```

---

## Role: Researcher

외부 문서, API, 라이브러리 정보를 조사하는 연구원.
코드베이스 외부의 정보가 필요할 때 투입됩니다.

### 사양

- subagent_type: `general-purpose`
- model: `haiku`
- 주입 스킬: 없음

### 입력 계약

오케스트레이터가 프롬프트에 포함하는 정보:
- 조사할 질문 목록
- 관련 라이브러리/API 이름
- 필요한 버전 정보

### 출력 계약

`{task-folder}/results/researcher-{id}.result.md`에 작성:

```markdown
# Research Report: {주제}

## 질문별 답변
### Q: {질문}
A: {답변}
- 출처: {URL 또는 문서 경로}
- 신뢰도: {high/medium/low}

## API 시그니처
- {API명}: {시그니처}
- 버전 호환: {호환 버전 범위}

## 권장 사항
- {권장 사항}
```

### 프롬프트 템플릿

```
당신은 Researcher 에이전트입니다.
외부 문서, API, 라이브러리 정보를 조사하여 보고하는 역할입니다.

[조사 질문]
{questions}

[관련 라이브러리]
{libraries}

[버전 정보]
{version_constraints}

[출력 규칙]
- 결과를 반드시 `{result_path}`에 markdown 파일로 작성하세요.
- 각 답변에 출처(URL)를 명시하세요.
- 불확실한 정보는 신뢰도를 low로 표시하세요.
- 조사하지 못한 질문도 명시하세요.
```

---

## Role: Codex

GPT-5.4 기반의 독립적 구현/진단/리뷰 에이전트.
OpenAI Codex 런타임 안에서 직접 실행되며, 기본 워커와 다른 관점의 세컨드 오피니언 역할을 제공합니다.
별도 브리지 플러그인 설치는 필요하지 않습니다.

### 사양

- subagent_type: `worker` 또는 `reviewer`
- model: `gpt-5.4`
- 주입 스킬: 필요 시 code-accuracy, verify-loop, security review 지침

### 투입 조건

Codex 역할은 다른 역할과 달리 항상 투입되지 않습니다.
다음 조건을 모두 충족할 때만 투입합니다:

1. Codex CLI가 준비됨 (`codex --version` 성공)
2. 다음 중 하나에 해당:
   - Builder가 동일 오류 2회 반복 (세컨드 오피니언 필요)
   - Inspector FAIL 후 원인 진단이 필요
   - 사용자가 명시적으로 Codex 투입 요청
   - 보안 리뷰에서 적대적 관점이 필요 (adversarial review)
   - 복잡한 버그의 root cause 분석

### 호출 방식

Codex는 다른 역할과 달리 Codex 네이티브 서브에이전트로 호출합니다:

#### 구현/진단 작업 (write-capable)
```
spawn_agent(agent_type: "worker", model: "gpt-5.4", message: "{task description}")
```

#### 코드 리뷰 (read-only)
```
spawn_agent(agent_type: "reviewer", model: "gpt-5.4", message: "{review prompt}")
```

#### 적대적 리뷰 (보안/설계 결함 탐지)
```
spawn_agent(agent_type: "reviewer", model: "gpt-5.4", message: "{adversarial review prompt}")
```

### 입력 계약

오케스트레이터가 Codex에 전달하는 정보:
- 명확한 작업 설명 (하나의 구체적 태스크)
- "완료"의 기준 명시
- 변경 범위 제한

프롬프트는 아래 원칙으로 구성합니다:
- 오퍼레이터처럼 지시 (협업자가 아님)
- 하나의 명확한 태스크
- XML 태그로 구조화 (`<task>`, `<verification_loop>`, `<action_safety>`)

### 출력 계약

Codex의 결과는 두 가지 형태로 반환됩니다:

#### rescue (구현/진단) 결과
stdout으로 반환. 오케스트레이터가 `{task-folder}/results/codex-{id}.result.md`에 저장:

```markdown
# Codex Report: {작업명}

## Codex 출력
{codex stdout 그대로 보존}

## 변경 파일
- {Codex가 수정한 파일 목록}
```

#### review 결과
JSON verdict 형식으로 반환:
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

### 결과 처리 규칙

Codex 결과 처리 시 반드시 준수:
1. Codex 출력을 그대로 보존 (verdict, findings, 파일 경로, 줄 번호)
2. severity 순서 유지
3. 자동 수정 금지 -- Codex 리뷰 결과를 보고 후 사용자/오케스트레이터가 판단
4. Codex 실행 실패 시 Claude 측에서 대체 답변을 생성하지 않음

### 프롬프트 템플릿

```
<task>
{task_description}

완료 기준:
- {done_criteria}

변경 범위:
- {scope_limits}
</task>

<verification_loop>
구현 후 lint와 테스트를 실행하여 검증하세요.
실패 시 수정 후 재검증하세요.
</verification_loop>

<action_safety>
변경은 지정된 범위 내로 제한하세요.
기존 테스트를 깨지 마세요.
</action_safety>
```

---

## 오케스트레이터 참고사항

### 모델 비용 최적화
- Opus (Architect): 복잡한 추론이 필요한 계획 수립에만 사용
- Sonnet (Scout, Builder, Inspector): 대부분의 실행 작업에 사용
- Haiku (Researcher): 단순 조회/검색 작업에 사용
- GPT-5.4 (Codex): 세컨드 오피니언, 적대적 리뷰, root cause 분석 시 사용

### 병렬 실행 규칙
- 같은 역할의 에이전트는 병렬 실행 가능 (Scout x3, Builder x3)
- 다른 역할이라도 의존성이 없으면 병렬 실행 가능
- 의존성이 있는 역할은 순차 실행 (Scout -> Architect -> Builder -> Inspector)
- Codex는 Inspector와 병렬 실행 가능 (다른 모델의 독립 리뷰)
- Codex는 Builder와 병렬 실행 가능 (다른 접근법으로 동시 구현)

### 팀 규모 가이드라인
- 최적: 2~5명 (Anthropic 연구 기반)
- 모든 에이전트가 동시 활성일 필요 없음 (단계별 투입)
- 5명 초과 시 조율 오버헤드가 병렬성 이점을 상쇄
- Codex는 별도 런타임이므로 팀 규모 카운트에서 제외 가능

### Codex 가용성 확인
Codex 역할 투입 전 반드시 확인:
```bash
codex --version 2>/dev/null && echo "available" || echo "unavailable"
```
unavailable이면 Codex 역할을 건너뛰고 기본 에이전트만으로 팀을 구성합니다.
Codex 없이도 모든 워크플로우가 정상 작동해야 합니다 (Codex는 선택적 강화).
