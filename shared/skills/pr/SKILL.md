---
name: pr
description: 현재 브랜치의 변경사항을 분석하고 Pull Request를 생성합니다.
argument-hint: [base-branch]
user-invocable: true
allowed-tools: [Read, Glob, Grep, Bash]
---

# PR

현재 브랜치의 변경사항을 분석하고 Pull Request를 생성합니다.

## 워크플로우

### 1. 컨텍스트 로드
- `~/ai-symbiote/{slug}/context.md`를 읽어 프로젝트 컨벤션 파악

### 2. 변경사항 분석
- `git status`, `git diff`, `git log`으로 변경사항 분석
- 인자로 base-branch가 지정되면 해당 브랜치와 비교

### 3. PR 생성
- PR 제목: 70자 이내, 변경 내용 요약
- PR 본문:
  ```
  ## Summary
  - 변경 사항 요약 (1-3 bullet points)

  ## Test Plan
  - 테스트 계획 체크리스트
  ```
- 브랜치를 push하고 `gh pr create`로 PR 생성

### 4. 결과
- PR URL을 사용자에게 반환
