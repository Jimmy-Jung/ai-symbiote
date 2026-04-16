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
SECURITY_SESSION_SUMMARY_LEVEL="auto"
MANIFEST_HELPER="$SCRIPT_DIR/../../skills/setup/scripts/manifest-defaults.sh"

if [ ! -f "$STATE_DIR/manifest.json" ]; then
  CONTEXT_PARTS+=("[Symbiote] manifest.json not found. Run setup in plan mode first to initialize the project. Use shared/skills/setup/scripts/begin-setup.sh for the entrypoint; without --approve it prints the Setup Plan via render-setup-plan.sh and setup-plan.md before any execution.")
else
  if [ -f "$MANIFEST_HELPER" ] && command -v python3 >/dev/null 2>&1; then
    NEEDS_MANIFEST_DEFAULTS=$(python3 - "$STATE_DIR/manifest.json" <<'PY'
import json
import sys
from pathlib import Path

manifest_path = Path(sys.argv[1])
try:
    data = json.loads(manifest_path.read_text())
except Exception:
    print("no")
    raise SystemExit(0)

agent_platforms = data.get("agentPlatforms")
security = data.get("security")
needs_defaults = (
    not isinstance(agent_platforms, list)
    or "claude" not in agent_platforms
    or "codex" not in agent_platforms
    or "cursor" not in agent_platforms
    or not isinstance(security, dict)
    or not security.get("sessionSummaryLevel")
)
print("yes" if needs_defaults else "no")
PY
)
    if [ "$NEEDS_MANIFEST_DEFAULTS" = "yes" ]; then
      bash "$MANIFEST_HELPER" --manifest "$STATE_DIR/manifest.json" >/dev/null 2>&1 || true
    fi
  fi
  # Inject project and stack summary from manifest.json into context
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
    SECURITY_SESSION_SUMMARY_LEVEL=$(json_nested_field "$MANIFEST_JSON" "security" "sessionSummaryLevel")
    [ -z "$SECURITY_SESSION_SUMMARY_LEVEL" ] && SECURITY_SESSION_SUMMARY_LEVEL="auto"

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

