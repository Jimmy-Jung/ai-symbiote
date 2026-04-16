#!/bin/bash
# ai-symbiote PreCompact hook: Preserve Tier 1 fingerprint during context compaction.
# Re-injects project identity, Seed rules, and Synapse keyword map so the AI
# retains project awareness after compaction.
#
# Created by JunyoungJung on 2026-04-16. Copyright © 2026 ai-symbiote.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

cat > /dev/null

STATE_DIR=$(get_state_dir)
CONTEXT_PARTS=()

# (a) Inject project and stack summary from manifest.json
if [ -f "$STATE_DIR/manifest.json" ]; then
  MANIFEST_JSON=$(cat "$STATE_DIR/manifest.json" 2>/dev/null)
  if [ -n "$MANIFEST_JSON" ]; then
    PROJ_NAME=$(json_nested_field "$MANIFEST_JSON" "project" "name")
    PROJ_TYPE=$(json_nested_field "$MANIFEST_JSON" "project" "type")
    PROJ_LANGS=$(json_nested_field "$MANIFEST_JSON" "project" "languages")
    STACK_PM=$(json_nested_field "$MANIFEST_JSON" "stack" "packageManager")
    STACK_BUILD=$(json_nested_field "$MANIFEST_JSON" "stack" "buildTool")
    STACK_FW=$(json_nested_field "$MANIFEST_JSON" "stack" "frameworks")
    STACK_ARCH=$(json_nested_field "$MANIFEST_JSON" "stack" "architecture")
    STACK_TEST=$(json_nested_field "$MANIFEST_JSON" "stack" "testFramework")
    STACK_CICD=$(json_nested_field "$MANIFEST_JSON" "stack" "cicd")

    MANIFEST_SUMMARY=""
    [ -n "$PROJ_NAME" ] && MANIFEST_SUMMARY="project: ${PROJ_NAME}"
    [ -n "$PROJ_TYPE" ] && MANIFEST_SUMMARY="${MANIFEST_SUMMARY}, type: ${PROJ_TYPE}"
    [ -n "$PROJ_LANGS" ] && MANIFEST_SUMMARY="${MANIFEST_SUMMARY}, languages: ${PROJ_LANGS}"
    [ -n "$STACK_PM" ] && MANIFEST_SUMMARY="${MANIFEST_SUMMARY}, packageManager: ${STACK_PM}"
    [ -n "$STACK_BUILD" ] && MANIFEST_SUMMARY="${MANIFEST_SUMMARY}, buildTool: ${STACK_BUILD}"
    [ -n "$STACK_FW" ] && MANIFEST_SUMMARY="${MANIFEST_SUMMARY}, frameworks: ${STACK_FW}"
    [ -n "$STACK_ARCH" ] && MANIFEST_SUMMARY="${MANIFEST_SUMMARY}, architecture: ${STACK_ARCH}"
    [ -n "$STACK_TEST" ] && MANIFEST_SUMMARY="${MANIFEST_SUMMARY}, testFramework: ${STACK_TEST}"
    [ -n "$STACK_CICD" ] && MANIFEST_SUMMARY="${MANIFEST_SUMMARY}, cicd: ${STACK_CICD}"

    if [ -n "$MANIFEST_SUMMARY" ]; then
      CONTEXT_PARTS+=("[Symbiote Manifest] ${MANIFEST_SUMMARY}")
    fi
  fi
fi

# (b) Tier 1: inject first 5 non-empty lines as excerpt + pointer
if [ -f "$STATE_DIR/context.md" ]; then
  CONTEXT_EXCERPT=$(grep -v '^$' "$STATE_DIR/context.md" 2>/dev/null | head -5 | tr '\n' ' ')
  if [ -n "$CONTEXT_EXCERPT" ]; then
    CONTEXT_PARTS+=("[Symbiote Context] ${CONTEXT_EXCERPT} | Full details: Read $STATE_DIR/context.md before making code changes.")
  fi
fi

# (c) Harness rules: extract Seed rules only
if [ -f "$STATE_DIR/harness-rules.md" ]; then
  SEED_RULES=$(grep '^\[Seed #' "$STATE_DIR/harness-rules.md" 2>/dev/null)
  if [ -n "$SEED_RULES" ]; then
    CONTEXT_PARTS+=("[Harness Seed Rules] $SEED_RULES")
  fi
fi

# (d) Synapse compact keyword map
if [ -f "$STATE_DIR/manifest.json" ]; then
  CONTEXT_PARTS+=('[Synapse] Keywords: "until done/keep going"->auto, "max performance/parallel"->auto --parallel-max, "deep analysis"->analyze, "code review"->review, "plan"->plan, "PRD"->prd, "evolve"->evolve, "commit"->git-commit. Medium+ tasks: form Scout/Architect/Builder/Inspector team. Simple tasks: handle directly. Read synapse/SKILL.md and roles/SKILL.md for team details.')
fi

# (e) Active Ralph loops: include phase/step info
if [ -d "$STATE_DIR/state" ]; then
  for state_dir in "$STATE_DIR/state"/*/; do
    [ -d "$state_dir" ] || continue
    if [ -f "${state_dir}ralph-state.md" ]; then
      ACTIVE=$(grep -o 'active: true' "${state_dir}ralph-state.md" 2>/dev/null)
      if [ -n "$ACTIVE" ]; then
        TASK_NAME=$(basename "$state_dir")
        PHASE=$(grep -o 'phase: [a-zA-Z]*' "${state_dir}ralph-state.md" 2>/dev/null | head -1 | sed 's/phase: //')
        STEP=$(grep -o 'step: [0-9]*' "${state_dir}ralph-state.md" 2>/dev/null | head -1 | sed 's/step: //')
        RALPH_INFO="[Symbiote] Ralph Loop '${TASK_NAME}' active"
        [ -n "$PHASE" ] && RALPH_INFO="${RALPH_INFO}, phase: ${PHASE}"
        [ -n "$STEP" ] && RALPH_INFO="${RALPH_INFO}, step: ${STEP}"
        CONTEXT_PARTS+=("$RALPH_INFO")
      fi
    fi
  done
fi

# Join and emit
if [ ${#CONTEXT_PARTS[@]} -gt 0 ]; then
  JOINED=""
  for part in "${CONTEXT_PARTS[@]}"; do
    if [ -n "$JOINED" ]; then
      JOINED="$JOINED | $part"
    else
      JOINED="$part"
    fi
  done
  emit_hook_context "$JOINED"
else
  emit_hook_continue
fi

# Record compaction event to harness-log.jsonl
if [ -d "$STATE_DIR" ]; then
  printf '{"v":2,"ts":"%s","type":"compaction","session_pid":"%s"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$$" >> "$STATE_DIR/harness-log.jsonl"
fi

exit 0
