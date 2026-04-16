# Changelog

All notable changes to this project will be documented in this file.

## [0.10.3] - 2026-04-16

### Added
- **3-Tier Lazy Context** — SessionStart 훅의 컨텍스트 주입을 3단계 지연 로딩으로 전환. 세션당 ~1,617 토큰 절감 (74%)
- **Session Intelligence Suite** — 8개 기능 일괄 추가:
  - **PreCompact 훅** — compaction 시 Tier 1 fingerprint 재주입으로 컨텍스트 유실 방지
  - **Strategic Compaction 제안** — Edit/Write 50회 도달 시 `/compact` 제안 (COMPACT_THRESHOLD 설정 가능)
  - **Config Protection** — 린터/포맷터 설정 파일 수정 차단 (SYMBIOTE_ALLOW_CONFIG_EDIT=1로 해제)
  - **GateGuard** — 미읽은 파일 수정 차단으로 "읽지 않고 수정" 실수 원천 방지 (SYMBIOTE_GATEGUARD=0으로 해제)
  - **MCP Health Check** — 3회 연속 실패 MCP 서버 차단, 5분 쿨다운 후 자동 재시도
  - **Cost Tracker** — Stop 훅에서 세션 메트릭 기록 (sessions.jsonl, 100줄 자동 truncation)
  - **Context Budget 스킬** — 토큰 소비 4단계 감사 (Inventory → Classify → Detect → Report)
  - **Instinct 시스템** — 프로젝트별 성공/실패 패턴 학습, confidence 기반 자동 만료/승격
- **Dispatcher 통합** — PreToolUse(Edit|Write) 훅 3개를 단일 dispatcher로 통합하여 hooks.json 비대화 방지
- **Smart Skill Routing** — 자연어 의도 분류 기반 스킬 추천 (Intent Router) + 작업 완료 후 컨텍스트 인지 다음 단계 제안 (Next Action Recommender). 언어 독립적 시맨틱 힌트 기반

### Fixed
- **마켓플레이스 플러그인 설치 실패** — `plugins/`가 `.gitignore`에 포함되어 클론 시 `source` 경로가 존재하지 않는 문제 수정. `plugins/ai-symbiote/` 빌드 산출물을 Git 추적에 포함

## [0.10.2] - 2026-04-15

### Added
- **Setup plan-first 워크플로우** — setup 스킬이 기본적으로 plan 모드에서 시작하여 사용자 승인 전까지 파일 생성/설치를 보류. begin-setup.sh, render-setup-plan.sh, run-store-setup.sh 엔트리포인트 추가
- **Usage tracker UserPromptSubmit 지원** — Claude slash-command(command-message) 이벤트 감지 및 15초 윈도우 내 Read 이벤트 중복 카운팅 방지
- **CLI Store service scanning** — 프로젝트 의존성 파일에서 서비스 패턴(supabase, stripe 등) 자동 감지, auto 모드에서 ready/installable 분류 및 recommendation 상태 파일 기록
- **Skill Store / MCP Store 자동화 스크립트** — 카탈로그 기반 자동 추천, 설치 상태 확인, guided 모드 지원
- **manifest-defaults.sh 테스트** — agentPlatforms 자동 추가, security 기본값, 타입 교정 등 10개 어설션

### Fixed
- **빌드 파이프라인 shared/lib 누락** — service-patterns.json이 번들에 미포함되어 배포 환경에서 스토어 스크립트 실패하는 문제 수정
- **하드코딩 경로 제거** — install.sh의 절대 경로를 $REPO_ROOT 변수로, SKILL.md의 절대 경로를 상대 경로로 교체
- **Store install 실패 핸들링** — cli-store.sh 설치 명령 실패 시 에러 감지 및 install-failed 상태 기록, run-store-setup.sh 실패 시 WARNING 출력

### Changed
- **SERVICE_PATTERNS 통합** — 3개 스토어에 하드코딩되어 불일치했던 감지 패턴을 shared/lib/service-patterns.json으로 추출. 각 스토어는 자기 catalog 키로 필터링
- **catalog.json 가드 추가** — 3개 스토어 스크립트 상단에 catalog 미존재 시 명확한 에러 메시지 출력

## [0.10.1] - 2026-04-15

