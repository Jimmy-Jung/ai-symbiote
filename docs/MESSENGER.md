# Messenger Bridge

> Telegram, Slack, Discord를 통해 Claude/Codex CLI를 원격으로 사용하는 메신저 브릿지

## 아키텍처

```
Telegram/Slack/Discord
        ↕ (Bot API)
   Node.js 봇 서버 (맥에서 실행)
        ↕ (파일시스템 + spawn)
   Claude CLI / Codex CLI
```

봇 서버가 맥에서 상주하며, 메신저 메시지를 받아 `claude -p` 또는 `codex exec`를 실행하고 결과를 회신합니다.

## 설정

### 1. 봇 서버 설치

```bash
/ai-symbiote:messenger setup
```

대화형 마법사가 플랫폼 선택, 토큰 입력, 봇 서버 다운로드/빌드/시작을 안내합니다.

### 2. config.json

`~/ai-symbiote/{slug}/messenger/config.json`:

```json
{
  "version": "1.0.0",
  "enabled": true,
  "platform": "telegram",
  "telegram": {
    "token": "BOT_TOKEN",
    "chatId": "CHAT_ID",
    "allowedUserIds": ["USER_ID_1", "USER_ID_2"]
  },
  "security": {
    "permissionLevel": "safe"
  },
  "preferences": {
    "notifyOnPhaseChange": true,
    "notifyOnIterationComplete": false,
    "approvalTimeoutSeconds": 1800,
    "language": "ko"
  },
  "projectDir": "/path/to/project",
  "defaultBackend": "claude"
}
```

### 3. 봇 서버 관리

| 명령 | 동작 |
|------|------|
| `/ai-symbiote:messenger start` | 봇 서버 시작 |
| `/ai-symbiote:messenger stop` | 봇 서버 종료 |
| `/ai-symbiote:messenger status` | 봇 서버 상태 확인 |
| `/ai-symbiote:messenger test` | 테스트 알림 전송 |

## 보안

### 사용자 인증

`telegram.allowedUserIds`에 허용할 Telegram 사용자 ID를 등록합니다. 목록에 없는 사용자는 즉시 차단됩니다.

```json
"allowedUserIds": ["8531186223"]
```

- 비어있거나 생략하면 모든 사용자 허용 (개발용)
- Telegram 사용자 ID는 봇에게 메시지를 보낸 후 `getUpdates` API로 확인 가능

### CLI 권한 제한

`security.permissionLevel`로 Claude CLI의 도구 사용을 제한합니다.

| 레벨 | 동작 | 용도 |
|------|------|------|
| `readonly` | 읽기 도구만 허용 (Read, Glob, Grep, WebSearch, WebFetch) | 조회 전용 |
| `safe` (기본) | Bash 도구 차단 | 일반 사용 (삭제/배포 차단) |
| `full` | 제한 없음 | 신뢰 환경 |

커스텀 도구 목록도 가능합니다:

```json
"security": {
  "permissionLevel": "safe",
  "allowedTools": ["Read", "Glob", "Grep", "Edit"],
  "disallowedTools": ["Bash", "Write"]
}
```

## Telegram 명령어

채팅창에서 `/`를 입력하면 자동완성 메뉴가 표시됩니다.

### AI 대화

| 명령 | 설명 |
|------|------|
| 자유 텍스트 | 현재 백엔드(claude/codex)에 질문. 세션이 유지됩니다. |
| `/claude <질문>` | Claude에 질문 (백엔드를 claude로 전환) |
| `/codex <질문>` | Codex에 질문 (백엔드를 codex로 전환) |
| `/new` 또는 `새대화` | 새 대화 시작 (세션 초기화) |
| `/session` 또는 `세션` | 현재 세션 정보 (ID, 메시지 수, 경과 시간) |
| `/help` 또는 `도움말` | 전체 명령어 목록 |

### 세션 관리

| 명령 | 설명 |
|------|------|
| `/sessions` | Claude Code 세션 목록 (최근 10개, 프로젝트명 + 첫 메시지 요약) |
| `/connect <id>` | 기존 Claude Code 세션에 연결. 앞 8자만 입력 가능. |
| `/disconnect` | 세션 연결 해제 |

