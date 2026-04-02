---
name: git-commit
user-invocable: true
description: 프로젝트 커밋 컨벤션에 맞는 커밋 메시지 자동 생성. git diff 분석 후 Conventional Commits 형식으로 생성합니다. This skill should be used when committing changes or when the user asks to commit.
---

# Git Commit

프로젝트 커밋 컨벤션에 맞는 커밋 메시지를 자동 생성합니다.

## 커밋 타입 표

| 타입 | 설명 | 예시 |
|-----|------|------|
| feat | 새로운 기능 | feat(auth): OAuth2 로그인 플로우 추가 |
| fix | 버그 수정 | fix(parser): null 입력 처리 개선 |
| refactor | 동작 변경 없는 코드 변경 | refactor(api): 에러 핸들러 분리 |
| docs | 문서 변경 | docs: API 레퍼런스 업데이트 |
| test | 테스트 추가/수정 | test(auth): 로그인 단위 테스트 추가 |
| chore | 빌드, 툴링 변경 | chore: 의존성 업그레이드 |
| style | 포맷팅, 공백 (로직 변경 없음) | style: 들여쓰기 수정 |
| perf | 성능 개선 | perf(query): user_id 인덱스 추가 |
| ci | CI 설정 변경 | ci: lint 워크플로우 추가 |
| build | 빌드 시스템 변경 | build: 새 번들러로 마이그레이션 |
| revert | 이전 커밋 되돌리기 | revert: feat(auth) 되돌리기 |

## Subject 규칙

- type(scope)는 영어로, subject는 한글로 작성
- 명령형/선언형 어조 (한글: "추가", "수정", "개선" / 영어: add, fix, improve)
- 마침표 없음
- 50자 이내 권장, 72자 절대 한도
- 간결하되 충분히 설명적

## Body 규칙

- Subject와 본문 사이 빈 줄 필수
- 한글로 작성
- WHY를 설명 (WHAT은 코드가 보여줌)
- 72자마다 줄바꿈

## Footer 규칙

- BREAKING CHANGE: 호환성 깨짐 설명
- Closes #issue-number
- Co-authored-by: Name <email>

## 6단계 커밋 워크플로우

1. 스테이징된 변경 검토 (git diff --cached)
2. 변경 내용에서 타입 결정
3. scope 식별 (해당 시)
4. Subject 작성 (명령형, 간결)
5. 필요 시 Body 작성 (복잡한 변경)
6. 커밋 실행

## 원자적 커밋 원칙

- 하나의 논리적 변경당 하나의 커밋
- 커밋 단위로 독립적으로 이해 가능해야 함

## 안전 사항

- `.env`, `.env.*`, `credentials`, `secrets`, `*.key` 등 민감 정보는 커밋하지 않음
- 경고 패턴 감지 시 사용자에게 확인 요청
