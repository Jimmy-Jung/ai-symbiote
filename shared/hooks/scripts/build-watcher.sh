#!/bin/bash
# ai-symbiote PostToolUse(Bash) hook: Detect build/test failures from command output.
# Watches Bash tool results for build errors, test failures, and lint issues.
# Records to harness-log.jsonl for pattern learning.
#
# Author: JunyoungJung
# Date: 2026-04-13
#
# Principle: Silence on success — output ONLY when failure detected.
#
# Protocol:
#   stdin:  {"session_id":"...","tool_name":"Bash","tool_input":{"command":"..."},"tool_response":"..."}
#   stdout: {"continue":true,"systemMessage":"..."} when build failure pattern detected
#           (empty) on success
#
# Supported platforms: Claude Code (PostToolUse Bash), Codex CLI (PostToolUse Bash)

# Safety: never crash the agent workflow
trap 'exit 0' ERR
set +e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

INPUT=$(read_stdin_safe)

# --- 1. Extract command and response ---
COMMAND=""
TOOL_RESPONSE=""
EXIT_CODE=""
SUCCESS_FLAG=""
if command -v jq >/dev/null 2>&1; then
  COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
  TOOL_RESPONSE=$(printf '%s' "$INPUT" | jq -r '
    if (.tool_response | type?) == "string" then .tool_response
    else (.tool_response.stdout? // .tool_response.stderr? // .tool_response.output? // empty)
    end
  ' 2>/dev/null)
  EXIT_CODE=$(printf '%s' "$INPUT" | jq -r '
    [
      .exit_code,
      .exitCode,
      .exit_status,
      .tool_response.exit_code?,
      .tool_response.exitCode?,
      .tool_response.exit_status?
    ] | map(select(. != null)) | first // empty
  ' 2>/dev/null)
  SUCCESS_FLAG=$(printf '%s' "$INPUT" | jq -r '
    [
      .success,
      .tool_response.success?
    ] | map(select(. != null)) | first // empty
  ' 2>/dev/null)
else
  COMMAND=$(json_nested_field "$INPUT" "tool_input" "command")
  TOOL_RESPONSE=$(json_field "$INPUT" "tool_response")
  EXIT_CODE=$(json_field "$INPUT" "exit_code")
  [ -z "$EXIT_CODE" ] && EXIT_CODE=$(json_field "$INPUT" "exitCode")
  [ -z "$EXIT_CODE" ] && EXIT_CODE=$(json_field "$INPUT" "exit_status")
  SUCCESS_FLAG=$(json_field "$INPUT" "success")
fi

if [ -z "$COMMAND" ]; then
  exit 0
fi

# --- 2. State directory setup ---
STATE_DIR=$(get_state_dir)
[ -z "$STATE_DIR" ] && exit 0

SESSION_DIR="$STATE_DIR/state/session-$PPID"
mkdir -p "$SESSION_DIR" 2>/dev/null || exit 0

HARNESS_LOG="$STATE_DIR/harness-log.jsonl"
RULES_FILE="$STATE_DIR/harness-rules.md"
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# --- 3. Classify build/test command ---
BUILD_TYPE=""
COMMAND_KIND="unknown"
ERROR_CATEGORY=""
DESCRIPTION=""
RULE_CANDIDATE=""

# Detect build commands
case "$COMMAND" in
  *xcodebuild*test*|*swift\ test*)
    BUILD_TYPE="swift_build"
    COMMAND_KIND="test"
    ;;
  *xcodebuild*|*swift\ build*)
    BUILD_TYPE="swift_build"
    COMMAND_KIND="build"
    ;;
  *npm\ test*|*yarn\ test*|*bun\ test*)
    BUILD_TYPE="node_build"
    COMMAND_KIND="test"
    ;;
  *npm\ run\ build*|*yarn\ build*|*bun\ run\ build*)
    BUILD_TYPE="node_build"
    COMMAND_KIND="build"
    ;;
  *pytest*|*python\ -m\ test*|*python\ -m\ pytest*)
    BUILD_TYPE="python_test"
    COMMAND_KIND="test"
    ;;
  *go\ test*)
    BUILD_TYPE="go_build"
    COMMAND_KIND="test"
    ;;
  *go\ build*)
    BUILD_TYPE="go_build"
    COMMAND_KIND="build"
    ;;
  *cargo\ test*)
    BUILD_TYPE="rust_build"
    COMMAND_KIND="test"
    ;;
  *cargo\ build*)
    BUILD_TYPE="rust_build"
    COMMAND_KIND="build"
    ;;
  *make\ test*|*ctest*)
    BUILD_TYPE="make_build"
    COMMAND_KIND="test"
    ;;
  *make*|*cmake*)
    BUILD_TYPE="make_build"
    COMMAND_KIND="build"
    ;;
  *gradle*test*|*./gradlew*test*)
    BUILD_TYPE="gradle_build"
    COMMAND_KIND="test"
    ;;
  *gradle*|*./gradlew*)
    BUILD_TYPE="gradle_build"
    COMMAND_KIND="build"
    ;;
  *bash\ scripts/*test*|*sh\ scripts/*test*)
    BUILD_TYPE="project_script"
    COMMAND_KIND="test"
    ;;
  *bash\ scripts/*|*sh\ scripts/*)
    BUILD_TYPE="project_script"
    COMMAND_KIND="build"
    ;;
esac

# Not a build/test command — exit silently
if [ -z "$BUILD_TYPE" ]; then
  exit 0
fi

STRUCTURED_FAILURE=""
case "$EXIT_CODE" in
  ""|0) ;;
  *) STRUCTURED_FAILURE="yes" ;;
esac
[ "$SUCCESS_FLAG" = "false" ] && STRUCTURED_FAILURE="yes"

if [ -z "$TOOL_RESPONSE" ] && [ -z "$STRUCTURED_FAILURE" ]; then
  exit 0
fi

# --- 4. Detect failure from tool_response ---
# Check for common build/test failure patterns
HAS_FAILURE=""

# Test failures first
if printf '%s' "$TOOL_RESPONSE" | grep -qiF '** TEST FAILED **' 2>/dev/null || \
   printf '%s' "$TOOL_RESPONSE" | grep -qiE '(tests? failed|[0-9]+ failing|FAIL:|FAIL[[:space:]].*test|FAILED.*test|AssertionError|test[^[:alnum:]]*FAILED)' 2>/dev/null; then
  HAS_FAILURE="yes"
  ERROR_CATEGORY="test_failed"
fi

# Build failures
if [ -z "$HAS_FAILURE" ] && printf '%s' "$TOOL_RESPONSE" | grep -qiE '(BUILD FAILED|BUILD FAILURE|error:.*\.swift|xcodebuild.*failed|fatal error|npm ERR!|Error:.*Module not found|Cannot find module|error\[)' 2>/dev/null; then
  HAS_FAILURE="yes"
  ERROR_CATEGORY="build_failed"
fi

# Language/runtime failures that should follow the command kind
if [ -z "$HAS_FAILURE" ] && printf '%s' "$TOOL_RESPONSE" | grep -qiE '(ImportError|ModuleNotFoundError|SyntaxError|TypeError)' 2>/dev/null; then
  HAS_FAILURE="yes"
  if [ "$COMMAND_KIND" = "test" ]; then
    ERROR_CATEGORY="test_failed"
  else
    ERROR_CATEGORY="build_failed"
  fi
fi

# Generic failure signals from output
if [ -z "$HAS_FAILURE" ] && printf '%s' "$TOOL_RESPONSE" | grep -qiE '(exit code [1-9]|FAILED|Error:)' 2>/dev/null; then
  HAS_FAILURE="yes"
  if [ "$COMMAND_KIND" = "test" ]; then
    ERROR_CATEGORY="test_failed"
  else
    ERROR_CATEGORY="build_failed"
  fi
fi

# Structured failure without useful output still counts
if [ -z "$HAS_FAILURE" ] && [ -n "$STRUCTURED_FAILURE" ]; then
  HAS_FAILURE="yes"
  if [ "$COMMAND_KIND" = "test" ]; then
    ERROR_CATEGORY="test_failed"
  else
    ERROR_CATEGORY="build_failed"
  fi
fi

if [ -z "$HAS_FAILURE" ]; then
  exit 0
fi

# --- 5. Extract error summary (first meaningful error line, max 200 chars) ---
ERROR_SUMMARY=""
# Try to find the first error line
ERROR_SUMMARY=$(printf '%s' "$TOOL_RESPONSE" | grep -iE '(error:|Error:|FAIL|BUILD FAILED|BUILD FAILURE|npm ERR!|AssertionError|tests? failed)' 2>/dev/null | head -1 | cut -c1-200)
[ -z "$ERROR_SUMMARY" ] && [ -n "$EXIT_CODE" ] && [ "$EXIT_CODE" != "0" ] && ERROR_SUMMARY="command exited with code $EXIT_CODE"
[ -z "$ERROR_SUMMARY" ] && [ "$SUCCESS_FLAG" = "false" ] && ERROR_SUMMARY="command reported success=false"
[ -z "$ERROR_SUMMARY" ] && ERROR_SUMMARY="$BUILD_TYPE failed"

# Sanitize for JSON
ERROR_SUMMARY=$(printf '%s' "$ERROR_SUMMARY" | tr -d '\n\r' | sed 's/"/\\"/g' | cut -c1-200)

# Determine which file caused the error (from error output)
ERROR_FILE=""
# Swift: extract file path from "path/file.swift:line:col: error:"
ERROR_FILE=$(printf '%s' "$TOOL_RESPONSE" | grep -oE '[^ ]+\.swift:[0-9]+:[0-9]+:' 2>/dev/null | head -1 | sed 's/:[0-9]*:[0-9]*:$//')
# JS/TS: extract from "Error: path/file.ts(line,col)"  or "at path/file.js:line"
if [ -z "$ERROR_FILE" ]; then
  ERROR_FILE=$(printf '%s' "$TOOL_RESPONSE" | grep -oE '[^ ]+\.(ts|js|tsx|jsx):[0-9]+' 2>/dev/null | head -1 | sed 's/:[0-9]*$//')
fi
# Python: extract from 'File "path/file.py", line N'
if [ -z "$ERROR_FILE" ]; then
  ERROR_FILE=$(printf '%s' "$TOOL_RESPONSE" | grep -oE 'File "[^"]+\.py"' 2>/dev/null | head -1 | sed 's/File "//;s/"$//')
fi

ESCAPED_FILE=""
BASENAME=""
if [ -n "$ERROR_FILE" ]; then
  ESCAPED_FILE=$(json_escape "$ERROR_FILE")
  BASENAME=$(basename "$ERROR_FILE")
  DESCRIPTION="$BASENAME: $ERROR_CATEGORY ($ERROR_SUMMARY)"
  RULE_CANDIDATE="After editing $BASENAME, run build/test to verify before making more changes"
else
  DESCRIPTION="$BUILD_TYPE: $ERROR_CATEGORY ($ERROR_SUMMARY)"
  RULE_CANDIDATE="Run build/test after each edit batch to catch errors early"
  ESCAPED_FILE="$BUILD_TYPE"
fi

# --- 6. Record to harness-log.jsonl ---
ESC_CMD=$(printf '%s' "$COMMAND" | cut -c1-100 | sed 's/"/\\"/g')
ESC_DESC=$(json_escape "$DESCRIPTION")
ESC_RULE=$(json_escape "$RULE_CANDIDATE")
ESC_SUMMARY=$(json_escape "$ERROR_SUMMARY")

printf '{"v":2,"ts":"%s","error_type":"build_%s","error_category":"%s","file":"%s","description":"%s","rule_candidate":"%s","command":"%s","error_summary":"%s","session_pid":"%s"}\n' \
  "$NOW" "$ERROR_CATEGORY" "$ERROR_CATEGORY" "$ESCAPED_FILE" "$ESC_DESC" "$ESC_RULE" "$ESC_CMD" "$ESC_SUMMARY" "$PPID" >> "$HARNESS_LOG" 2>/dev/null

# --- 7. Check repeated build failures (same error_category + file in 7 days) ---
if [ -f "$HARNESS_LOG" ] && [ -f "$RULES_FILE" ]; then
  PATTERN_COUNT=$(filter_recent_jsonl "$HARNESS_LOG" 7 | \
    grep "\"error_type\":\"build_$ERROR_CATEGORY\"" 2>/dev/null | \
    grep "\"file\":\"$ESCAPED_FILE\"" 2>/dev/null | \
    wc -l | tr -d ' ') || PATTERN_COUNT=0

  if [ "$PATTERN_COUNT" -ge 2 ]; then
    # Dedup
    if grep -qF "$RULE_CANDIDATE" "$RULES_FILE" 2>/dev/null; then
      exit 0
    fi

    LINE_COUNT=$(wc -l < "$RULES_FILE" | tr -d ' ')
    if [ "$LINE_COUNT" -ge 300 ]; then
      emit_hook_notice "[Harness] harness-rules.md reached ${LINE_COUNT} lines. Run gc skill to prune."
      exit 0
    fi

    RULE_COUNT=$(grep -c '^\[Harness #' "$RULES_FILE" 2>/dev/null) || RULE_COUNT=0
    NEXT_ID=$((RULE_COUNT + 1))
    TODAY=$(date +%Y-%m-%d)

    printf '\n[Harness #%d] %s (auto-generated %s)\n' "$NEXT_ID" "$RULE_CANDIDATE" "$TODAY" >> "$RULES_FILE" 2>/dev/null
    printf '{"v":2,"ts":"%s","type":"rule_created","rule_id":%d,"description":"%s","source":"build_watcher"}\n' \
      "$NOW" "$NEXT_ID" "$ESC_DESC" >> "$HARNESS_LOG" 2>/dev/null

    emit_hook_notice "[Harness] Repeated ${ERROR_CATEGORY} in ${BASENAME:-$BUILD_TYPE} - auto-added Harness #${NEXT_ID} rule."
    exit 0
  fi
fi

exit 0
