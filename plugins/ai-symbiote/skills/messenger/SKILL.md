---
name: messenger
description: "Messenger bridge setup and management. Integrates with Slack, Discord, Telegram to monitor and control auto-loop/autopilot sessions while away. Triggers on: messenger, notification setup."
argument-hint: <setup|start|stop|status|test>
user-invocable: true
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep]
---

# Messenger Bridge

Remotely monitor and control auto-loop/autopilot sessions via messenger.

State files are stored in `~/ai-symbiote/{slug}/messenger/`. Claude and Codex can share this directory based on the same project slug.

## Subcommands

### `messenger setup`

Runs the interactive setup wizard.

1. **Platform selection**: Choose from Slack / Discord / Telegram
2. **Token input**: Configure bot token per platform
   - **Telegram**: Bot token from BotFather + chat ID
   - **Slack**: Bot Token (xoxb-), App Token (xapp-), Signing Secret, Channel ID
   - **Discord**: Bot Token, Channel ID
3. **Create config.json**: Save to `~/ai-symbiote/{slug}/messenger/config.json`
4. **Download and install bot server**:
   ```bash
   BRIDGE_DIR="$HOME/ai-symbiote/messenger-bridge"
   if [ ! -d "$BRIDGE_DIR" ]; then
     git clone https://github.com/Jimmy-Jung/ai-symbiote "$BRIDGE_DIR/repo"
     if [ -d "$BRIDGE_DIR/repo/shared/messenger-bridge" ]; then
       cd "$BRIDGE_DIR/repo/shared/messenger-bridge" && npm install && npm run build
     fi
   fi
   ```
5. **Start bot server**:
   ```bash
   BRIDGE_JS="$HOME/ai-symbiote/messenger-bridge/repo/shared/messenger-bridge/dist/index.js"
   STATE_DIR="$HOME/ai-symbiote/{slug}"
   nohup node "$BRIDGE_JS" --state-dir "$STATE_DIR" > "$STATE_DIR/messenger/bot.log" 2>&1 &
   echo $! > "$STATE_DIR/messenger/bot.pid"
   ```
6. **Send test notification**: Write test file to `messenger/notifications/`

### `messenger start`

Starts the bot server.

```bash
BRIDGE_JS="$HOME/ai-symbiote/messenger-bridge/repo/shared/messenger-bridge/dist/index.js"
STATE_DIR="$HOME/ai-symbiote/{slug}"
nohup node "$BRIDGE_JS" --state-dir "$STATE_DIR" > "$STATE_DIR/messenger/bot.log" 2>&1 &
echo $! > "$STATE_DIR/messenger/bot.pid"
```

### `messenger stop`

Stops the bot server.

```bash
STATE_DIR=$(get_state_dir result)
PID=$(cat "$STATE_DIR/messenger/bot.pid" 2>/dev/null)
if [ -n "$PID" ]; then
  kill "$PID" 2>/dev/null
  rm -f "$STATE_DIR/messenger/bot.pid"
fi
```

### `messenger status`

Checks bot server status:
- PID file existence and process running status
- Platform connection status
- Recent notification files (last 5 in notifications/)
- Pending approval requests (requests without response in approvals/)
- Pending commands (pending in commands/)

### `messenger test`

Sends a test notification:

```bash
STATE_DIR=$(get_state_dir result)
NOTIFY_DIR="$STATE_DIR/messenger/notifications"
mkdir -p "$NOTIFY_DIR"
TS=$(date -u +"%Y-%m-%dT%H-%M-%S")
cat > "$NOTIFY_DIR/${TS}_test.json" <<'EOF'
{
  "event": "test",
  "timestamp": "current_time",
  "taskFolder": "test",
  "data": {
    "summary": "Messenger bridge test notification."
  }
}
EOF
```

## Config File Format

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

## Architecture Overview

```text
AI Symbiote (hooks/skills) <-> Filesystem <-> Node.js Bot Server <-> Messenger API
                                     |
                    ~/ai-symbiote/{slug}/messenger/
                    ├── config.json
                    ├── notifications/
                    ├── approvals/
                    ├── commands/
                    ├── bot.pid
                    └── bot.log
```

### 3-Stage Capabilities

| Stage | Direction | Description |
|-------|-----------|-------------|
| Stage 1 | Symbiote -> Messenger | Loop start/phase transition/escalation/completion notifications |
| Stage 2 | Bidirectional | Approval/rejection/modification requests and responses on escalation |
| Stage 3 | Messenger -> Symbiote | Start/stop/resume/cancel/status/instruction commands |
