#!/bin/bash
# ai-symbiote SessionStart hook: Check project bootstrap status.
# Checks ~/ai-symbiote/{slug}/ for manifest and interrupted Ralph loops.
#
# Principle: Silence on success — only output context/synapse injection and
#            warnings. No extra messages when everything is normal.
#
# Codex hook protocol:
#   stdout: {"continue":true,"systemMessage":"..."} for context injection

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

cat > /dev/null

STATE_DIR=$(get_state_dir)
CONTEXT_PARTS=()

if [ ! -f "$STATE_DIR/manifest.json" ]; then
  CONTEXT_PARTS+=("[Symbiote] manifest.json not found. Run setup to initialize the project.")
fi

# Harness: analyze previous sessions for rule_prevented before cleanup
if [ -d "$STATE_DIR" ] && [ -f "$STATE_DIR/harness-rules.md" ]; then
  HARNESS_LOG="$STATE_DIR/harness-log.jsonl"
  NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  for sess_dir in "$STATE_DIR"/session-*/; do
    [ -d "$sess_dir" ] || continue
    SESS_PID=$(basename "$sess_dir" | sed 's/session-//')
    # Only analyze dead sessions (not the current one)
    if [ -n "$SESS_PID" ] && ! kill -0 "$SESS_PID" 2>/dev/null; then
      EVENTS_FILE="$sess_dir/events.jsonl"
      if [ -f "$EVENTS_FILE" ]; then
        # For each harness/seed rule, check if covered files were edited without errors
        while IFS= read -r rule_line; do
          RULE_ID=$(printf '%s' "$rule_line" | grep -o '#[0-9]*' | head -1 | tr -d '#')
          [ -z "$RULE_ID" ] && continue
          # Extract file hint from rule (basename mentioned in rule text)
          RULE_FILE=$(printf '%s' "$rule_line" | grep -o '[A-Za-z0-9_-]*\.[a-z]*' | head -1)
          [ -z "$RULE_FILE" ] && continue
          # Check if this file was edited in the session
          EDITED=$(grep -c "\"file\":\"[^\"]*$RULE_FILE\"" "$EVENTS_FILE" 2>/dev/null) || EDITED=0
          if [ "$EDITED" -gt 0 ]; then
            # Check if there were errors on this file
            ERRORS=$(grep "\"file\":\"[^\"]*$RULE_FILE\"" "$EVENTS_FILE" 2>/dev/null | grep -c '"status":"error"' 2>/dev/null) || ERRORS=0
            if [ "$ERRORS" -eq 0 ]; then
              printf '{"v":2,"ts":"%s","type":"rule_prevented","rule_id":%s,"file":"%s","session_pid":"%s"}\n' \
                "$NOW" "$RULE_ID" "$(printf '%s' "$RULE_FILE" | tr -d '"')" "$SESS_PID" >> "$HARNESS_LOG" 2>/dev/null
            fi
          fi
        done < <(grep '^\[Harness #\|^\[Seed #' "$STATE_DIR/harness-rules.md" 2>/dev/null)
      fi
      # Clean up stale session
      rm -rf "$sess_dir" 2>/dev/null
    fi
  done
fi

