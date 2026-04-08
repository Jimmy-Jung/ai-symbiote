# Changelog

All notable changes to this project will be documented in this file.

## [0.6.1] - 2026-04-08

### Fixed
- **harness-learn 세션 디렉터리 경로** — `$STATE_DIR/session-$PPID` → `$STATE_DIR/state/session-$PPID`로 수정, 세션 이벤트가 올바른 위치에 기록되도록 보장

### Added
- **빌드 스크립트에 harness-seeds 포함** — `shared/harness-seeds/`가 plugins/ 및 dist/에 복사되어 배포 환경에서 시드 규칙 로딩 동작

### Changed
- 빌드 재실행으로 plugins/ 전체 동기화 (lint 스킬, 훅 개선, 스킬 문서 갱신 반영)

## [0.6.0] - 2026-04-08

### Added
- **contribute 스킬** — GitHub 이슈 자동 등록 워크플로우
- **gc (garbage collection) 스킬** — 상태 폴더 정리 자동화
- **harness-learn 훅** — 에이전트 실수 감지 후 자동 규칙 생성, auto-loop FAIL 연동 및 확장자 패턴 학습
- **피드백 루프 + 자기진화** — 하네스 3개 기둥(Context, Hooks, Feedback) 전체에 걸친 자기학습 사이클 완성
- **harness-seeds** — 기술 스택별 시드 규칙이 초기 부트스트랩 시 로딩되어 알려진 에이전트 실수를 첫 세션부터 방지
- **AI 시대 스타트업 전략 문서** — 수직 AI, 자동화 전략 및 하네스 엔지니어링 가이드

### Changed
- 전체 25개 스킬을 영문으로 국제화 (i18n)
- guard-shell 훅에 안전한 우회 경로 제시 및 harness-log 기록 추가
- README 및 ARCHITECTURE 문서 전면 개편 — hooks 매핑표, 디렉터리 구조, 빌드 흐름 갱신
- tasks 디렉터리를 .gitignore에 추가

## [0.5.5] - 2026-03-25

### Changed
- setup 기본 모델을 gpt-5.4로 변경

## [0.5.4] - 2026-03-20

### Added
- Initial tagged release
