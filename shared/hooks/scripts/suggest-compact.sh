#!/bin/bash
# ai-symbiote PreToolUse hook: Suggest manual compaction at logical intervals.
# Counts Edit/Write tool calls per session and suggests /compact when threshold reached.
#
# Created by JunyoungJung on 2026-04-16. Copyright © 2026 ai-symbiote.

set +e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

# Consume stdin (hook protocol requires reading it)
cat > /dev/null

# Session-scoped counter (fallback chain: CLAUDE > CURSOR > CODEX > default)
SESSION_ID="${CLAUDE_SESSION_ID:-${CURSOR_SESSION_ID:-${CODEX_SESSION_ID:-default}}}"
COUNTER_FILE="${TMPDIR:-/tmp}/symbiote-compact-${SESSION_ID}"

# Atomic read-increment-write inside lock to prevent race conditions
if command -v flock >/dev/null 2>&1; then
  LOCK_FILE="$COUNTER_FILE.lock"
  exec 9>"$LOCK_FILE"
  flock 9 2>/dev/null || true
  COUNT=0
  [ -f "$COUNTER_FILE" ] && COUNT=$(cat "$COUNTER_FILE" 2>/dev/null)
  case "$COUNT" in ''|*[!0-9]*) COUNT=0 ;; esac
  COUNT=$((COUNT + 1))
  echo "$COUNT" > "$COUNTER_FILE"
  exec 9>&-
else
  # Fallback (macOS): atomic write via temp file + mv
  COUNT=0
  [ -f "$COUNTER_FILE" ] && COUNT=$(cat "$COUNTER_FILE" 2>/dev/null)
  case "$COUNT" in ''|*[!0-9]*) COUNT=0 ;; esac
  COUNT=$((COUNT + 1))
  TMP_COUNTER=$(mktemp "${COUNTER_FILE}.XXXXXX" 2>/dev/null) || TMP_COUNTER="${COUNTER_FILE}.tmp.$$"
  echo "$COUNT" > "$TMP_COUNTER"
  mv -f "$TMP_COUNTER" "$COUNTER_FILE" 2>/dev/null || echo "$COUNT" > "$COUNTER_FILE"
fi

# Read threshold from env (default 50, clamp to 1-10000)
COMPACT_THRESHOLD="${COMPACT_THRESHOLD:-50}"
case "$COMPACT_THRESHOLD" in
  ''|*[!0-9]*) COMPACT_THRESHOLD=50 ;;
esac
if [ "$COMPACT_THRESHOLD" -lt 1 ]; then
  COMPACT_THRESHOLD=1
fi
if [ "$COMPACT_THRESHOLD" -gt 10000 ]; then
  COMPACT_THRESHOLD=10000
fi

# Check if we should suggest compaction
if [ "$COUNT" -eq "$COMPACT_THRESHOLD" ]; then
  emit_hook_notice "[Compact] ${COUNT} tool calls this session. Consider /compact before starting the next phase."
elif [ "$COUNT" -gt "$COMPACT_THRESHOLD" ]; then
  OVER=$((COUNT - COMPACT_THRESHOLD))
  if [ $((OVER % 25)) -eq 0 ]; then
    emit_hook_notice "[Compact] ${COUNT} tool calls this session. Consider /compact before starting the next phase."
  else
    emit_hook_continue
  fi
else
  emit_hook_continue
fi

exit 0