# Security: inject a prioritized, compact summary at SessionStart
if command -v python3 >/dev/null 2>&1; then
  SECURITY_SESSION_SUMMARY=$(python3 - "$STATE_DIR/security-baseline.json" "$STATE_DIR/security-log.jsonl" "$STATE_DIR/state/security-tool-recommendations.json" "$SECURITY_SESSION_SUMMARY_LEVEL" <<'PY'
import json
import sys
from pathlib import Path

baseline_path = Path(sys.argv[1])
log_path = Path(sys.argv[2])
recommendation_path = Path(sys.argv[3])
summary_level = (sys.argv[4] or "auto").strip().lower()

score = None
critical = high = medium = info = 0
scan_date = "unknown"
if baseline_path.exists():
    try:
        baseline = json.loads(baseline_path.read_text())
        summary = baseline.get("summary", {})
        score = baseline.get("score", 0)
        critical = summary.get("critical", 0)
        high = summary.get("high", 0)
        medium = summary.get("medium", 0)
        info = summary.get("info", 0)
        scan_date = baseline.get("scan_date", "unknown")
    except Exception:
        pass

blocked = 0
warned = 0
latest = None
if log_path.exists():
    import subprocess
    try:
        tail = subprocess.run(
            ["tail", "-200", str(log_path)],
            capture_output=True, text=True, timeout=5,
        )
        lines = tail.stdout.splitlines()
    except Exception:
        lines = []
    for raw in lines:
        raw = raw.strip()
        if not raw:
            continue
        try:
            item = json.loads(raw)
        except Exception:
            continue
        if item.get("type") != "security":
            continue
        action = item.get("action")
        if action == "blocked":
            blocked += 1
        elif action == "warned":
            warned += 1
        detail = item.get("category") or "unknown"
        source = item.get("file") or item.get("command") or item.get("rule_id") or "n/a"
        latest = f"{detail} @ {source}"

pending_preview = ""
pending_count = 0
if recommendation_path.exists():
    try:
        recommendation_data = json.loads(recommendation_path.read_text())
        items = recommendation_data.get("recommendations", [])
        names = [item.get("tool") or item.get("name") or "unknown" for item in items]
        pending_count = len(names)
        if names:
            pending_preview = ", ".join(names[:2])
            if len(names) > 2:
                pending_preview = f"{pending_preview} +{len(names) - 2} more"
    except Exception:
        pass

parts = []
if score is not None:
    parts.append(f"score={score}/100")
    parts.append(f"C:{critical} H:{high} M:{medium} I:{info}")

show_details = False
if summary_level == "verbose":
    show_details = True
elif summary_level == "quiet":
    show_details = False
else:
    show_details = bool(blocked or critical or high)

if show_details:
    if blocked or warned:
        activity = f"activity b={blocked} w={warned}"
        if latest:
            activity = f"{activity} latest={latest}"
        parts.append(activity)
    if pending_preview:
        parts.append(f"pending={pending_preview}")
elif score is not None:
    parts.append(f"last_scan={scan_date}")

if parts:
    print("[Security] " + " | ".join(parts) + ". Run /security status for details.")
PY
)
  [ -n "$SECURITY_SESSION_SUMMARY" ] && CONTEXT_PARTS+=("$SECURITY_SESSION_SUMMARY")
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
# Token optimization: when rules exceed 50 lines, inject only the most effective
# rules ranked by prevented count from harness-log.jsonl.
if [ -f "$STATE_DIR/harness-rules.md" ]; then
  RULES_CONTENT=$(cat "$STATE_DIR/harness-rules.md" 2>/dev/null)
  if [ -n "$RULES_CONTENT" ]; then
    RULES_LINES=$(echo "$RULES_CONTENT" | wc -l | tr -d ' ')
    if [ "$RULES_LINES" -le 50 ]; then
      CONTEXT_PARTS+=("[Harness Rules] $RULES_CONTENT")
    else
      # Summary mode: rank rules by prevented count and inject top 50 lines
      HARNESS_LOG="$STATE_DIR/harness-log.jsonl"
      if [ -f "$HARNESS_LOG" ]; then
        # Count prevented events per rule_id, sort descending
        RANKED_IDS=$(grep '"type":"rule_prevented"' "$HARNESS_LOG" 2>/dev/null | \
          grep -o '"rule_id":[0-9]*' | sed 's/"rule_id"://' | \
          sort | uniq -c | sort -rn | awk '{print $2}')
        if [ -n "$RANKED_IDS" ]; then
          # Build ranked rules content: rules ordered by effectiveness
          RANKED_RULES=""
          for rid in $RANKED_IDS; do
            RULE_LINE=$(grep -m1 "\\[Harness #${rid}\\]\\|\\[Seed #${rid}\\]" "$STATE_DIR/harness-rules.md" 2>/dev/null)
            [ -n "$RULE_LINE" ] && RANKED_RULES="${RANKED_RULES}${RULE_LINE}
"
          done
          # Append remaining rules not in prevented log
          while IFS= read -r line; do
            case "$line" in \[Harness\ \#*\]* | \[Seed\ \#*\]*)
              if ! echo "$RANKED_RULES" | grep -qF "$line" 2>/dev/null; then
                RANKED_RULES="${RANKED_RULES}${line}
"
              fi
              ;; esac
          done < "$STATE_DIR/harness-rules.md"
          SUMMARY_CONTENT=$(echo "$RANKED_RULES" | head -50)
        else
          # No prevented data: fall back to first 50 lines
          SUMMARY_CONTENT=$(head -50 "$STATE_DIR/harness-rules.md")
        fi
      else
        SUMMARY_CONTENT=$(head -50 "$STATE_DIR/harness-rules.md")
      fi
      OMITTED=$((RULES_LINES - 50))
      CONTEXT_PARTS+=("[Harness Rules (top 50 of ${RULES_LINES}, ranked by effectiveness)] $SUMMARY_CONTENT
[${OMITTED} additional rules omitted. Run /gc to prune unused rules.]")
      if [ "$RULES_LINES" -gt 300 ]; then
        CONTEXT_PARTS+=("[Harness] harness-rules.md has ${RULES_LINES} lines (recommended max 300). Run gc skill to prune.")
      fi
    fi
  fi
fi

# Synapse orchestrator routing rules injection
if [ -f "$STATE_DIR/manifest.json" ]; then
  SYNAPSE_ROUTING='[Synapse Orchestrator] You are the Synapse team leader of ai-symbiote. Analyze user requests and act according to the rules below.

## Mode Detection (keyword matching from user message)
- "until done","do not stop","keep going" → Skill(skill:"ai-symbiote:auto", args:"<task>")
- "max performance","parallel","autopilot" → Skill(skill:"ai-symbiote:auto", args:"<task> --mode parallel-max")
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
Inject code-accuracy, verify-loop, plan skills into each role.

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
  emit_hook_context "$JOINED"
else
  emit_hook_continue
fi

exit 0
