---
name: team-templates
description: 팀 구성 템플릿. synapse 오케스트레이터가 작업 유형에 따라 서브에이전트 팀을 구성할 때 참조합니다. analysis, implementation, review, planning, research, dynamic 6개 템플릿을 정의합니다.
user-invocable: false
---

# Team Templates -- 팀 구성 템플릿

synapse 오케스트레이터가 작업 유형별로 최적의 팀을 구성할 때 참조하는 템플릿.
각 템플릿은 역할 배치, 단계 순서, 병렬화 규칙, 결과 합성 전략을 정의합니다.

## 템플릿 선택 기준

| 작업 유형 | 템플릿 | 트리거 |
|----------|--------|--------|
| 심층 분석, 리서치, 아키텍처 분석 | analysis | analyze 워크플로우, "심층 분석", "구조 분석" |
| 기능 구현, 버그 수정, 자율 실행 | implementation | auto-loop, autopilot, "끝까지", "구현" |
| 코드 리뷰, PR 리뷰 | review | review 워크플로우, "코드 리뷰" |
| 구현 계획 수립 | planning | planning 워크플로우, "계획 수립" |
| 외부 조사, 마이그레이션 계획 | research | "조사", "리서치", "마이그레이션" |
| 위 어디에도 해당 안 됨 | dynamic | synapse가 작업 분석 후 판단 |

---

## Template: analysis

심층 분석 팀. 코드베이스를 다각도로 탐색하고 구조화된 분석 결과를 생성합니다.

### 팀 구성

| 순서 | 역할 | 수량 | 실행 | 목적 |
|------|------|------|------|------|
| Wave 1 | Scout | 2~3 | 병렬 | 서로 다른 탐색 전략으로 정보 수집 |
| Wave 2 | Architect | 1 | 순차 | Scout 결과를 합성하여 구조화된 분석 |

### 병렬화 규칙
- Wave 1: Scout들은 서로 다른 검색 전략을 할당받아 병렬 실행
  - Scout-001: Grep 기반 정확 매칭 (심볼, import)
  - Scout-002: Glob 기반 파일 패턴 탐색 (구조, 네이밍)
  - Scout-003: subagent(explorer) 기반 심층 탐색 (선택적, 복잡한 분석 시)
- Wave 2: 모든 Scout 완료 후 Architect 실행

### 결과 합성
오케스트레이터가 Architect의 결과 파일을 읽어 사용자에게 보고합니다.

### 적용 스킬
- analyze 워크플로우
- "심층 분석", "깊이 파악" 자연어 트리거

---

## Template: implementation

구현 팀. 분석부터 구현, 검증까지 전 과정을 처리합니다.
auto-loop과 autopilot의 4-Phase 파이프라인을 팀 기반으로 실행합니다.

### 팀 구성

| 순서 | 역할 | 수량 | 실행 | 목적 |
|------|------|------|------|------|
| Phase 0: Analyze | Scout | 1~2 | 병렬 | 요구사항 분석, 코드베이스 탐색 |
| Phase 1: Plan | Architect | 1 | 순차 | Scout 결과 기반 구현 계획 |
| Phase 2: Execute | Builder | 1~3 | 병렬(독립 단계) | Architect 계획에 따른 코드 구현 |
| Phase 3: Verify | Inspector | 1 | 순차 | 구현 결과 검증 |

### 병렬화 규칙
- Phase 0: Scout들은 병렬 실행 (요구사항 분석 + 코드베이스 탐색)
- Phase 1: Scout 결과 수집 후 Architect 실행
- Phase 2: Architect가 병렬 가능으로 표시한 단계들을 별도 Builder에 배분
- Phase 3: 모든 Builder 완료 후 Inspector 실행

### Codex 연동 (선택적)

Codex가 사용 가능하면 implementation 팀에서 다음과 같이 활용합니다:

| 상황 | Codex 투입 방식 |
|------|----------------|
| Builder 동일 오류 2회 반복 | Codex를 Builder 대체로 투입 (다른 모델의 세컨드 오피니언) |
| Inspector FAIL + 원인 불명 | Codex rescue로 root cause 진단 |
| Phase 3 Verify | Inspector와 Codex review를 병렬 실행 (이중 검증) |
| 보안 검토 필요 (Level 4) | Codex adversarial-review 추가 투입 |

Codex가 unavailable이면 이 섹션을 건너뛰고 Claude 에이전트만으로 진행합니다.

### 모드 변형

#### autonomous 모드 (auto-loop)
- Loop 활성화: Inspector FAIL 시 Phase 2로 회귀
- maxIterations: 10 (기본값, manifest.json에서 오버라이드 가능)
- completionLevel: 2 (기본값)
- 에스컬레이션: maxIterations 도달, 동일 오류 3회, 파괴적 변경
- Codex 투입: 동일 오류 2회 반복 시 자동 (available한 경우)

#### parallel-max 모드 (autopilot)
- Builder 수를 최대화 (독립 단계 수만큼)
- maxIterations: 3
- Loop 실패 시 접근 방식 변경 후 재시도
- Codex 투입: 1회차 실패 시 즉시 Codex rescue 시도 (available한 경우)

### 결과 합성
오케스트레이터가 각 Phase의 결과를 읽고 다음 Phase로 진행 여부를 결정합니다.
Inspector FAIL 시: 이슈 분석 -> 수정 계획 -> Builder 재디스패치.

### 적용 스킬
- auto-loop (autonomous 모드)
- autopilot (parallel-max 모드)
- "끝까지", "최대 성능" 자연어 트리거

