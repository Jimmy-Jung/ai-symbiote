#!/usr/bin/env bash
# Codex-compatible Ralph loop runner.
#
# Author: JunyoungJung
# Date: 2026-04-17

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../hooks/scripts/lib/common.sh"

PROJECT_ROOT="${RALPH_PROJECT_ROOT:-}"
STATE_DIR="${RALPH_STATE_DIR:-}"
TOOL="${RALPH_TOOL:-}"
MAX_ITERATIONS="${RALPH_MAX_ITERATIONS:-10}"
PREPARE_ONLY="false"
UNSAFE="false"

usage() {
  cat <<'EOF'
Usage: ralph-loop.sh [options]

Options:
  --project-root PATH     Project root to operate on
  --state-dir PATH        Symbiote state directory
  --tool codex|claude|amp Tool runtime to use
  --max-iterations N      Maximum iterations (default: 10)
  --prepare-only          Prepare state files but do not invoke the tool
  --unsafe                Use fully unsandboxed execution for Codex
  -h, --help              Show this help
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --project-root)
      PROJECT_ROOT="${2:-}"
      shift 2
      ;;
    --state-dir)
      STATE_DIR="${2:-}"
      shift 2
      ;;
    --tool)
      TOOL="${2:-}"
      shift 2
      ;;
    --tool=*)
      TOOL="${1#*=}"
      shift
      ;;
    --max-iterations)
      MAX_ITERATIONS="${2:-}"
      shift 2
      ;;
    --max-iterations=*)
      MAX_ITERATIONS="${1#*=}"
      shift
      ;;
    --prepare-only)
      PREPARE_ONLY="true"
      shift
      ;;
    --unsafe)
      UNSAFE="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "[Ralph] Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [ -z "$PROJECT_ROOT" ]; then
  PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
fi

if [ -z "$STATE_DIR" ]; then
  STATE_DIR=$(cd "$PROJECT_ROOT" && get_state_dir)
fi

if ! [[ "$MAX_ITERATIONS" =~ ^[0-9]+$ ]]; then
  echo "[Ralph] --max-iterations must be a positive integer." >&2
  exit 1
fi

detect_default_tool() {
  if command -v codex >/dev/null 2>&1; then
    printf 'codex'
  elif command -v claude >/dev/null 2>&1; then
    printf 'claude'
  elif command -v amp >/dev/null 2>&1; then
    printf 'amp'
  else
    printf ''
  fi
}

if [ -z "$TOOL" ]; then
  TOOL=$(detect_default_tool)
fi

if [ -z "$TOOL" ] && [ "$PREPARE_ONLY" = "true" ]; then
  TOOL="codex"
fi

case "$TOOL" in
  codex|claude|amp) ;;
  *)
    echo "[Ralph] Supported tools: codex, claude, amp" >&2
    exit 1
    ;;
esac

RALPH_DIR="$STATE_DIR/ralph"
PRD_FILE="$RALPH_DIR/prd.json"
PROGRESS_FILE="$RALPH_DIR/progress.txt"
ARCHIVE_DIR="$RALPH_DIR/archive"
LAST_BRANCH_FILE="$RALPH_DIR/.last-branch"
LAST_PRD_FILE="$RALPH_DIR/.last-prd.json"
PROMPT_FILE="$RALPH_DIR/.ralph-prompt.md"
mkdir -p "$RALPH_DIR" "$ARCHIVE_DIR" "$STATE_DIR/state"

if [ ! -f "$PRD_FILE" ]; then
  echo "[Ralph] Missing prd.json: $PRD_FILE" >&2
  echo "[Ralph] Generate it first with the ralph skill." >&2
  exit 1
fi

PRD_JSON="$(cat "$PRD_FILE")"
BRANCH_NAME="$(json_field "$PRD_JSON" "branchName")"
TASK_DESCRIPTION="$(json_field "$PRD_JSON" "description")"
PROJECT_NAME="$(json_field "$PRD_JSON" "project")"

if [ -z "$BRANCH_NAME" ]; then
  echo "[Ralph] prd.json must include branchName." >&2
  exit 1
fi

