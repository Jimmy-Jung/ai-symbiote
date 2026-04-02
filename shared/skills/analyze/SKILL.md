---
name: analyze
description: 대상에 대해 심층 분석을 수행합니다.
argument-hint: <analysis target>
user-invocable: true
allowed-tools: [Read, Glob, Grep, Bash, Agent]
---

# Analyze

synapse 오케스트레이터의 analysis 팀을 구성하여 대상을 심층 분석합니다.

## 팀 구성

- 팀 템플릿: `analysis`

### 단계별 팀 투입

| 순서 | 역할 | 수량 | 목적 |
|------|------|------|------|
| Wave 1 | Scout | 2~3 (병렬) | 서로 다른 전략으로 정보 수집 |
| Wave 2 | Architect | 1 | Scout 결과를 합성하여 구조화된 분석 |

### Scout 배분 전략
- Scout-001: Grep 기반 정확 매칭 (심볼, import, 타입 참조)
- Scout-002: Glob 기반 파일 패턴 탐색 (구조, 네이밍 컨벤션)
- Scout-003: subagent(explorer) 심층 탐색 (복잡한 분석 시 선택적 투입)

## 분석 결과 구조

Architect가 다음 구조로 분석 결과를 정리합니다:
- 누락된 정보 (Missing Questions)
- 범위 리스크 (Scope Risks)
- 미검증 가정 (Unvalidated Assumptions)
- 엣지 케이스 (Edge Cases)
- 권장 사항 (Recommendations)

## 핸드오프

분석 완료 후 필요 시 planning 워크플로우로 계획 수립을 제안합니다.