---

## Template: review

리뷰 팀. 코드 변경사항을 다각도로 검증합니다.

### 팀 구성

| 순서 | 역할 | 수량 | 실행 | 목적 |
|------|------|------|------|------|
| Wave 1 | Scout | 1 | 순차 | 변경 사항 주변 컨텍스트 수집 |
| Wave 2 | Inspector | 2~3 | 병렬 | 서로 다른 관점으로 리뷰 |

### 병렬화 규칙
- Wave 1: Scout가 변경 파일의 관련 코드, 의존성, 테스트를 수집
- Wave 2: Inspector들은 서로 다른 리뷰 관점을 할당받아 병렬 실행
  - Inspector-001: 코드 품질 (가독성, 복잡도, 중복)
  - Inspector-002: 패턴 준수 (아키텍처, 네이밍, 컨벤션)
  - Inspector-003: 잠재 버그 + 성능 (널 참조, 경계 조건, N+1)
  - (manifest.json enableSecurityReview = true 시) Inspector-004: 보안 리뷰

### Codex 연동 (선택적)

Codex가 사용 가능하면 review 팀에서 다음과 같이 활용합니다:

- Inspector들과 병렬로 `Skill(skill: "codex:review")` 실행 → Claude + Codex 이중 리뷰
- 보안 리뷰 요청 시 `Skill(skill: "codex:adversarial-review")` 추가 → 적대적 관점 리뷰
- Codex 리뷰 결과(JSON verdict)를 Inspector 결과와 합산

Codex가 unavailable이면 Inspector만으로 리뷰합니다.

### 결과 합성
오케스트레이터가 모든 Inspector + Codex 결과를 합산하여 통합 리뷰 보고서를 작성합니다.
severity 기준 정렬: critical > warning > suggestion.
Codex findings는 출처를 "[Codex]"로 표시하여 구분합니다.

### 적용 스킬
- review 워크플로우

---

## Template: planning

계획 팀. 구현 전 실행 가능한 계획을 수립합니다.

### 팀 구성

| 순서 | 역할 | 수량 | 실행 | 목적 |
|------|------|------|------|------|
| Wave 1 | Scout | 2 | 병렬 | 코드베이스 구조 + 유사 구현 탐색 |
| Wave 2 | Architect | 1 | 순차 | Scout 결과 기반 상세 계획 수립 |

### 병렬화 규칙
- Wave 1: Scout 병렬 (구조 탐색 + 유사 패턴 탐색)
- Wave 2: Scout 결과 수집 후 Architect 실행

### 결과 합성
오케스트레이터가 Architect 결과를 EnterPlanMode로 사용자에게 제시합니다.
사용자 승인 후 implementation 팀으로 전환 가능.

### 적용 스킬
- planning 워크플로우

---

## Template: research

리서치 팀. 외부 정보와 코드베이스 내부 정보를 결합합니다.

### 팀 구성

| 순서 | 역할 | 수량 | 실행 | 목적 |
|------|------|------|------|------|
| Wave 1 | Scout + Researcher | 2~4 | 병렬 | 내부 탐색 + 외부 조사 동시 진행 |
| Wave 2 | Architect | 1 | 순차 | 내/외부 결과 합성하여 보고서 작성 |

### 병렬화 규칙
- Wave 1: Scout (코드베이스)와 Researcher (외부 문서/API)를 병렬 실행
- Wave 2: 모든 결과 수집 후 Architect가 합성

### 적용 스킬
- "조사", "리서치", "마이그레이션" 자연어 트리거

---

## Template: dynamic

동적 팀. 위 템플릿에 해당하지 않는 작업에 대해 synapse가 직접 구성합니다.

### 구성 규칙
1. 항상 Scout 1명으로 시작 (코드베이스 파악)
2. Scout 결과를 읽고 필요한 역할을 추가 투입
3. 최대 5명 제한 유지
4. 각 역할 투입 시 roles/SKILL.md의 프롬프트 템플릿 사용

### 의사결정 트리
```
Scout 결과 분석
├─ 코드 변경 필요 → Builder 투입
├─ 계획 수립 필요 → Architect 투입
├─ 검증 필요 → Inspector 투입
├─ 외부 정보 필요 → Researcher 투입
└─ 추가 탐색 필요 → Scout 추가 투입
```

---

## 공통 프로토콜

### team-manifest.json

모든 팀은 task-folder에 `team-manifest.json`을 생성하여 팀 상태를 추적합니다.

```json
{
  "taskId": "{task-folder}",
  "template": "{template-name}",
  "phase": "{current-phase}",
  "agents": [
    {
      "id": "scout-001",
      "role": "scout",
      "model": "sonnet",
      "status": "complete",
      "resultPath": "results/scout-001.result.md"
    }
  ],
  "decisions": [
    {
      "timestamp": "ISO8601",
      "decision": "Scout 결과 기반으로 Builder 3명 병렬 투입 결정"
    }
  ]
}
```

### 에스컬레이션
팀 내에서 해결 불가한 상황 발생 시, 오케스트레이터가 사용자에게 에스컬레이션합니다.
메신저 브릿지가 활성화되어 있으면 메신저를 통해 에스컬레이션합니다.
(상세: auto-loop/SKILL.md의 메신저 브릿지 연동 섹션)

### 결과 파일 정리
팀 완료 후 결과 파일은 task-folder에 보존됩니다.
clean 워크플로우로 정리 가능.
