---
name: clean
description: 완료된 작업의 상태 폴더를 정리합니다.
argument-hint: [task-folder-name | --all | --force]
user-invocable: true
allowed-tools: [Read, Bash, Glob]
---

# Clean

완료된 작업의 상태 폴더를 정리합니다.

## 상태 디렉터리

`~/ai-symbiote/{slug}/state/`

## 워크플로우

1. `~/ai-symbiote/{slug}/state/` 하위 모든 task-folder를 스캔합니다.
2. 각 폴더의 `ralph-state.md`를 확인합니다:
   - `active: false` 또는 `ralph-state.md` 없음 -> 완료된 작업
   - `active: true` -> 진행 중 (건너뜀)
3. 완료된 작업 목록을 표시하고 사용자에게 삭제 확인을 요청합니다.
4. 확인 후 해당 task-folder를 삭제합니다.
5. 진행 중인 작업이 있으면 건드리지 않습니다.

## 옵션

- `--all`: 확인 없이 완료된 모든 작업 폴더 삭제
- `--force`: 진행 중인 작업 포함 전체 삭제 (주의)
- 작업명 지정: 특정 작업만 삭제 (예: `clean 2026-02-13T1430_login-feature`)