branch_to_task_basename() {
  local branch_name="$1"
  local task_basename
  task_basename="$(printf '%s' "${branch_name#ralph/}" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-//; s/-$//')"
  if [ -z "$task_basename" ]; then
    task_basename="ralph-task"
  fi
  printf '%s' "$task_basename"
}

TASK_BASENAME="$(branch_to_task_basename "$BRANCH_NAME")"

TASK_DIR="$STATE_DIR/state/ralph-$TASK_BASENAME"
STATE_FILE="$TASK_DIR/ralph-state.md"
NOTEPAD_FILE="$TASK_DIR/notepad.md"
mkdir -p "$TASK_DIR"

STARTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

read_branch() {
  if [ -f "$1" ]; then
    cat "$1" 2>/dev/null || true
  fi
}

read_prd_branch() {
  if [ -f "$1" ]; then
    json_field "$(cat "$1")" "branchName"
  fi
}

ensure_progress_file() {
  if [ -f "$PROGRESS_FILE" ]; then
    return 0
  fi
  cat > "$PROGRESS_FILE" <<EOF
# Ralph Progress Log

## Codebase Patterns

Started: $STARTED_AT
---
EOF
}

archive_previous_run_if_needed() {
  local last_branch current_branch archive_date archive_name archive_path
  local previous_task_basename previous_task_dir previous_state_file previous_prd_source
  current_branch="$BRANCH_NAME"
  last_branch="$(read_branch "$LAST_BRANCH_FILE")"

  if [ -z "$last_branch" ] || [ "$last_branch" = "$current_branch" ]; then
    return 0
  fi

  archive_date="$(date +%Y-%m-%d)"
  archive_name="$(printf '%s' "${last_branch#ralph/}" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-//; s/-$//')"
  [ -n "$archive_name" ] || archive_name="previous-run"
  archive_path="$ARCHIVE_DIR/$archive_date-$archive_name"
  mkdir -p "$archive_path"

  previous_task_basename="$(branch_to_task_basename "$last_branch")"
  previous_task_dir="$STATE_DIR/state/ralph-$previous_task_basename"
  previous_state_file="$previous_task_dir/ralph-state.md"
  previous_prd_source=""

  if [ -f "$LAST_PRD_FILE" ] && [ "$(read_prd_branch "$LAST_PRD_FILE")" = "$last_branch" ]; then
    previous_prd_source="$LAST_PRD_FILE"
  elif [ "$(read_prd_branch "$PRD_FILE")" = "$last_branch" ]; then
    previous_prd_source="$PRD_FILE"
  fi

  [ -n "$previous_prd_source" ] && cp "$previous_prd_source" "$archive_path/prd.json"
  [ -f "$PROGRESS_FILE" ] && cp "$PROGRESS_FILE" "$archive_path/progress.txt"
  [ -f "$previous_state_file" ] && cp "$previous_state_file" "$archive_path/ralph-state.md"

  rm -f "$PROGRESS_FILE"
}

write_current_branch() {
  printf '%s\n' "$BRANCH_NAME" > "$LAST_BRANCH_FILE"
}

write_current_prd_snapshot() {
  cp "$PRD_FILE" "$LAST_PRD_FILE"
}

write_notepad() {
  cat > "$NOTEPAD_FILE" <<EOF
# Ralph Notepad

- project: ${PROJECT_NAME:-unknown}
- branch: $BRANCH_NAME
- workspace: $PROJECT_ROOT
- ralphDir: $RALPH_DIR
EOF
}

write_state() {
  local active="$1"
  local iteration="$2"
  local phase="$3"
  local completion_level="$4"
  local step="$5"

  cat > "$STATE_FILE" <<EOF
# Ralph State

- active: $active
- iteration: $iteration
- maxIterations: $MAX_ITERATIONS
- phase: $phase
- step: $step
- taskDescription: ${TASK_DESCRIPTION:-$BRANCH_NAME}
- completionLevel: $completion_level
- startedAt: $STARTED_AT
- tool: $TOOL
- branchName: $BRANCH_NAME
EOF
}

build_prompt() {
  local iteration="$1"
  cat > "$PROMPT_FILE" <<EOF
# Ralph Agent Instructions

You are an autonomous coding agent working on a software project.

## Workspace

- Project root: $PROJECT_ROOT
- Ralph state directory: $RALPH_DIR
- PRD file: $PRD_FILE
- Progress log: $PROGRESS_FILE
- Loop state file: $STATE_FILE
- Iteration: $iteration of $MAX_ITERATIONS

## Your Task

1. Read the PRD at \`$PRD_FILE\`.
2. Read the progress log at \`$PROGRESS_FILE\` and check \`## Codebase Patterns\` first.
3. Check whether the current git branch matches PRD \`branchName\`. If not, switch or create it from the main development branch.
4. Pick the highest-priority user story where \`passes: false\`.
5. Implement exactly that one user story.
6. Run the project's quality checks that fit the change surface.
7. If you discover reusable local patterns, update nearby \`AGENTS.md\` files.
8. If checks pass, commit all related changes with message: \`feat: [Story ID] - [Story Title]\`.
9. Update \`$PRD_FILE\` so the completed story becomes \`passes: true\`.
10. Append progress to \`$PROGRESS_FILE\`.

## Progress Entry Format

Append to \`$PROGRESS_FILE\`:

\`\`\`text
## [UTC timestamp] - [Story ID]
- What was implemented
- Files changed
- Checks run and result
- Learnings for future iterations:
  - reusable patterns
  - gotchas
  - useful context
---
\`\`\`

If you discover a reusable rule, also add it under the \`## Codebase Patterns\` section near the top of \`$PROGRESS_FILE\`.

## Quality Rules

- Do not work on more than one story in this iteration.
- Do not commit broken code.
- Keep changes tightly scoped to the selected story.
- For UI stories, use browser tooling when available and note if manual verification is still needed.

## Stop Condition

If every story in \`$PRD_FILE\` has \`passes: true\`, finish with:

<promise>COMPLETE</promise>

If unfinished stories remain, end normally without the completion tag.
EOF
}

run_tool_once() {
  case "$TOOL" in
    codex)
      if [ "$UNSAFE" = "true" ]; then
        codex exec --dangerously-bypass-approvals-and-sandbox \
          -C "$PROJECT_ROOT" \
          --add-dir "$STATE_DIR" \
          - < "$PROMPT_FILE"
      else
        codex exec --full-auto \
          -C "$PROJECT_ROOT" \
          --add-dir "$STATE_DIR" \
          - < "$PROMPT_FILE"
      fi
      ;;
    claude)
      claude --dangerously-skip-permissions --print < "$PROMPT_FILE"
      ;;
    amp)
      amp --dangerously-allow-all < "$PROMPT_FILE"
      ;;
  esac
}

archive_previous_run_if_needed
ensure_progress_file
write_current_branch
write_current_prd_snapshot
write_notepad

if [ "$PREPARE_ONLY" = "true" ]; then
  write_state "false" "0" "prepared" "0" "0"
  echo "[Ralph] Prepared workspace: $RALPH_DIR"
  echo "[Ralph] State file: $STATE_FILE"
  exit 0
fi

require_tool() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "[Ralph] Required tool is not installed: $1" >&2
    exit 1
  fi
}

case "$TOOL" in
  codex) require_tool codex ;;
  claude) require_tool claude ;;
  amp) require_tool amp ;;
esac

echo "[Ralph] Starting loop"
echo "[Ralph] tool=$TOOL iterations=$MAX_ITERATIONS"
echo "[Ralph] project=$PROJECT_ROOT"
echo "[Ralph] state=$STATE_DIR"

for iteration in $(seq 1 "$MAX_ITERATIONS"); do
  completion=$(( iteration * 100 / MAX_ITERATIONS ))
  write_state "true" "$iteration" "run" "$completion" "$iteration"
  build_prompt "$iteration"

  echo ""
  echo "==============================================================="
  echo "  Ralph Iteration $iteration / $MAX_ITERATIONS ($TOOL)"
  echo "==============================================================="

  OUTPUT="$(run_tool_once 2>&1 | tee /dev/stderr)" || true

  if printf '%s' "$OUTPUT" | grep -q "<promise>COMPLETE</promise>"; then
    write_state "false" "$iteration" "complete" "100" "$iteration"
    echo "[Ralph] All stories completed."
    exit 0
  fi
done

write_state "false" "$MAX_ITERATIONS" "max-iterations" "100" "$MAX_ITERATIONS"
echo "[Ralph] Reached max iterations without completion." >&2
exit 1