# --- Auto-GC: remove duplicate and stale harness rules on SessionStart ---
if [ -f "$STATE_DIR/harness-rules.md" ] && grep -q '^\[Harness #' "$STATE_DIR/harness-rules.md" 2>/dev/null; then
  _GC_CTX="$STATE_DIR/harness-rules.md"
  _GC_LOG="$STATE_DIR/harness-log.jsonl"
  _GC_TMP="$_GC_CTX.autogc.tmp"
  _GC_REMOVED=0
  _GC_SEEN=$(mktemp 2>/dev/null || echo "/tmp/harness-gc-seen-$$")
  _THIRTY_DAYS=$(date -u -v-30d +%Y-%m-%dT 2>/dev/null || date -u -d '30 days ago' +%Y-%m-%dT 2>/dev/null || echo "")

  while IFS= read -r _gc_line || [ -n "$_gc_line" ]; do
    if printf '%s' "$_gc_line" | grep -q '^\[Harness #'; then
      # Dedup: extract rule text and skip if already seen
      _gc_text=$(printf '%s' "$_gc_line" | sed 's/^\[Harness #[0-9]*\] //' | sed 's/ (auto-generated [0-9-]*)$//')
      if grep -qxF "$_gc_text" "$_GC_SEEN" 2>/dev/null; then
        _GC_REMOVED=$((_GC_REMOVED + 1))
        continue
      fi
      printf '%s\n' "$_gc_text" >> "$_GC_SEEN"

      # Stale: skip if created 30+ days ago with no recent activity
      if [ -n "$_THIRTY_DAYS" ] && [ -f "$_GC_LOG" ]; then
        _gc_rid=$(printf '%s' "$_gc_line" | grep -o '#[0-9]*' | head -1 | tr -d '#')
        if [ -n "$_gc_rid" ]; then
          _gc_created=$(grep '"type":"rule_created"' "$_GC_LOG" 2>/dev/null | \
            grep "\"rule_id\":$_gc_rid[,}]" 2>/dev/null | \
            grep -o '"ts":"[^"]*"' 2>/dev/null | head -1 | sed 's/"ts":"//;s/"//')
          _gc_prevented=$(grep '"type":"rule_prevented"' "$_GC_LOG" 2>/dev/null | \
            grep "\"rule_id\":$_gc_rid[,}]" 2>/dev/null | \
            tail -1 | grep -o '"ts":"[^"]*"' 2>/dev/null | sed 's/"ts":"//;s/"//')
          _gc_latest="${_gc_prevented:-$_gc_created}"
          if [ -n "$_gc_latest" ] && [[ "$_gc_latest" < "$_THIRTY_DAYS" ]]; then
            _GC_REMOVED=$((_GC_REMOVED + 1))
            continue
          fi
        fi
      fi
    fi
    printf '%s\n' "$_gc_line"
  done < "$_GC_CTX" > "$_GC_TMP"

  rm -f "$_GC_SEEN" 2>/dev/null

  if [ "$_GC_REMOVED" -gt 0 ]; then
    # Squeeze consecutive blank lines and apply
    cat -s "$_GC_TMP" > "$_GC_CTX" 2>/dev/null || mv "$_GC_TMP" "$_GC_CTX" 2>/dev/null
    rm -f "$_GC_TMP" 2>/dev/null
    CONTEXT_PARTS+=("[Harness] Auto-GC: removed ${_GC_REMOVED} duplicate/stale rules from harness-rules.md.")
  else
    rm -f "$_GC_TMP" 2>/dev/null
  fi
fi

# Harness: notify about auto-generated rules from previous sessions
if [ -f "$STATE_DIR/harness-log.jsonl" ]; then
  RECENT_RULES=$(grep '"type":"rule_created"' "$STATE_DIR/harness-log.jsonl" 2>/dev/null | tail -3)
  if [ -n "$RECENT_RULES" ]; then
    RULE_COUNT=$(grep -c '"type":"rule_created"' "$STATE_DIR/harness-log.jsonl" 2>/dev/null) || RULE_COUNT=0
    CONTEXT_PARTS+=("[Harness] ${RULE_COUNT} auto-generated harness rules exist. Run stats to view harness evolution metrics.")
  fi

  # Harness: recommend gc when log exceeds 100 lines
  LOG_LINES=$(wc -l < "$STATE_DIR/harness-log.jsonl" 2>/dev/null | tr -d ' ') || LOG_LINES=0
  if [ "$LOG_LINES" -ge 100 ]; then
    CONTEXT_PARTS+=("[Harness] harness-log.jsonl has ${LOG_LINES} lines. Run gc skill to prune unused rules and old logs.")
  fi
fi

