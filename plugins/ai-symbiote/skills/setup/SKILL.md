---
name: setup
description: 프로젝트 부트스트랩. 코드베이스를 분석하여 프로젝트 스택을 감지하고 공용 Symbiote 상태를 초기화합니다.
argument-hint:
user-invocable: true
allowed-tools: [Read, Write, Edit, Glob, Grep, Bash]
---

# Setup Skill

프로젝트를 분석하고 `~/ai-symbiote/{slug}/` 아래에 공용 상태 디렉터리를 준비합니다.

## 상태 디렉터리

모든 플랫폼은 `~/ai-symbiote/{slug}/`를 공용으로 사용합니다.

- `manifest.json`
- `context.md`
- `state/`
- `taskmaster/`
- `usage-data/`
- `messenger/`

## 기본 워크플로우

1. 프로젝트 slug를 계산합니다.
2. `~/ai-symbiote/{slug}/` 디렉터리를 만듭니다.
3. `usage-data/`, `state/`, `taskmaster/`, `messenger/`를 초기화합니다.
4. `manifest.json`과 `context.md` 생성 준비 상태를 점검합니다.
5. 현재 플랫폼이 Claude인지 Codex인지 확인하고 후속 안내를 출력합니다.

## 메모

이 스킬은 통합 저장소 기준의 공용 설명서입니다. 플랫폼별 커맨드 이름과 설치 절차는 각 플랫폼 오버레이 문서를 따릅니다.
