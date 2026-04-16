#!/bin/bash
# ai-symbiote Stop hook: Record per-session activity metrics.
# Appends one JSONL line per session to usage-data/sessions.jsonl.
#
# Created by JunyoungJung on 2026-04-16. Copyright © 2026 ai-symbiote.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

# Capture stdin to temp file for byte-for-byte passthrough
STDIN_TMP=$(mktemp "${TMPDIR:-/tmp}/symbiote-stop-stdin.XXXXXX" 2>/dev/null) || STDIN_TMP="${TMPDIR:-/tmp}/symbiote-stop-stdin.$$"
cat > "$STDIN_TMP"

STATE_DIR=$(get_state_dir)
mkdir -p "$STATE_DIR/usage-data"

SESSIONS_FILE="$STATE_DIR/usage-data/sessions.jsonl"

# Collect metrics
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
SESSION_ID="${CLAUDE_SESSION_ID:-${CURSOR_SESSION_ID:-default}}"

# Write 1-line JSON record
printf '{"ts":"%s","session_id":"%s","completed":true}\n' "$TS" "$SESSION_ID" >> "$SESSIONS_FILE"

# Truncation: keep only last 100 lines if exceeds 100
LINES=$(wc -l < "$SESSIONS_FILE" 2>/dev/null | tr -d ' ') || LINES=0
if [ "$LINES" -gt 100 ]; then
  tail -100 "$SESSIONS_FILE" > "$SESSIONS_FILE.tmp" && mv "$SESSIONS_FILE.tmp" "$SESSIONS_FILE"
fi

# Pass stdin through to stdout (byte-for-byte via temp file)
cat "$STDIN_TMP"
rm -f "$STDIN_TMP"

exit 0
