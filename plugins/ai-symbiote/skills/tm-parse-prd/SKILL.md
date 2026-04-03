---
name: tm-parse-prd
description: "prd.json을 읽어 작업별 task.json 초안을 생성하거나 갱신합니다."
argument-hint: "task-folder --append"
user-invocable: true
allowed-tools: [Read, Write, Bash]
---

# TM Parse PRD

prd.json을 읽어 작업별 task.json 초안을 생성하거나 갱신합니다.

## 상태 디렉터리

`~/ai-symbiote/{slug}/taskmaster/`

## 동작

1. 대상 `prd.json` 위치를 확인합니다 (`~/ai-symbiote/{slug}/taskmaster/prd.json`).
2. `${CODEX_PLUGIN_ROOT:-$CLAUDE_PLUGIN_ROOT}/taskmaster/tasks.template.json` 기반으로 task.json을 준비합니다.
3. `userStories[]`를 top-level task 또는 subtask 후보로 해석합니다.
4. `dependsOn[]`를 `dependencies[]`로 변환합니다.
5. `acceptanceCriteria[]`를 `testStrategy` 또는 subtask 검증 항목으로 변환합니다.

## 원칙

- `prd.json`은 원본 요구사항으로 유지합니다.
- `task.json`은 실행용 정규화 결과입니다.
- 변환 과정에서 `userStories` 연결을 잃지 않습니다.
