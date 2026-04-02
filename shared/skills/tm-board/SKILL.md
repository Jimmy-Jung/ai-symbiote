---
name: tm-board
description: task graph를 상태별로 요약해 보여줍니다.
argument-hint: [--tag <tag>] [--status <status>]
user-invocable: true
allowed-tools: [Read, Bash, Glob]
---

# TM Board

task graph를 상태별로 요약해 보여줍니다.

## 상태 디렉터리

`~/ai-symbiote/{slug}/taskmaster/`

## 출력 항목

- 전체 task 수
- 상태별 개수 (pending, in_progress, review, done, blocked)
- 현재 `currentTaskId`
- `blocked` task 목록
- 실행 가능한 `pending` 후보

## 동작

1. `~/ai-symbiote/{slug}/taskmaster/tasks.json`을 읽습니다.
2. `~/ai-symbiote/{slug}/taskmaster/state.json`을 읽습니다.
3. 태스크를 상태별로 분류하여 보드 형태로 출력합니다.

## 원칙

- task graph가 없으면 "not initialized"를 반환합니다.
- 보드 출력은 상태 요약이며, 세부 수정은 각 tm-* 워크플로우가 담당합니다.
