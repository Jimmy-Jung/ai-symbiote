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
# the user explicitly invokes it. See docs/02-아키텍처.md ("Write-time
# Verification Layer" section) for Option D details.
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

# Project: derive from git repo root basename (best-effort, fallback "unknown").
# NOTE: basename alone collides when two repos share a name (e.g., ~/work/app
# and ~/tmp/app). We also store repo_root (absolute path) below so /verify and
# setup-check.sh can filter precisely. `project` stays for human-readable UI.
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

# base_sha: HEAD sha captured at edit time. Stored separately from any future
# commit sha so /verify can compute the correct diff contract:
#   - if current HEAD == base_sha: edit is still uncommitted
#       → use `git diff <base_sha> -- <file>` (unstaged) / `--cached` (staged)
#   - if current HEAD != base_sha: commits landed after this edit
#       → use `git diff <base_sha>..HEAD -- <file>` for combined post-edit diff
# NEVER use `git show <base_sha> -- <file>`: base_sha is the PRE-edit HEAD so
# `git show` returns the prior commit's contents, not the edit being reviewed.
BASE_SHA=$(cd "$REPO_ROOT" 2>/dev/null && git rev-parse --short HEAD 2>/dev/null || true)
[ -z "$BASE_SHA" ] && BASE_SHA="uncommitted"

# Legacy `sha` field retained for backward compatibility with pre-0.11 consumers.
# New consumers must read `base_sha`. Remove `sha` at next major version bump.
SHA="$BASE_SHA"

# --- 4. Escape fields for JSON ---
FILE_ESCAPED=$(json_escape "$FILE_PATH")
PROJECT_ESCAPED=$(json_escape "$PROJECT")
BRANCH_ESCAPED=$(json_escape "$BRANCH")
SHA_ESCAPED=$(json_escape "$SHA")
BASE_SHA_ESCAPED=$(json_escape "$BASE_SHA")
REPO_ROOT_ESCAPED=$(json_escape "$REPO_ROOT")
TRIGGER_ESCAPED=$(json_escape "$TRIGGER_LC")

# --- 5. Append queue entry ---
# Schema v2 fields (since 2026-04-21):
#   repo_root : absolute path of the git worktree root. Dedupes same-name repos.
#   base_sha  : HEAD at the moment of edit. Used for diff contract in /verify.
# Legacy v1 field `sha` mirrors base_sha and is preserved for consumers that
# have not migrated. See shared/skills/verify/SKILL.md Step 3 for the diff
# collection contract that depends on base_sha semantics.
printf '{"ts":"%s","project":"%s","repo_root":"%s","branch":"%s","base_sha":"%s","sha":"%s","file":"%s","trigger":"%s"}\n' \
  "$NOW" "$PROJECT_ESCAPED" "$REPO_ROOT_ESCAPED" "$BRANCH_ESCAPED" "$BASE_SHA_ESCAPED" "$SHA_ESCAPED" "$FILE_ESCAPED" "$TRIGGER_ESCAPED" \
  >> "$QUEUE_FILE" 2>/dev/null

# --- 6. Silence on success ---
printf '{"continue":true}\n'
exit 0
