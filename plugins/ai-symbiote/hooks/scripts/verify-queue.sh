#!/bin/bash
# ai-symbiote PostToolUse(Write|Edit) hook: Write-time Verification Layer queue.
# Append edit metadata to ~/.ai-symbiote/state/verify-queue.jsonl for later /verify execution.
#
# Author: JunyoungJung
# Date: 2026-04-20
#
# Design rationale: hooks.json has timeout: 10s, but Judge-based verification
# (~30s per call) cannot fit in that window. This hook only does O(<100ms) queue
# append; actual verification runs synchronously inside the `/verify` skill when
# the user explicitly invokes it. See docs/ARCHITECTURE.md for Option D details.
#
# Principle: Silence on success — never blocks edit flow.
#
# Protocol:
#   stdin:  Claude Code hook event JSON (tool_input.file_path available)
#   stdout: {"continue":true} (always; queue append is fire-and-forget)

# Safety: never crash the agent workflow. Use explicit `|| true` on git calls
# rather than ERR trap which fires on any non-zero exit.
set +e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

INPUT=$(cat)

# --- 1. Extract file path ---
FILE_PATH=$(json_nested_field "$INPUT" "tool_input" "file_path")
if [ -z "$FILE_PATH" ]; then
  FILE_PATH=$(json_field "$INPUT" "file_path")
fi

# Skip if no file path (e.g., hook fired for non-edit tool)
if [ -z "$FILE_PATH" ]; then
  printf '{"continue":true}\n'
  exit 0
fi

# --- 2. Queue directory (global, project-agnostic) ---
QUEUE_DIR="$HOME/.ai-symbiote/state"
mkdir -p "$QUEUE_DIR" 2>/dev/null || {
  printf '{"continue":true}\n'
  exit 0
}
QUEUE_FILE="$QUEUE_DIR/verify-queue.jsonl"

# --- 3. Collect metadata ---
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
TOOL_NAME=$(json_field "$INPUT" "tool_name")
TRIGGER="${TOOL_NAME:-write}"
# Lowercase the trigger for consistency (Write -> write, Edit -> edit)
TRIGGER_LC=$(printf '%s' "$TRIGGER" | tr '[:upper:]' '[:lower:]')

# Project slug: derive from git repo root basename (best-effort, fallback "unknown")
FILE_DIR=$(dirname "$FILE_PATH" 2>/dev/null || echo ".")
REPO_ROOT=$(cd "$FILE_DIR" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null || true)
if [ -z "$REPO_ROOT" ]; then
  REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
fi
PROJECT=$(basename "$REPO_ROOT" 2>/dev/null || echo "unknown")
[ -z "$PROJECT" ] && PROJECT="unknown"

# Branch
BRANCH=$(cd "$REPO_ROOT" 2>/dev/null && git branch --show-current 2>/dev/null || true)
[ -z "$BRANCH" ] && BRANCH="unknown"

# HEAD sha (or "uncommitted" if no commits yet)
SHA=$(cd "$REPO_ROOT" 2>/dev/null && git rev-parse --short HEAD 2>/dev/null || true)
[ -z "$SHA" ] && SHA="uncommitted"

# --- 4. Escape file path for JSON ---
FILE_ESCAPED=$(json_escape "$FILE_PATH")
PROJECT_ESCAPED=$(json_escape "$PROJECT")
BRANCH_ESCAPED=$(json_escape "$BRANCH")
SHA_ESCAPED=$(json_escape "$SHA")
TRIGGER_ESCAPED=$(json_escape "$TRIGGER_LC")

# --- 5. Append queue entry ---
printf '{"ts":"%s","project":"%s","branch":"%s","sha":"%s","file":"%s","trigger":"%s"}\n' \
  "$NOW" "$PROJECT_ESCAPED" "$BRANCH_ESCAPED" "$SHA_ESCAPED" "$FILE_ESCAPED" "$TRIGGER_ESCAPED" \
  >> "$QUEUE_FILE" 2>/dev/null

# --- 6. Silence on success ---
printf '{"continue":true}\n'
exit 0
