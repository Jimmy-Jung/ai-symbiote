#!/bin/bash
# ai-symbiote PostToolUse(Write|Edit) hook: Detect unnecessary AI-generated comments.
# Warns when edited files contain patterns of low-value comments.
#
# Principle: Silence on success — output ONLY when suspicious comments exceed threshold.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/security-mode.sh
# Defensive load: a source failure must not silently disable the hook.
source "$SCRIPT_DIR/lib/security-mode.sh" 2>/dev/null || true
if [ "${_SEC_MODE_LIB_LOADED:-0}" = "1" ] && ! is_hook_enabled commentChecker; then
  exit 0
fi

INPUT=$(read_stdin_safe)

FILE_PATH=$(json_nested_field "$INPUT" "tool_input" "file_path")
if [ -z "$FILE_PATH" ]; then
  FILE_PATH=$(json_field "$INPUT" "file_path")
fi

if [ -z "$FILE_PATH" ] || [ ! -f "$FILE_PATH" ]; then
  exit 0
fi

case "$FILE_PATH" in
  *.md|*.mdc|*.json|*.yaml|*.yml|*.txt|*.sh|*.env*)
    exit 0
    ;;
esac

COMMENT_COUNT=0

P1=$(grep -cE '^\s*(//|#|/\*)\s*(Initialize|Set|Get|Return|Create|Update|Delete|Check|Handle|Process)\s' "$FILE_PATH" 2>/dev/null) || P1=0
P2=$(grep -cE '^\s*(//|#)\s*(if |for |while |function |def |class |return |import |from |require |include |export |const |var |let )' "$FILE_PATH" 2>/dev/null) || P2=0
P3=$(grep -cE '^\s*(//|#)\s*(TODO|FIXME|HACK|XXX)\s*$' "$FILE_PATH" 2>/dev/null) || P3=0

COMMENT_COUNT=$((P1 + P2 + P3))

if [ "$COMMENT_COUNT" -gt 3 ]; then
  emit_hook_notice "[Comment Checker] ${COMMENT_COUNT} suspicious comments in ${FILE_PATH}: trivial(${P1}), commented-out code(${P2}), empty TODO(${P3})."
fi

exit 0