### Fixed
- **Cursor 플러그인 중복 감지 해결** — `plugins/ai-symbiote/` 빌드 산출물을 Git 추적에서 제거하여 Cursor의 서드파티 플러그인 자동 임포트가 `.claude-plugin`을 중복 로드하는 문제 수정. `version_sync.py` 및 릴리스 규칙에서 해당 경로 제거

## [0.10.0] - 2026-04-15

### Fixed
- **문서 정확성 보정** — README/docs 전체에 Cursor 플랫폼 설치·훅·매처 정보 반영, feedback-logger.sh 누락으로 인한 훅 파일 수(9→10) 보정, "Claude 전용" 오표기를 "Codex 미지원"으로 정정, 메신저 브릿지 문서 현행화

## [0.9.0] - 2026-04-15

### Added
- **하네스 관측/학습 강화 묶음** — build-watcher 훅, feedback-logger, manifest context 주입, harness-rules 요약 모드, MCP Store 스킬과 카탈로그를 포함한 최근 운영 자동화 기능을 마이너 릴리즈로 통합
- **보안 가드레일 확장** — guard-shell의 SEC-001~SEC-016 실시간 차단, `security-guard.sh` 파일 보안 스캔, `security-log.jsonl` 기반 이벤트 추적을 기본 배포 라인에 포함

### Changed
- **문서/오케스트레이션 흐름 정리** — dev-docs 워크플로우 전환, Intent Contract 기반 Synapse 라우팅, ADK 패턴 매핑, 버전 동기화/릴리즈 흐름 문서를 현재 번들 기준으로 정렬

### Fixed
- **운영 안정성 보강** — build/test 실패 분류, 최근 7일 집계, jq 없는 환경 JSON 파싱, 메신저 watcher 신규 파일 감지, setup/harness 경로 기록 이슈를 포함한 0.8.x 안정화 수정 사항을 반영

## [0.8.4] - 2026-04-14

### Added
- **실시간 보안 가드레일** — guard-shell.sh에 16개 보안 패턴(SEC-001~SEC-016) 추가. Secret Exposure(API키 노출, .env 커밋), Dangerous Execution(eval 원격실행, chmod -R 777, docker --privileged), Data Exfiltration(민감파일 아카이브, netcat 전송) 3개 카테고리로 분류하여 차단
- **security-guard.sh 훅** — PostToolUse Write/Edit에서 파일 내용을 스캔하여 하드코딩 시크릿, SQL injection, XSS, 디버그 모드 활성화를 경고 (Claude 전용). 100KB 초과/바이너리 자동 스킵, 확장자 화이트리스트 적용
- **보안 시드 규칙** — security.md에 6개 보안 시드 규칙 추가. setup 시 프로젝트 harness-rules에 자동 주입
- **security-log.jsonl** — 보안 이벤트 전용 로그. 최대 10,000줄 자동 rotation, harness-log.jsonl에도 통합 기록

### Changed
- **위험도 낮은 패턴 경고로 완화** — git clean -fd, chmod 777(단일파일), npm --no-audit, env dump를 차단에서 경고(continue=true)로 변경. 캐시 정리, CI 플래그 등 일상적 작업을 허용하면서 인지는 유지

## [0.8.3] - 2026-04-14

### Added
- **manifest context 주입** — SessionStart 훅에서 `manifest.json`의 project/stack 정보를 `[Symbiote Manifest]` 태그로 context에 자동 주입하여 매 세션마다 프로젝트 탐색 없이 즉시 맥락 파악 가능

## [0.8.2] - 2026-04-13

### Added
- **build-watcher 훅** — Claude와 Codex의 Bash PostToolUse에서 build/test 실패를 공통 감지하고 `harness-log.jsonl`에 반복 패턴 학습용 이벤트 기록
- **feedback-logger 유틸리티** — 사용자가 변경을 반려했을 때 반복 피드백을 기록하고 동일 패턴이 누적되면 Harness 규칙으로 승격

### Changed
- **Codex 훅 문서 및 배선 갱신** — Codex의 Bash PostToolUse 지원 범위를 README, ARCHITECTURE, DEPENDENCIES와 훅 설정에 반영
- **하네스 로그 스키마 확장** — `build_build_failed`, `build_test_failed`, `user_feedback`, `error_category`, `error_summary`를 문서화