if [ -d "$STATE_DIR/state" ]; then
  for state_dir in "$STATE_DIR/state"/*/; do
    [ -d "$state_dir" ] || continue
    if [ -f "${state_dir}ralph-state.md" ]; then
      ACTIVE=$(grep -o 'active: true' "${state_dir}ralph-state.md" 2>/dev/null)
      if [ -n "$ACTIVE" ]; then
        TASK_NAME=$(basename "$state_dir")
        CONTEXT_PARTS+=("[Symbiote] Ralph Loop '${TASK_NAME}' was interrupted. Resume via ralph or clean up with the clean workflow.")
      fi
    fi
  done
fi

if [ -f "$STATE_DIR/context.md" ]; then
  CONTEXT_CONTENT=$(cat "$STATE_DIR/context.md" 2>/dev/null)
  if [ -n "$CONTEXT_CONTENT" ]; then
    CONTEXT_PARTS+=("[Symbiote Context] $CONTEXT_CONTENT")
  fi
fi

# Harness rules: inject from separate file (Seed + Harness rules)
if [ -f "$STATE_DIR/harness-rules.md" ]; then
  RULES_CONTENT=$(cat "$STATE_DIR/harness-rules.md" 2>/dev/null)
  if [ -n "$RULES_CONTENT" ]; then
    CONTEXT_PARTS+=("[Harness Rules] $RULES_CONTENT")
    RULES_LINES=$(echo "$RULES_CONTENT" | wc -l | tr -d ' ')
    if [ "$RULES_LINES" -gt 300 ]; then
      CONTEXT_PARTS+=("[Harness] harness-rules.md exceeded ${RULES_LINES} lines (recommended max 300). Run gc skill to prune unused rules.")
    fi
  fi
fi

# Synapse orchestrator routing rules injection
if [ -f "$STATE_DIR/manifest.json" ]; then
  SYNAPSE_ROUTING='[Synapse Orchestrator] You are the Synapse team leader of ai-symbiote. Analyze user requests and act according to the rules below.

## Mode Detection (keyword matching from user message)
- "until done","do not stop","keep going" → Skill(skill:"ai-symbiote:auto-loop", args:"<task>")
- "max performance","parallel","autopilot" → Skill(skill:"ai-symbiote:autopilot", args:"<task>")
- "deep analysis","deep search","analyze deeply" → Skill(skill:"ai-symbiote:analyze", args:"<target>")
- "code review","review this" → Skill(skill:"ai-symbiote:review")
- "make a plan","plan" → Skill(skill:"ai-symbiote:plan", args:"<task>")
- "research","investigate" → analysis team + Researcher
- "requirements","PRD","feature spec" → Skill(skill:"ralph-skills:prd")
- "update project","evolve" → Skill(skill:"ai-symbiote:evolve")
- "commit" → Skill(skill:"ai-symbiote:git-commit")

## Team-based Execution (medium+ tasks)
Even without explicit keywords, form a team for medium+ scope:
1. Scout(Explore, sonnet) x1-2 for codebase exploration
2. Architect(Plan, opus) x1 for implementation planning
3. Builder(general-purpose, sonnet) x1-3 for implementation
4. Inspector(general-purpose, sonnet) x1 for verification
Filesystem contract: ~/ai-symbiote/{slug}/state/{task-folder}/ stores ralph-state.md, team-manifest.json, results/*.result.md

## Task Scope Assessment
- simple: 1-2 files, single function change → handle directly (no team needed)
- medium: 3-5 files, cross-module work → Scout + Builder + Inspector
- large: 5+ files, architecture change → full team (Scout → Architect → Builder → Inspector)

## Reference Skills
When forming teams, Read roles/SKILL.md and team-templates/SKILL.md for prompt templates and output contracts.
Inject code-accuracy, verify-loop, planning skills into each role.

## Principles
- Respond in the language the user uses
- Handle simple tasks directly without team formation
- Pass subagent results via filesystem
- Escalate on: maxIterations reached, same error 3 times, destructive changes require user confirmation'
  CONTEXT_PARTS+=("$SYNAPSE_ROUTING")
fi

# Messenger bridge: check pending commands
MESSENGER_CMD_DIR="$STATE_DIR/messenger/commands"
if [ -d "$MESSENGER_CMD_DIR" ]; then
  for cmd_file in "$MESSENGER_CMD_DIR"/*.json; do
    [ -f "$cmd_file" ] || continue
    CMD_STATUS=$(json_field "$(cat "$cmd_file")" "status")
    if [ "$CMD_STATUS" = "pending" ]; then
      CMD_TYPE=$(json_field "$(cat "$cmd_file")" "command")
      CMD_ARGS=""
      if command -v jq >/dev/null 2>&1; then
        CMD_ARGS=$(jq -r '.args | to_entries | map(.value) | join(", ")' "$cmd_file" 2>/dev/null)
      else
        CMD_ARGS=$(grep -o '"instruction"[[:space:]]*:[[:space:]]*"[^"]*"' "$cmd_file" | head -1 | sed 's/.*"instruction"[[:space:]]*:[[:space:]]*"//' | sed 's/"$//')
        [ -z "$CMD_ARGS" ] && CMD_ARGS=$(grep -o '"task"[[:space:]]*:[[:space:]]*"[^"]*"' "$cmd_file" | head -1 | sed 's/.*"task"[[:space:]]*:[[:space:]]*"//' | sed 's/"$//')
      fi
      ESCAPED_CMD=$(json_escape "[Messenger] Command received: ${CMD_TYPE} - ${CMD_ARGS}")
      CONTEXT_PARTS+=("$ESCAPED_CMD")
    fi
  done
fi

# Messenger bridge: check pending approval responses
MESSENGER_APR_DIR="$STATE_DIR/messenger/approvals"
if [ -d "$MESSENGER_APR_DIR" ]; then
  for resp_file in "$MESSENGER_APR_DIR"/*_response.json; do
    [ -f "$resp_file" ] || continue
    RESP_ID=$(json_field "$(cat "$resp_file")" "id")
    RESP_DECISION=$(json_field "$(cat "$resp_file")" "decision")
    RESP_COMMENT=$(json_field "$(cat "$resp_file")" "comment")
    CONTEXT_PARTS+=("[Messenger] Approval response received: ${RESP_ID} - decision: ${RESP_DECISION}, comment: ${RESP_COMMENT}")
  done
fi

if [ ${#CONTEXT_PARTS[@]} -gt 0 ]; then
  JOINED=""
  for part in "${CONTEXT_PARTS[@]}"; do
    if [ -n "$JOINED" ]; then
      JOINED="$JOINED | $part"
    else
      JOINED="$part"
    fi
  done
  ESCAPED=$(json_escape "$JOINED")
  printf '{"continue":true,"systemMessage":"%s"}\n' "$ESCAPED"
else
  printf '{"continue":true}\n'
fi

exit 0
