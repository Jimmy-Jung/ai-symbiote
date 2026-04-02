---
name: review
description: 현재 변경사항에 대해 코드 리뷰를 실행합니다.
argument-hint: [file or directory]
user-invocable: true
allowed-tools: [Read, Glob, Grep, Bash, Agent]
---

# Review

synapse 오케스트레이터의 review 팀을 구성하여 코드 리뷰를 수행합니다.

## 팀 구성

- 팀 템플릿: `review`

### 단계별 팀 투입

| 순서 | 역할 | 수량 | 목적 |
|------|------|------|------|
| Wave 1 | Scout | 1 | 변경 파일의 관련 코드, 의존성, 테스트 수집 |
| Wave 2 | Inspector | 2~3 (병렬) | 서로 다른 관점으로 리뷰 |

### Inspector 배분 전략
- Inspector-001: 코드 품질 (가독성, 복잡도, 중복)
- Inspector-002: 패턴 준수 (아키텍처, 네이밍, 컨벤션)
- Inspector-003: 잠재 버그 + 성능 (null 참조, 경계 조건, N+1)
- Inspector-004: 보안 리뷰 (manifest.json enableSecurityReview = true 시)

## 변경사항 수집

- `git diff --staged`와 `git diff`로 변경 내용 확인
- 인자로 파일/디렉터리가 지정되면 해당 범위만 리뷰

## 결과 보고

synapse가 모든 Inspector 결과를 합산하여 통합 리뷰 보고서를 작성합니다:
- severity 기준 정렬: Critical > Warning > Suggestion
- 각 항목에 파일 경로와 라인 번호 포함
- 수정 제안 포함
