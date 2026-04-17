#!/bin/bash
# ai-symbiote UserPromptSubmit hook: Intent-based skill routing.
# Reads user prompt and injects intent classification hints so the AI
# can recommend appropriate skills for natural language requests.
#
# Created by JunyoungJung on 2026-04-16. Copyright © 2026 ai-symbiote.

trap 'exit 0' ERR
set +e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

# Read stdin (hook protocol passes JSON via stdin)
INPUT=$(read_stdin_safe)

# Extract user_prompt from JSON input
PROMPT=""
if command -v jq >/dev/null 2>&1; then
  PROMPT=$(printf '%s' "$INPUT" | jq -r '.user_prompt // empty' 2>/dev/null) || PROMPT=""
elif command -v python3 >/dev/null 2>&1; then
  PROMPT=$(printf '%s' "$INPUT" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
    print(d.get("user_prompt", ""))
except Exception:
    pass
' 2>/dev/null) || PROMPT=""
else
  PROMPT=$(printf '%s' "$INPUT" | grep -o '"user_prompt"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/"user_prompt"[[:space:]]*:[[:space:]]*"//' | sed 's/"$//') || PROMPT=""
fi

# Empty prompt → pass through
if [ -z "$PROMPT" ]; then
  emit_hook_continue
  exit 0
fi

# Already a slash command → pass through
case "$PROMPT" in
  /*)
    emit_hook_continue
    exit 0
    ;;
esac

# Short prompts (< 3 words) → pass through
WORD_COUNT=$(echo "$PROMPT" | wc -w | tr -d ' ')
if [ "$WORD_COUNT" -lt 3 ] 2>/dev/null; then
  emit_hook_continue
  exit 0
fi

# Locate intent-hints.json
HINTS_FILE="$SCRIPT_DIR/../../lib/intent-hints.json"
# Fallback paths for different build layouts
[ ! -f "$HINTS_FILE" ] && HINTS_FILE="$SCRIPT_DIR/../lib/intent-hints.json"

# Hints file not found → pass through
if [ ! -f "$HINTS_FILE" ]; then
  emit_hook_continue
  exit 0
fi

# Build compact intent summary (avoid injecting full JSON every prompt)
COMPACT_HINTS=""
if command -v jq >/dev/null 2>&1; then
  COMPACT_HINTS=$(jq -r '.categories | to_entries[] | select(.key != "none") | "\(.key): \(.value.signals | join("; ")) → /\(.value.recommended_skills | join(", /"))"' "$HINTS_FILE" 2>/dev/null) || COMPACT_HINTS=""
elif command -v python3 >/dev/null 2>&1; then
  COMPACT_HINTS=$(HINTS_FILE="$HINTS_FILE" python3 -c "
import json, os
with open(os.environ['HINTS_FILE']) as f:
    data = json.load(f)
for k, v in data['categories'].items():
    if k == 'none': continue
    skills = ', /'.join(v['recommended_skills'])
    signals = '; '.join(v['signals'])
    print(f\"{k}: {signals} → /{skills}\")
" 2>/dev/null) || COMPACT_HINTS=""
fi

if [ -z "$COMPACT_HINTS" ]; then
  emit_hook_continue
  exit 0
fi

# Build systemMessage with compact hints (not full JSON)
MESSAGE="[Intent Router] Classify the user's intent and recommend a skill if appropriate.

$COMPACT_HINTS

Rules:
- If the user's request clearly matches a category, suggest the recommended skills
- If the intent is 'none' or unclear, do NOT suggest any skill
- Format: \"Recommended: /skill-name — reason\"
- This is a suggestion only. Proceed with the user's request regardless."

emit_hook_context "$MESSAGE"
exit 0
