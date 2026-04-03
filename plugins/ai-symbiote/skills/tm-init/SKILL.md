---
name: tm-init
description: Task Master 전역 task graph 상태를 초기화합니다.
argument-hint: [--tag <tag>]
user-invocable: true
allowed-tools: [Read, Write, Bash]
---

# TM Init

Task Master형 전역 task graph 상태를 초기화합니다.

## 상태 디렉터리

`~/ai-symbiote/{slug}/taskmaster/`

## 동작

1. `~/ai-symbiote/{slug}/taskmaster/` 디렉터리 존재 여부를 확인합니다.
2. 없으면 디렉터리를 생성합니다.
3. `${CODEX_PLUGIN_ROOT:-$CLAUDE_PLUGIN_ROOT}/taskmaster/state.template.json`과 config 기반으로 `state.json`을 생성합니다.
4. 이미 있으면 현재 상태를 보여주고 재초기화 여부를 확인합니다.

## 초기화 스크립트

```bash
SLUG=$(프로젝트 경로 기반 slug)
STATE_DIR="$HOME/ai-symbiote/$SLUG/taskmaster"
mkdir -p "$STATE_DIR"
```

state.template.json을 복사하여 state.json 생성.

## 원칙

- 스키마 파일을 진실 기준으로 사용합니다.
- 템플릿 파일을 초기 상태 복제 원본으로 사용합니다.
- 세션 상태 폴더(`~/ai-symbiote/{slug}/state/*`)는 건드리지 않습니다.
- 기존 파일이 있으면 파괴적 덮어쓰기를 피합니다.
