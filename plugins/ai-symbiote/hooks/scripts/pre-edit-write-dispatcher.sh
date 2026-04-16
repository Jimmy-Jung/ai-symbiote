#!/bin/bash
# ai-symbiote PreToolUse dispatcher: Consolidates Edit/Write pre-flight checks.
# Runs config-protection, gateguard-gate, and suggest-compact in sequence.
# First block wins — if any sub-handler blocks, dispatcher stops and outputs that block.
#
# Created by JunyoungJung on 2026-04-16. Copyright © 2026 ai-symbiote.

# Safety: never crash the agent workflow
trap 'exit 0' ERR
set +e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

# --- 1. Read stdin into temp file (needs to be passed to each sub-handler) ---
STDIN_TMP=$(mktemp "${TMPDIR:-/tmp}/symbiote-dispatcher.XXXXXX" 2>/dev/null)
cat > "$STDIN_TMP"
trap 'rm -f "$STDIN_TMP"' EXIT

# --- 2. config-protection.sh (highest priority — blocking a config edit is more important) ---
if [ -f "$SCRIPT_DIR/config-protection.sh" ]; then
  OUTPUT=$(cat "$STDIN_TMP" | bash "$SCRIPT_DIR/config-protection.sh" 2>/dev/null)
  if echo "$OUTPUT" | grep -q '"continue":false' 2>/dev/null; then
    echo "$OUTPUT"
    exit 0
  fi
fi

# --- 3. gateguard-gate.sh (second — must read before edit) ---
# Skip gateguard if tracker session file mechanism is unavailable (e.g., Codex lacks Read tracker).
# Presence of the tracker script on the same platform indicates the tracking pipeline is active.
GATEGUARD_TRACKER="$SCRIPT_DIR/gateguard-tracker.sh"
if [ -f "$SCRIPT_DIR/gateguard-gate.sh" ] && [ -f "$GATEGUARD_TRACKER" ]; then
  OUTPUT=$(cat "$STDIN_TMP" | bash "$SCRIPT_DIR/gateguard-gate.sh" 2>/dev/null)
  if echo "$OUTPUT" | grep -q '"continue":false' 2>/dev/null; then
    echo "$OUTPUT"
    exit 0
  fi
fi

# --- 4. suggest-compact.sh (lowest — just a suggestion, never blocks) ---
if [ -f "$SCRIPT_DIR/suggest-compact.sh" ]; then
  COMPACT_OUTPUT=$(cat "$STDIN_TMP" | bash "$SCRIPT_DIR/suggest-compact.sh" 2>/dev/null)
  if echo "$COMPACT_OUTPUT" | grep -q 'systemMessage\|user_message' 2>/dev/null; then
    echo "$COMPACT_OUTPUT"
    exit 0
  fi
fi

# --- 5. Nothing blocked and no notice — continue ---
emit_hook_continue
exit 0
