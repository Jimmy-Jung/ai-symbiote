#!/bin/bash
# ai-symbiote Stop hook: Record session observations for instinct pattern extraction.
#
# Created by JunyoungJung on 2026-04-16. Copyright © 2026 ai-symbiote.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

# Capture stdin to temp file for byte-for-byte passthrough
STDIN_TMP=$(mktemp "${TMPDIR:-/tmp}/symbiote-instinct-stdin.XXXXXX" 2>/dev/null) || STDIN_TMP="${TMPDIR:-/tmp}/symbiote-instinct-stdin.$$"
cat > "$STDIN_TMP"

STATE_DIR=$(get_state_dir)
mkdir -p "$STATE_DIR/instincts"

# Generate project ID from git remote URL hash
PROJECT_ID=""
if command -v git >/dev/null 2>&1; then
  REMOTE_URL=$(git remote get-url origin 2>/dev/null)
  if [ -n "$REMOTE_URL" ]; then
    if command -v shasum >/dev/null 2>&1; then
      PROJECT_ID=$(printf '%s' "$REMOTE_URL" | shasum -a 256 | cut -c1-12)
    elif command -v sha256sum >/dev/null 2>&1; then
      PROJECT_ID=$(printf '%s' "$REMOTE_URL" | sha256sum | cut -c1-12)
    fi
  fi
fi
# Fallback: lowercase directory basename, keep alphanumeric + dash
[ -z "$PROJECT_ID" ] && PROJECT_ID=$(basename "$(pwd)" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-' | head -c 12)
[ -z "$PROJECT_ID" ] && PROJECT_ID="unknown"

# Save project ID
echo "$PROJECT_ID" > "$STATE_DIR/instincts/project-id.txt"

# Append observation to observations.jsonl
SESSION_ID="${CLAUDE_SESSION_ID:-${CURSOR_SESSION_ID:-${CODEX_SESSION_ID:-default}}}"
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
printf '{"ts":"%s","session_id":"%s","project_id":"%s","type":"observation"}\n' "$TS" "$SESSION_ID" "$PROJECT_ID" >> "$STATE_DIR/instincts/observations.jsonl"

# Pass stdin through to stdout (byte-for-byte via temp file)
cat "$STDIN_TMP"
rm -f "$STDIN_TMP"

exit 0