### Fixed
- **build/test 실패 분류 정밀화** — `** TEST FAILED **`, `npm test`의 `FAIL ...test.ts`, 구조화된 `exit_code` 실패를 `test_failed`로 올바르게 분류
- **최근 7일 집계 정확도 개선** — 문자열 grep 대신 ISO-8601 cutoff 기반 필터를 사용해 1~6일 전 실패도 누락 없이 집계
- **jq 없는 환경 JSON 파싱 보강** — 공통 유틸이 `python3` fallback을 사용해 escaped quote와 scalar 값을 안정적으로 읽도록 수정
- **편집 실패 카테고리 분리** — `not_unique`, `not_found`, `no_such_file`, `permission_denied`, `no_change`를 개별 error type으로 학습하도록 개선

## [0.8.1] - 2026-04-12

### Changed
- **dev-docs 스킬 워크플로우 전환** — generate-dev-docs.sh heredoc 기반에서 SKILL.md 워크플로우 기반 동적 문서 생성으로 전환. Claude가 실제 소스(스킬 frontmatter, 훅 매핑, Intent Contract 등)를 읽고 맥락 있는 설명을 생성
- **23개 섹션 매핑** — Deep Scan/Model/Render 3단계 파이프라인에 전체 섹션별 소스-다이어그램 매핑 테이블 명시
- **Workflow Ownership** — SKILL.md가 primary, generate-dev-docs.sh는 baseline fallback으로 소유권 경계 명시

### Fixed
- **테스트 동적 카운트** — test-dev-docs-skill.sh의 하드코딩된 "27개" assertion을 동적 카운트로 전환

### Added
- **test-dev-docs-quality.sh** — 마커 블록 내 최소 줄 수 검증 테스트 (워크플로우 실행 후 품질 게이트)

## [0.8.0] - 2026-04-12

### Changed
- **Synapse Intent-Based Routing** — 키워드 기반 라우팅을 Intent Contract 기반 의도 라우팅으로 전환
- **ADK 패턴 매핑** — 6개 팀 템플릿에 ADK 실행 패턴 명시적 매핑

## [0.7.1] - 2026-04-12

### Fixed
- **SKILL front matter YAML 파싱 오류** — `roles`, `team-templates` 스킬의 `description` 값을 인용 처리해 콜론 포함 문자열이 로컬 플러그인 로딩 중 YAML 에러를 내지 않도록 수정

## [0.7.0] - 2026-04-12

### Added
- **harness-rules 요약 모드** — 규칙 50줄 초과 시 prevented count 기반 정렬 후 상위 50줄만 컨텍스트에 주입하여 토큰 절감
- **테스트** — setup-check 요약 모드 테스트 10개 (`tests/test-setup-check-summary.sh`)

### Changed
- **스킬 병합 (30→26)** — `tm-board`+`tm-init`+`tm-parse-prd`→`taskmaster`, `planning`→`plan`에 흡수, `auto-loop`+`autopilot`→`auto`
- 14개 파일의 크로스 레퍼런스 업데이트 (synapse, team-templates, roles, setup, verify-loop, messenger, harness-learn, setup-check, session-control)
- TODOS.md에 스킬 병합 폭발 반경 분석 기록

## [0.6.3] - 2026-04-12

### Added
- **MCP Store 스킬** — 프로젝트 스택 기반 MCP 서버 자동 추천/설치 (`shared/skills/mcp-store/`)
- **MCP Store 카탈로그** — 156개 MCP 서버 메타데이터 및 카탈로그 검증 테스트
- **ADK 패턴 문서** — Google Agent Development Kit 주요 패턴 설명
- **harness 통합 테스트** — harness-learn 훅 및 mcp-store 카탈로그 검증 테스트 스위트
- **setup에 mcpServers 스키마** — manifest.json에 MCP 서버 설정 스키마 추가

### Fixed
- **harness-learn 규칙 중복 생성 방지** — 동일 패턴 규칙이 반복 생성되지 않도록 개선, harness-rules.md 분리

### Changed
- 스킬 문서를 harness-rules.md 기반으로 업데이트 (evolve, gc, setup)

## [0.6.2] - 2026-04-08

### Fixed
- **messenger watcher 신규 파일 감지 안정화** — `usePolling` 기반 감시, 초기 스캔 후 재스캔, 주기적 pending scan, 처리 타임아웃을 추가해 Telegram 브릿지에서 `notifications/` 신규 JSON 파일이 누락되거나 처리 중 고착되는 문제를 수정

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
