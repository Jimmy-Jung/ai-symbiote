---
name: plan
description: 구현 계획을 수립합니다. 요구사항을 분석하고 단계별 구현 계획을 생성합니다.
argument-hint: <task description>
user-invocable: true
allowed-tools: [Read, Glob, Grep, Bash, Agent]
---

# Plan

synapse 오케스트레이터의 planning 팀을 구성하여 구현 계획을 수립합니다.

## 팀 구성

- 팀 템플릿: `planning`

### 단계별 팀 투입

| 순서 | 역할 | 수량 | 목적 |
|------|------|------|------|
| Wave 1 | Scout | 2 (병렬) | 코드베이스 구조 + 유사 구현 탐색 |
| Wave 2 | Architect | 1 | Scout 결과 기반 상세 계획 수립 |

### Scout 배분 전략
- Scout-001: 코드베이스 구조 탐색 (아키텍처, 레이어, 의존성)
- Scout-002: 유사 기능/패턴 탐색 (참고할 기존 구현)

## 계획 제시

synapse가 Architect 결과를 읽어 EnterPlanMode로 사용자에게 제시합니다.
사용자 승인 후 implementation 팀으로 전환 가능.

## 원칙

- task-folder를 생성하지 않습니다
- 중간 파일을 저장하지 않습니다 (Scout/Architect 결과는 임시 사용 후 폐기)
- 모든 분석과 계획은 사용자 승인을 위한 것입니다
