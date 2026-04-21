# Changelog

All notable changes to this project will be documented in this file.

## [0.11.0] - 2026-04-21

### Added
- **Write-time Verification Layer** — AI가 작성한 코드가 "왜" 그렇게 쓰였는지를 사람이 재구성할 수 없는 opacity 문제를 행동적으로 측정·제거하는 신규 파이프라인. `/verify` 스킬이 큐잉된 편집 각각에 대해 cold-read reviewer(Codex) + LLM judge를 돌려 검증 아티팩트(`.ai-symbiote/qa/<project>/<date>/<sha>.md`)를 생성. 코드 자체가 아니라 Q&A 트랜스크립트가 1급 리뷰 대상이 됨
- **PostToolUse(Write|Edit) 훅 `verify-queue.sh`** — 편집 메타데이터를 `~/.ai-symbiote/state/verify-queue.jsonl`에 <100ms로 append. `hooks.json`의 `timeout: 10s` 제약 안에서 Judge 호출(~30s)을 분리하는 Option D 아키텍처
- **SessionStart `[Verify] N pending verification(s)` 알림** — `setup-check.sh`가 현재 레포의 pending 건수를 감지해 세션 시작 시 노출. `/verify` 누락 방지
- **3-role reviewer 프롬프트** — Intent / Structural / Alternative 관점을 통합해 reviewer에게 전달. 단일 프롬프트로 멀티-에이전트 대체
- **V2c 랜덤 질문 subset (필수)** — Reviewer pool N=5~8에서 저자는 K=3만 무작위로 답변. 예상 질문 전체에 답변을 미리 준비하는 seeding 공격 차단. `--all-questions` 디버그 플래그만 bypass 허용
- **Pre-flight 기계검증 (Step 2.5)** — `/verify` 실행 시 프로젝트 네이티브 typecheck/lint/test를 먼저 돌려 결과를 reviewer 프롬프트에 주입. unused import·type drift·실패 test를 reviewer 질문으로 직접 전환
- **배치 캡 (`--max-batch`, 기본 10)** — pending이 10건 초과일 때 첫 10건만 처리하고 나머지는 큐 유지. Codex judge 비용 폭주 차단
- **Queue schema v2** — `repo_root` 절대경로 + `base_sha`(편집 직전 HEAD) 필드 추가. `~/work/app`과 `~/tmp/app` 같은 동명 레포 충돌, 편집 후 HEAD 이동 시 잘못된 diff 참조 차단. 레거시 `sha` 필드는 v1 호환용 mirror 유지 (v0.12에서 제거 예정)
- **`docs/02-아키텍처.md` Write-time Verification Layer 섹션** — Option D 데이터 흐름, validator 계층(V1a~d, V2a~c), 플랫폼 지원 매트릭스, artifact 영속성 정책, queue schema v2 표 문서화
- **`docs/09-검증-레이어-동작원리.md` (신규, 359줄)** — 12개 mermaid 다이어그램으로 동작원리를 초보자 친화적으로 설명. AlphaGo 비유, 공격 시나리오, FAQ 포함
- **테스트 인프라** — `tests/test-verify-queue.sh` 44 케이스 + `tests/test-setup-check-verify.sh` 20 케이스 총 64. JSON escaping, trigger lowercase, non-git fallback, orphan edit 격리, symlink 거부, newline 경로 보존, 멀티레포 분리, v1/v2 혼재, jq 부재 시 grep fallback, zero-match 산술 회귀 모두 커버

### Changed
- **Skill 8개 한글 prose → 영어** (`verify`, `synapse`, `setup`, `auto`, `plan`, `review`, `team-templates`, `roles`). SKILL.md 파일은 LLM 컨텍스트에 매번 로드되므로 한글 본문은 영어 대비 2-3배 더 많이 tokenize됨. 실제 파일명·한국어 트리거 키워드 예시·validator 키워드 패턴은 의미상 필요해 유지
- **Codex 플랫폼 지원** — Write|Edit PostToolUse 훅 부재로 자동 큐잉 불가. `/verify --sha <sha>` / `--file <path>` 수동 호출만 지원. `build-codex.sh`가 `shared/skills/verify/SKILL.md`를 `dist/codex-symbiote/`에 자동 복사하므로 스킬 자체는 노출됨
- **`/verify` Fallback Mode 재기술** — Codex CLI 부재 시 reviewer/judge를 **별도 Claude subagent**로 띄우고, 단일 세션 collusion을 명시적으로 금지. `allowed-tools`에 `Agent` 추가 (이전에는 누락되어 fallback이 차단됨)

