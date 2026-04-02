---
name: planning
user-invocable: true
description: 새 기능 계획, 리팩토링, 코드베이스 구조 분석 시 사용하는 개발 계획 방법론. This skill should be used when planning new features, refactoring, or analyzing codebase structure before implementation.
---

# 개발 계획 (Development Planning)

언어/플랫폼에 무관하게 적용되는 소프트웨어 개발 계획 방법론.

## 요구사항 인터뷰

구현 전 다음 질문으로 목표를 명확히 한다:

- What: 무엇을 구현/변경하는가?
- Why: 왜 필요한가? 해결하려는 문제는?
- How: 선호하는 접근 방식이 있는가?
- Success criteria: 언제 완료된 것으로 보는가?

추측하지 말고, 모호하면 사용자에게 확인한다.

## 필수 정보 수집

### 기술 컨텍스트
- 언어: 단일 언어 또는 하이브리드
- 프레임워크: 사용 중인 UI/백엔드 프레임워크
- 아키텍처 패턴: MVVM, Clean, MVC, 레이어드 등
- 의존성 관리: package.json, Package.swift, requirements.txt, build.gradle 등

### 기존 패턴
- 유사 기능이 어떻게 구현되어 있는가?
- 네이밍 컨벤션, 파일 구조
- 테스트 패턴

## 코드베이스 검색 전략

### 병렬 검색
Grep, Glob를 동시에 활용한다:

- Grep: 정확한 타입명, 메서드명, import 관계
- Glob: 특정 패턴의 파일 목록 (예: *Repository*, *ViewModel*)
- subagent(explorer): 넓은 범위의 코드베이스 탐색이 필요할 때

### 검색 대상
- 유사 기능: 참고할 기존 구현
- 네이밍 컨벤션: 클래스/함수/파일명 규칙
- 아키텍처 패턴: 레이어 구조, 의존성 방향
- 테스트 패턴: 기존 테스트 위치와 구조

## 영향도 평가 매트릭스

| 항목 | 내용 | 확인 방법 |
|------|------|----------|
| 직접 변경 | 수정/추가/삭제할 파일 | Grep으로 참조 추적 |
| 간접 영향 | 의존하는 모듈, 호출하는 코드 | import 분석 |
| Breaking change | API 변경, 시그니처 변경 | 사용처 전체 검색 |
| 리스크 | 예상치 못한 영향 가능 영역 | 경계 모듈, 외부 연동 |

## 구현 계획 템플릿

```
목표 (Goal)
  - 명확히 정의된 달성 목표

영향 분석 (Impact)
  - 직접 변경 대상
  - 간접 영향 범위
  - Breaking change 여부

단계 (Steps)
  1. [단계명] - [의존성] - [검증 방법]
  2. ...

리스크 (Risks)
  - 예상 리스크와 대응 방안

검증 계획 (Verification)
  - 어떻게 완료 여부를 확인하는가
```

## 원칙

1. 추측 금지: 코드베이스 검색으로 확인한다.
2. 병렬 탐색: Grep, Glob 등을 동시에 활용한다.
3. 기존 패턴 존중: 새 패턴을 만들지 않고 기존 패턴을 따른다.
4. 단계별 검증: 각 단계에 검증 수단을 포함한다.
5. 선제적 리스크 식별: 구현 전에 리스크를 정리한다.

## Role Injection: Architect

이 섹션은 synapse 오케스트레이터가 Architect 서브에이전트를 스폰할 때 프롬프트에 주입됩니다.

Architect는 위의 요구사항 인터뷰, 필수 정보 수집, 영향도 평가 매트릭스, 구현 계획 템플릿을 따릅니다.
Scout 결과 파일을 읽어 코드베이스 정보를 확보한 후, 구현 계획을 수립하세요.
Builder에게 배분할 작업 단위를 명확히 정의하고, 병렬 실행 가능 여부를 표시하세요.
결과는 반드시 지정된 result 파일에 markdown으로 작성하세요.
