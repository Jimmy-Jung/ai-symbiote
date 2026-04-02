---
name: messenger
description: "메신저 브릿지 설정 및 관리. Slack, Discord, Telegram 연동으로 자리를 비운 동안에도 auto-loop/autopilot 세션을 모니터링하고 제어합니다. Triggers on: 메신저, messenger, 알림 설정, notification setup."
argument-hint: <setup|start|stop|status|test>
user-invocable: true
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep]
---

# Messenger Bridge — 메신저 브릿지 관리

메신저를 통해 auto-loop/autopilot 세션을 원격 모니터링하고 제어합니다.

상태 파일은 `~/ai-symbiote/{slug}/messenger/`에 저장됩니다. Claude와 Codex는 같은 프로젝트 슬러그를 기준으로 이 디렉터리를 공유할 수 있습니다.

## 서브 커맨드

### `messenger setup`

대화형 설정 마법사를 실행합니다.

1. **플랫폼 선택**: Slack / Discord / Telegram 중 선택
2. **토큰 입력**: 플랫폼별 봇 토큰 설정
   - **Telegram**: BotFather에서 생성한 봇 토큰 + 채팅 ID
   - **Slack**: Bot Token (xoxb-), App Token (xapp-), Signing Secret, Channel ID
   - **Discord**: Bot Token, Channel ID
3. **config.json 생성**: `~/ai-symbiote/{slug}/messenger/config.json`에 저장
4. **봇 서버 다운로드 및 설치**:
   ```bash
   BRIDGE_DIR="$HOME/ai-symbiote/messenger-bridge"
   if [ ! -d "$BRIDGE_DIR" ]; then
     git clone https://github.com/Jimmy-Jung/ai-symbiote "$BRIDGE_DIR/repo"
     if [ -d "$BRIDGE_DIR/repo/shared/messenger-bridge" ]; then
       cd "$BRIDGE_DIR/repo/shared/messenger-bridge" && npm install && npm run build
     fi
   fi
   ```
5. **봇 서버 시작**:
   ```bash
   BRIDGE_JS="$HOME/ai-symbiote/messenger-bridge/repo/shared/messenger-bridge/dist/index.js"
   STATE_DIR="$HOME/ai-symbiote/{slug}"
   nohup node "$BRIDGE_JS" --state-dir "$STATE_DIR" > "$STATE_DIR/messenger/bot.log" 2>&1 &
   echo $! > "$STATE_DIR/messenger/bot.pid"
   ```
6. **테스트 알림 전송**: `messenger/notifications/`에 테스트 파일 작성

### `messenger start`

봇 서버를 시작합니다.

```bash
BRIDGE_JS="$HOME/ai-symbiote/messenger-bridge/repo/shared/messenger-bridge/dist/index.js"
STATE_DIR="$HOME/ai-symbiote/{slug}"
nohup node "$BRIDGE_JS" --state-dir "$STATE_DIR" > "$STATE_DIR/messenger/bot.log" 2>&1 &
echo $! > "$STATE_DIR/messenger/bot.pid"
```

### `messenger stop`

봇 서버를 종료합니다.

```bash
STATE_DIR=$(get_state_dir 결과)
PID=$(cat "$STATE_DIR/messenger/bot.pid" 2>/dev/null)
if [ -n "$PID" ]; then
  kill "$PID" 2>/dev/null
  rm -f "$STATE_DIR/messenger/bot.pid"
fi
```

### `messenger status`

봇 서버 상태를 확인합니다:
- PID 파일 존재 및 프로세스 실행 여부
- 플랫폼 연결 상태
- 최근 알림 파일 (notifications/ 내 최근 5개)
- 대기 중인 승인 요청 (approvals/ 내 request without response)
- 대기 중인 명령 (commands/ 내 pending)

### `messenger test`

테스트 알림을 전송합니다:

```bash
STATE_DIR=$(get_state_dir 결과)
NOTIFY_DIR="$STATE_DIR/messenger/notifications"
mkdir -p "$NOTIFY_DIR"
TS=$(date -u +"%Y-%m-%dT%H-%M-%S")
cat > "$NOTIFY_DIR/${TS}_test.json" <<'EOF'
{
  "event": "test",
  "timestamp": "현재시각",
  "taskFolder": "test",
  "data": {
    "summary": "메신저 브릿지 테스트 알림입니다."
  }
}
EOF
```

## 설정 파일 형식

`~/ai-symbiote/{slug}/messenger/config.json`:

```json
{
  "version": "1.0.0",
  "enabled": true,
  "platform": "telegram",
  "telegram": {
    "token": "BOT_TOKEN",
    "chatId": "CHAT_ID"
  },
  "preferences": {
    "notifyOnPhaseChange": true,
    "notifyOnIterationComplete": false,
    "approvalTimeoutSeconds": 1800,
    "language": "ko"
  }
}
```

## 아키텍처 개요

```text
AI Symbiote (hooks/skills) ←→ 파일시스템 ←→ Node.js 봇 서버 ←→ 메신저 API
                                     │
                    ~/ai-symbiote/{slug}/messenger/
                    ├── config.json
                    ├── notifications/
                    ├── approvals/
                    ├── commands/
                    ├── bot.pid
                    └── bot.log
```

### 3단계 기능

| 단계 | 방향 | 설명 |
|------|------|------|
| Stage 1 | Symbiote → 메신저 | 루프 시작/단계전환/에스컬레이션/완료 알림 |
| Stage 2 | 양방향 | 에스컬레이션 시 승인/거부/수정 요청 및 응답 |
| Stage 3 | 메신저 → Symbiote | 시작/중지/재개/취소/상태/지시 명령 |