### 루프 제어

auto-loop/autopilot 실행 중일 때 사용합니다.

| 명령 | 설명 |
|------|------|
| `/status` 또는 `상태` | 현재 루프 상태 (단계, 반복 횟수) |
| `/start <작업>` 또는 `시작 <작업>` | 작업 시작 요청 |
| `/stop` 또는 `중지` | 루프 중지 |
| `/resume` 또는 `재개` | 루프 재개 |
| `/cancel` 또는 `취소` | 루프 취소 |
| `/instruct <지시>` | 다음 반복에 지시 주입 |

루프가 활성일 때 자유 텍스트를 보내면 `/instruct`로 자동 처리됩니다.

## 세션 동작 방식

### Claude 세션 유지

첫 메시지에서 `--output-format json`으로 `session_id`를 캡처하고, 이후 메시지는 `--resume <session_id>`로 같은 세션을 이어갑니다. 맥 터미널의 Claude Code와 동일한 대화 경험입니다.

```
나: 이 프로젝트의 구조를 설명해줘
봇: (프로젝트 분석 후 설명)

나: 그 중에서 shared/ 폴더의 역할은?
봇: (이전 컨텍스트를 기억하고 답변)  ← --resume으로 세션 유지
```

### Claude Code 세션 연동

맥 터미널에서 진행하던 대화를 Telegram에서 이어갈 수 있습니다:

```
1. /sessions → 세션 목록 확인
   dfe9cc2a 4/3 17:27 *integral-ios-ms*
     → 로그인 화면 레이아웃 수정

2. /connect dfe9cc2a → 해당 세션에 연결

3. 질문 입력 → 해당 세션의 컨텍스트로 답변
```

### Codex 세션

Codex CLI는 `--resume`을 지원하지 않아 매번 새 세션으로 실행됩니다. 단발성 작업(코드 리뷰, 분석)에 적합합니다.

### 백엔드 전환

`/claude` 또는 `/codex`로 백엔드를 전환하면, 이후 자유 텍스트도 해당 백엔드로 유지됩니다.

```
/codex 이 코드를 리뷰해줘    → codex 실행
이 부분은 왜 이렇게 했어?     → codex 유지
/claude 대안을 제안해줘       → claude로 전환
더 자세히 설명해줘            → claude 유지
/new                        → 기본값(claude)으로 초기화
```

## 모니터링

### macOS 알림

릴레이 시작/완료/오류 시 macOS 알림 센터에 데스크톱 배너가 표시됩니다.

### 봇 로그

```bash
tail -f ~/ai-symbiote/{slug}/messenger/bot.log
```

출력 예시:

```
[Relay] ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[Relay] 💬 질문: "현재 릴리즈 버전을 알려줘"
[Relay] 🚀 claude 실행 (세션 이어감, #3) [2151d620…]
[Relay] 🔧 claude -p "현재 릴리즈 버전을 알려줘" --disallowedTools Bash --resume 2151d620-... --output-format text
[Relay] 📝 현재 릴리즈 버전은 v0.4.3입니다.
[Relay] ✅ 완료 (8.3s, 45자, 세션 #3)
[Relay] ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### 루프 알림

auto-loop/autopilot 실행 중에는 단계 전환, 에스컬레이션, 완료 등의 알림이 Telegram으로 자동 전송됩니다.

## 3단계 기능

| 단계 | 방향 | 설명 |
|------|------|------|
| Stage 1 | Symbiote → 메신저 | 루프 시작/단계전환/에스컬레이션/완료 알림 |
| Stage 2 | 양방향 | 에스컬레이션 시 승인/거부/수정 요청 및 응답 |
| Stage 3 | 메신저 → Symbiote | AI 대화, 세션 관리, 루프 제어 명령 |

## 파일 구조

```
~/ai-symbiote/{slug}/messenger/
├── config.json        # 봇 설정 (토큰, 인증, 보안)
├── bot.pid            # 봇 서버 PID
├── bot.log            # 봇 서버 로그
├── notifications/     # Stage 1: 알림 파일 (.json → .sent)
├── approvals/         # Stage 2: 승인 요청/응답 파일
└── commands/          # Stage 3: 명령 파일 (instruct, start 등)
```