### Fixed
- **diff 수집 계약 버그 (Codex Finding 1, High)** — 저장된 `sha`는 편집 전 HEAD인데 `git show <sha>`로 읽어 이전 커밋 diff를 reviewer에게 노출시키던 논리 오류. `base_sha` 필드로 분리 후 `HEAD==base_sha`/`HEAD!=base_sha` 분기로 재작성. 커밋 후 추가 편집이 누락되지 않도록 `git diff HEAD` + `--cached`까지 병합
- **Fallback mode 실행 차단 (Codex Finding 2, Medium)** — `allowed-tools`에 `Agent` 누락으로 Codex 부재 시 Claude subagent fallback이 실행되지 않던 문제 해결
- **동명 레포 queue 충돌 (Codex Finding 3)** — 레포 basename만으로 필터링해 교차 오염되던 문제. `repo_root` 절대경로를 1차 필터로, `project + branch`는 v1 legacy fallback으로 사용
- **setup-check 산술 silently 0 반환 (Claude adversarial, Critical)** — `grep -c ... || echo 0`가 grep의 `0` 출력 + fallback `0`을 모두 캡처해 `0\n0`을 arithmetic context에 넣어 `$((...))` 실패. `tr -dc '0-9'` + 기본값으로 정규화해 notification이 무음 억제되는 steady-state 버그 해소
- **크로스 프로젝트 오염 (Cross-confirmed High)** — 레포 외부 편집 시 hook의 cwd 레포로 fallback해 잘못된 프로젝트에 집계되던 문제. `repo_root=""` + `project="unknown"` placeholder로 대체
- **`json_escape` newline/CR silent corruption (Claude High)** — `tr '\n' ' '`이 `a\nb.ts` 같은 POSIX-legal 경로를 `a b.ts`로 변환. python3 기반 full-JSON escape로 교체, sed 폴백에서도 `\\, \", \t, \n, \r` 모두 처리
- **`source ~/.claude/skills/...` 샌드박스 우회 (Codex High #1)** — `/verify`가 read-only 샌드박스 전에 홈 디렉터리 임의 코드에 제어권을 넘기던 패턴 제거. Prompt는 temp file로 전달해 argv 주입도 차단
- **Symlink write amplifier (Claude Medium)** — QUEUE_DIR/QUEUE_FILE이 symlink이면 편집마다 타 경로에 누적 기록될 위험. `[ -L ... ]` 체크 후 silent exit로 차단
- **pool<3 무언 우회 (Codex Medium #5)** — 질문 풀이 3개 미만일 때 `/verify`가 "trivial"로 판정해 Step 7 스킵하던 경로를 `reviewer_underrun` FAIL로 변경. reviewer 파싱 실패/guardrail 트립이 검증 우회가 되지 않도록

### Deferred (v0.12+ 설계 검토)
- **Queue concurrent write race (flock)** — 병렬 편집 시 atomic append가 PIPE_BUF에 의존. flock 도입은 macOS 기본 미포함 등 플랫폼 호환성 검토 필요
- **Queue rotation / TTL** — `gc` 스킬 확장으로 30일 이상 된 pending entry 정리 예정
- **Cursor 플랫폼 통합** — hooks 이벤트 규약(lower camelCase)과 matcher(`Shell`, `Read`, `Write`)가 Claude와 상이해 별도 설계 필요

## [0.10.9] - 2026-04-20

### Added
- **setup: AI 주도 2단계 guided 흐름 + `recommend` 모드** — 비대화형 AI agent Bash 도구에서 stdin TTY 부재로 guided 선택이 전부 `later`로 떨어지던 문제 해결. `--mode recommend`로 추천만 수집 후, `SETUP_STORE_{SKILLS,CLI,MCP}_CHOICE` 환경변수로 선택값을 전달해 `--mode guided` 실행 시 `read`를 건너뛰도록 정비
- **store 계열 auto 매칭에 플랫폼/별칭 지원** — `project.platforms`(ios, ipados, android, …), `project.type`, `stack.buildTool`을 lookup 키로 추가하고 `shared/lib/stack-aliases.json`으로 `ios/ipados/swiftui/uikit → swift`, `android/jetpack/compose/kmp → android|kotlin` 등을 정규화
- **iOS/Swift 프로젝트 감지 및 추천 보강** — `*.xcodeproj/project.pbxproj`, `Podfile`, `Project.swift`를 서비스 스캔 후보에 추가. cli-store에 `swiftlint`, `swiftformat`, `xcbeautify`, `fastlane`, `tuist`, `xcodegen`, `cocoapods`, `simctl` 엔트리 추가. mcp-store `stacks.swift`에 Apple 문서 조회용 `context7` 추가
- **Android/Kotlin 스택 커버리지 신설** — 세 catalog에 `stacks.android`/`stacks.kotlin` 추가. cli-store에 `adb`, `emulator`, `gradle`, `ktlint`, `detekt`, `fastlane`, `bundletool`, `kotlinc` 제공. mcp-store에 `context7` + `github` 제공. `Podfile`·`Project.swift`·`build.gradle(.kts)`·`AndroidManifest.xml`·`libs.versions.toml`을 `candidateFiles`에 포함, service-patterns에 Firebase/Sentry/RevenueCat/Amplitude/Mixpanel/OneSignal iOS·Android 좌표 보강
- **skill-store 추천 스킬 대규모 보강** — iOS/Swift: `dpearson2699/swift-ios-skills`, `CharlesWiltgen/Axiom`, `twostraws/swift-agent-skills`, `twostraws/swiftui-agent-skill`, `AvdLee/SwiftUI-Agent-Skill`, `AvdLee/Swift-Concurrency-Agent-Skill`, `vabole/apple-skills`, `kylehughes/apple-platform-build-tools-claude-code-plugin`, `conorluddy/ios-simulator-skill`. Android: `android/skills`, `Drjacky/claude-android-ninja`, `dpconde/claude-android-skill`, `aldefy/compose-skill`, `new-silvermoon/awesome-android-agent-skills`. Kotlin: `Kotlin/kotlin-agent-skills`(공식), `kbrgnj/kotlin-backend-agent-skills`

### Changed
- **skill-store: awesome-agent-skills 외부 카탈로그 의존성 제거** — `_source`(VoltAgent/awesome-agent-skills) 필드를 들어내고 카탈로그를 "큐레이트된 시드 + 누락 시 WebSearch/GitHub 검색"으로 재정의. SKILL.md를 3-tier(local → awesome-agent-skills README → GitHub)에서 2-tier(local → WebSearch/GitHub)로 단순화하고 `allowed-tools`에 `WebFetch`/`WebSearch` 추가
- **README 설치 섹션 개선** — 프롬프트로 자동 설치할 수 있도록 Claude Code/Codex CLI/Cursor용 프롬프트 블록 추가, 하드코딩된 `/Users/jimmy` 절대 경로를 `~/ai-symbiote` 홈 디렉터리 예시로 일반화

## [0.10.8] - 2026-04-17

### Added
- **Codex용 PRD/Ralph 워크플로 추가** — `prd` 스킬로 기능 PRD를 작성하고 `ralph` 스킬과 `ralph-loop.sh`로 `prd.json` 변환 및 Codex 기반 자율 반복 실행을 준비할 수 있도록 확장

### Fixed
- **Ralph 아카이브 정합성 수정** — 브랜치 전환 시 이전 실행의 `prd.json`, `ralph-state.md`, `progress.txt`가 새 브랜치 내용으로 덮여 저장되던 문제를 이전 스냅샷 기준으로 보존하도록 수정
- **Ralph prepare-only 실행성 수정** — `--prepare-only`가 런타임 툴 설치 여부와 무관하게 상태 파일과 작업 디렉터리를 준비할 수 있도록 실행 순서 조정
- **setup/README 문서 정합성 보정** — Codex에서 Ralph를 외부 플러그인처럼 설치한다는 안내를 내장 워크플로 기준으로 바로잡고 스킬/테스트 개수 표기를 현재 구현과 일치시킴

## [0.10.7] - 2026-04-17

### Fixed
- **security 스킬 frontmatter YAML 파싱 오류 수정** — `argument-hint`를 배열처럼 보이는 비인용 값에서 문자열로 변경해 Codex 스킬 로더가 `invalid YAML` 경고 없이 `SKILL.md`를 정상 해석하도록 수정

## [0.10.6] - 2026-04-17

### Fixed
- **Issue #7 해결: GateGuard가 방금 쓴 파일의 후속 수정까지 막던 문제 수정** — 성공한 `Write|Edit` 대상을 PostToolUse에서 자동 등록하도록 바꿔 같은 세션의 정상적인 연속 수정 흐름을 허용
- **Issue #8 해결: usage tracker가 command-message 외 입력 형태를 놓치던 문제 수정** — `command-name`, bare slash command, 추가 skill 필드를 함께 인식하도록 확장해 `usage-data/{skills,commands}`가 실제 사용량을 반영
- **Issue #9 해결: Claude PreToolUse 차단이 continuation 자체를 끊던 문제 수정** — deny 응답을 Claude 공식 `permissionDecision` 포맷으로 전환하고 compact 제안을 PostToolUse로 이동해 연속 작업이 끊기지 않도록 정리
- **문서 정합성 보정** — Cursor 훅 배선이 현재 `Write` 중심이라는 점을 README와 주요 기능 문서에 명시해 플랫폼별 동작 범위를 실제 구현과 맞춤

## [0.10.5] - 2026-04-17

### Fixed
- **Issue #6 해결: setup dry-run이 manifest를 변형하던 문제 수정** — 실제 state는 건드리지 않으면서 임시 state에서 recommendation/summary를 정상 계산하도록 조정해 dry-run 출력 왜곡과 상태 오염을 함께 해소
- **Issue #6 해결: store manifest detail key 유실 수정** — CLI Skill MCP store가 기존 manifest 엔트리를 덮어쓰지 않고 병합하도록 바꿔 사용자 정의 detail 필드가 유지되도록 수정
- **Issue #5 해결: security scan 대형 Tuist iOS 프로젝트 지연 완화** — timeout heartbeat exclude 흐름을 정리하고 world-writable 검사까지 `Pods`, `DerivedData`, `Tuist`, `.build`, `*.xcframework` 제외 규칙을 일관되게 적용
- **이슈 회귀 테스트 추가** — dry-run immutability, summary 정확도, scanner timeout heartbeat exclude 경로를 테스트로 고정

## [0.10.4] - 2026-04-17

### Fixed
- **훅 stdin timeout 가드 (freeze 방지)** — harness가 stdin을 닫지 않을 때 `$(cat)`이 무한 대기하여 Claude Code가 간헐적으로 멈추는 문제 해결. 18개 훅 전체를 새 헬퍼 `read_stdin_safe`로 교체하여 2초 내 종료 보장 (timeout → gtimeout → perl → cat 순 fallback)
- **`next-action.sh` 잠재적 query injection 제거** — `$LAST_SKILL`을 jq `--arg`와 python3 환경변수로 전달하도록 변경. 파일명에 특수문자가 포함되어도 안전
- **`next-action.sh` stdin passthrough 단순화** — temp 파일 의존성 제거, 변수 기반으로 전환하여 I/O 실패 경로 자체를 제거
- **Intent Router 정보 손실 수정** — compact hints가 `signals[0]`만 사용하던 것을 전체 `signals`를 `;`로 합쳐 주입하도록 변경. python3 fallback의 `$HINTS_FILE` 보간도 환경변수 전달로 전환
- **`skill-chains.json` 죽은 키 정리** — 사용되지 않는 `new_files_added`, `tests_modified`, `no_changes` 제거. `feature_branch_with_commits`는 스크립트가 JSON에서 읽도록 일관성 확보

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
