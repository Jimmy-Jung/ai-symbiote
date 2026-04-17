#!/bin/bash
# ai-symbiote PreToolUse hook: Guard against dangerous shell commands and security risks.
# Blocks destructive git operations, security violations, and other risky commands.
#
# Author: JunyoungJung
# Date: 2026-04-14
#
# Principle: Silence on success — output ONLY when a command is blocked.
#
# Claude Code hook protocol:
#   stdin:  {"session_id":"...","cwd":"...","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"..."}}
#   stdout: {"continue":false,"permissionDecision":"deny","systemMessage":"..."} to block
#           (empty or {"continue":true}) to approve
#
# Security rules: SEC-001 ~ SEC-016
#   SEC-001~005: Secret Exposure
#   SEC-006~011: Dangerous Execution
#   SEC-012~016: Data Exfiltration

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

INPUT=$(read_stdin_safe)

COMMAND=$(json_nested_field "$INPUT" "tool_input" "command")

if [ -z "$COMMAND" ]; then
  exit 0
fi

BLOCKED=""
WORKAROUND=""
RULE_ID=""
RISK=""
CATEGORY=""

# ============================================================
# Destructive command guards (existing)
# ============================================================
case "$COMMAND" in
  *"git push --force"*|*"git push -f "*)
    BLOCKED="Force push destroys remote history."
    WORKAROUND="git push --force-with-lease"
    ;;
  *"git reset --hard"*)
    BLOCKED="Hard reset permanently deletes uncommitted changes."
    WORKAROUND="git stash"
    ;;
  *"rm -rf /"*|*"rm -rf ~"*|*"rm -rf /*"*)
    BLOCKED="Deleting system or home directory is blocked."
    WORKAROUND=""
    ;;
  *"git clean -fd"*)
    # Warn instead of block — commonly used for cache/build artifact cleanup
    STATE_DIR=$(get_state_dir)
    if [ -d "$STATE_DIR" ]; then
      NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
      ESC_CMD=$(json_escape "$COMMAND")
      printf '{"v":2,"ts":"%s","error_type":"guard_warned","command":"%s","workaround":"git clean -fdn (dry-run first)","session_pid":"%s"}\n' \
        "$NOW" "$ESC_CMD" "$PPID" >> "$STATE_DIR/harness-log.jsonl" 2>/dev/null
    fi
    emit_hook_notice "[Guard] Warning: git clean -fd permanently deletes untracked files. Consider git clean -fdn (dry-run) first."
    exit 0
    ;;
  *"git rebase -i"*|*"git rebase --interactive"*)
    BLOCKED="Interactive rebase is not supported in this terminal."
    WORKAROUND="git rebase <branch> (non-interactive)"
    ;;
  *"git add -i"*|*"git add --interactive"*)
    BLOCKED="Interactive add is not supported in this terminal."
    WORKAROUND="git add <specific-files>"
    ;;
  *"rm -rf .git"*)
    BLOCKED="Deleting git repository is blocked."
    WORKAROUND="Run manually if intentional"
    ;;
  *"chmod -R 777"*)
    # Legacy guard — now handled by SEC-007 below, but keep for ordering safety
    ;;
  *"sudo rm"*|*"sudo chmod"*|*"sudo chown"*)
    BLOCKED="Filesystem changes via sudo are blocked."
    WORKAROUND="Run manually if needed"
    ;;
esac

CMD_LOWER=$(printf '%s' "$COMMAND" | tr '[:upper:]' '[:lower:]')

# Pipe-to-shell check (existing)
if [ -z "$BLOCKED" ]; then
  if printf '%s' "$CMD_LOWER" | grep -qE '(curl|wget)\s.*\|\s*(ba)?sh'; then
    BLOCKED="Piping remote scripts directly is a security risk."
    WORKAROUND="Download file first, then review before executing"
  fi
fi

# ============================================================
# Security guards: SEC-001 ~ SEC-016
# ============================================================

# --- Secret Exposure (SEC-001 ~ SEC-005) ---

# SEC-001: echo/printf secrets to stdout
if [ -z "$BLOCKED" ]; then
  if printf '%s' "$CMD_LOWER" | grep -qE '(echo|printf)\s.*\b(api_key|api_secret|secret_key|access_key|private_key|auth_token|bearer)\b.*='; then
    BLOCKED="Secret value is being printed to stdout."
    WORKAROUND="Use a .env file or secret manager instead of printing secrets"
    RULE_ID="SEC-001"; RISK="HIGH"; CATEGORY="secret_exposure"
  fi
fi

# SEC-002: curl/wget with inline token in Authorization header or URL
if [ -z "$BLOCKED" ]; then
  if printf '%s' "$COMMAND" | grep -qE "(curl|wget)\s.*(-H\s*['\"]Authorization:\s*(Bearer|Basic|Token)\s+[A-Za-z0-9_\.\-]{20,})"; then
    BLOCKED="Authorization token is exposed inline in the command."
    WORKAROUND="Store the token in an environment variable: -H \"Authorization: Bearer \$TOKEN\""
    RULE_ID="SEC-002"; RISK="HIGH"; CATEGORY="secret_exposure"
  fi
fi

# SEC-003: git add .env files
if [ -z "$BLOCKED" ]; then
  if printf '%s' "$COMMAND" | grep -qE 'git\s+add\s+.*\.env(\s|$|\.)'; then
    BLOCKED=".env file should not be committed to git."
    WORKAROUND="Add .env to .gitignore and use .env.example for templates"
    RULE_ID="SEC-003"; RISK="CRITICAL"; CATEGORY="secret_exposure"
  fi
fi

# SEC-004: base64 encoded secret assignment
if [ -z "$BLOCKED" ]; then
  if printf '%s' "$CMD_LOWER" | grep -qE '(export\s+)?(api_key|secret|token|password|credentials)\s*=\s*.*base64'; then
    BLOCKED="Base64-encoded secret detected in environment variable."
    WORKAROUND="Use a secret manager or .env file, not inline base64"
    RULE_ID="SEC-004"; RISK="HIGH"; CATEGORY="secret_exposure"
  fi
fi

# SEC-005: export secrets directly in shell
if [ -z "$BLOCKED" ]; then
  if printf '%s' "$COMMAND" | grep -qE 'export\s+(AWS_SECRET_ACCESS_KEY|AWS_SECRET_KEY|GITHUB_TOKEN|OPENAI_API_KEY|ANTHROPIC_API_KEY|DATABASE_URL|DB_PASSWORD|PRIVATE_KEY)\s*=\s*["\x27]?[A-Za-z0-9_\.\-/+=]{8,}'; then
    BLOCKED="Secret is being exported directly to shell environment."
    WORKAROUND="Use a .env file or direnv, not inline export with real values"
    RULE_ID="SEC-005"; RISK="CRITICAL"; CATEGORY="secret_exposure"
  fi
fi

# --- Dangerous Execution (SEC-006 ~ SEC-011) ---

# SEC-006: eval/exec with remote content
if [ -z "$BLOCKED" ]; then
  if printf '%s' "$CMD_LOWER" | grep -qE 'eval\s+"\$\((curl|wget)'; then
    BLOCKED="eval with remote content is a code injection risk."
    WORKAROUND="Download, review, then source the script"
    RULE_ID="SEC-006"; RISK="CRITICAL"; CATEGORY="dangerous_execution"
  fi
fi

# SEC-007: chmod 777 — block recursive, warn on single file
if [ -z "$BLOCKED" ]; then
  if printf '%s' "$COMMAND" | grep -qE 'chmod\s+-R\s+777\b'; then
    BLOCKED="chmod -R 777 recursively grants full permissions to everyone."
    WORKAROUND="chmod -R 755 for directories, chmod -R 644 for files"
    RULE_ID="SEC-007"; RISK="HIGH"; CATEGORY="dangerous_execution"
  elif printf '%s' "$COMMAND" | grep -qE 'chmod\s+777\b'; then
    # Single file chmod 777 — warn instead of block
    SEC_WARN="yes"
  fi
fi

# SEC-008: npm/pip install with unsafe flags — block unsafe-perm/trusted-host, warn on no-audit
if [ -z "$BLOCKED" ]; then
  if printf '%s' "$CMD_LOWER" | grep -qE '(npm\s+install|pip\s+install)\s.*--(unsafe-perm|trusted-host)'; then
    BLOCKED="Package install with security bypass flags detected."
    WORKAROUND="Remove the unsafe flag and fix the underlying issue"
    RULE_ID="SEC-008"; RISK="MEDIUM"; CATEGORY="dangerous_execution"
  elif printf '%s' "$CMD_LOWER" | grep -qE '(npm\s+install|pip\s+install)\s.*--no-audit'; then
    # --no-audit is common in CI — warn instead of block
    SEC_WARN="yes"
  fi
fi

# SEC-009: docker run --privileged
if [ -z "$BLOCKED" ]; then
  if printf '%s' "$CMD_LOWER" | grep -qE 'docker\s+run\s.*--privileged'; then
    BLOCKED="docker --privileged gives the container full host access."
    WORKAROUND="Use specific --cap-add flags instead of --privileged"
    RULE_ID="SEC-009"; RISK="HIGH"; CATEGORY="dangerous_execution"
  fi
fi

# SEC-010: binding dangerous ports to 0.0.0.0
if [ -z "$BLOCKED" ]; then
  if printf '%s' "$COMMAND" | grep -qE '0\.0\.0\.0:(22|3306|5432|6379|27017)\b'; then
    BLOCKED="Sensitive service port bound to all interfaces (0.0.0.0)."
    WORKAROUND="Bind to 127.0.0.1 instead of 0.0.0.0 for local development"
    RULE_ID="SEC-010"; RISK="HIGH"; CATEGORY="dangerous_execution"
  fi
fi

# SEC-011: inline code execution with network access
if [ -z "$BLOCKED" ]; then
  if printf '%s' "$CMD_LOWER" | grep -qE '(python3?\s+-c|node\s+-e|ruby\s+-e)\s.*\b(urllib|requests|http|fetch|net|socket)\b'; then
    BLOCKED="Inline code execution with network access detected."
    WORKAROUND="Write to a file first, review, then execute"
    RULE_ID="SEC-011"; RISK="MEDIUM"; CATEGORY="dangerous_execution"
  fi
fi

# --- Data Exfiltration (SEC-012 ~ SEC-016) ---

# SEC-012: archiving sensitive files
if [ -z "$BLOCKED" ]; then
  if printf '%s' "$CMD_LOWER" | grep -qE '(tar|zip|7z)\s.*\.(env|ssh|credentials|pem|key)\b'; then
    BLOCKED="Archiving sensitive files (.env, .ssh, credentials, keys)."
    WORKAROUND="Exclude sensitive files from the archive"
    RULE_ID="SEC-012"; RISK="HIGH"; CATEGORY="data_exfiltration"
  fi
fi

# SEC-013: scp/rsync sending config files externally
if [ -z "$BLOCKED" ]; then
  if printf '%s' "$CMD_LOWER" | grep -qE '(scp|rsync)\s.*\.(env|pem|key|credentials)\b.*@'; then
    BLOCKED="Transferring sensitive files to external host."
    WORKAROUND="Verify the destination and consider encrypting the file first"
    RULE_ID="SEC-013"; RISK="HIGH"; CATEGORY="data_exfiltration"
  fi
fi

# SEC-014: dumping environment variables to file — warn instead of block (common for debugging)
if [ -z "$BLOCKED" ]; then
  if printf '%s' "$CMD_LOWER" | grep -qE '(^|\s)(env|printenv|set)\s*>\s'; then
    SEC_WARN="yes"
  fi
fi

# SEC-015: git push with staged .env or secret files
if [ -z "$BLOCKED" ]; then
  if printf '%s' "$CMD_LOWER" | grep -qE 'git\s+push\b'; then
    # Check if .env or sensitive files are staged
    STAGED_SECRETS=$(cd "$(printf '%s' "$INPUT" | grep -o '"cwd":"[^"]*"' | sed 's/"cwd":"//;s/"$//' 2>/dev/null || pwd)" 2>/dev/null && \
      git diff --cached --name-only 2>/dev/null | grep -iE '\.(env|pem|key)$|credentials|\.secret' | head -1)
    if [ -n "$STAGED_SECRETS" ]; then
      BLOCKED="Staged files contain potential secrets: $STAGED_SECRETS"
      WORKAROUND="git reset HEAD <file> to unstage, then add to .gitignore"
      RULE_ID="SEC-015"; RISK="CRITICAL"; CATEGORY="data_exfiltration"
    fi
  fi
fi

# SEC-016: netcat sending data externally
if [ -z "$BLOCKED" ]; then
  if printf '%s' "$CMD_LOWER" | grep -qE '(nc|ncat|netcat)\s.*\b[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\b'; then
    BLOCKED="Sending data to external host via netcat."
    WORKAROUND="Use curl or a proper HTTP client for external communication"
    RULE_ID="SEC-016"; RISK="MEDIUM"; CATEGORY="data_exfiltration"
  fi
fi

# ============================================================
# Soft warnings (continue=true, command is NOT blocked)
# ============================================================
if [ -z "$BLOCKED" ] && [ "${SEC_WARN:-}" = "yes" ]; then
  # Determine what to warn about
  WARN_MSG=""
  if printf '%s' "$COMMAND" | grep -qE 'chmod\s+777\b'; then
    WARN_MSG="chmod 777 grants full permissions. Consider chmod 755 instead."
  elif printf '%s' "$CMD_LOWER" | grep -qF -- '--no-audit'; then
    WARN_MSG="--no-audit skips vulnerability checks. Run npm audit separately."
  elif printf '%s' "$CMD_LOWER" | grep -qE '(env|printenv|set)\s*>\s'; then
    WARN_MSG="Environment dump may contain secrets. Delete the file after debugging."
  fi
  if [ -n "$WARN_MSG" ]; then
    emit_hook_notice "[Guard] Warning: ${WARN_MSG}"
    # Record warning event
    STATE_DIR=$(get_state_dir)
    if [ -d "$STATE_DIR" ]; then
      NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
      ESC_CMD=$(json_escape "$COMMAND")
      ESCAPED_WARN=$(json_escape "$WARN_MSG")
      printf '{"v":2,"ts":"%s","error_type":"guard_warned","command":"%s","warning":"%s","session_pid":"%s"}\n' \
        "$NOW" "$ESC_CMD" "$ESCAPED_WARN" "$PPID" >> "$STATE_DIR/harness-log.jsonl" 2>/dev/null
    fi
  fi
  exit 0
fi

# ============================================================
# Output blocked result
# ============================================================
if [ -n "$BLOCKED" ]; then
  # Build message: security rules include rule ID and risk level
  if [ -n "$RULE_ID" ]; then
    if [ -n "$WORKAROUND" ]; then
      MSG="[${RULE_ID}/${RISK}] ${BLOCKED} Alternative: ${WORKAROUND}."
    else
      MSG="[${RULE_ID}/${RISK}] ${BLOCKED}"
    fi
  else
    if [ -n "$WORKAROUND" ]; then
      MSG="Blocked: ${BLOCKED} Workaround: ${WORKAROUND}. Note: verify this matches your intent."
    else
      MSG="Blocked: ${BLOCKED}"
    fi
  fi
  emit_hook_block "[Guard] ${MSG}"

  # Record blocked event
  STATE_DIR=$(get_state_dir)
  if [ -d "$STATE_DIR" ]; then
    NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    ESC_CMD=$(json_escape "$COMMAND")
    ESC_WA=$(json_escape "$WORKAROUND")
    if [ -n "$RULE_ID" ]; then
      # Security event → security-log.jsonl
      SECURITY_LOG="$STATE_DIR/security-log.jsonl"
      printf '{"v":2,"ts":"%s","type":"security","category":"%s","rule_id":"%s","risk":"%s","command":"%s","action":"blocked","session_pid":"%s"}\n' \
        "$NOW" "$CATEGORY" "$RULE_ID" "$RISK" "$ESC_CMD" "$PPID" >> "$SECURITY_LOG" 2>/dev/null
      # Also record to harness-log for unified view
      HARNESS_LOG="$STATE_DIR/harness-log.jsonl"
      printf '{"v":2,"ts":"%s","error_type":"security_blocked","rule_id":"%s","risk":"%s","command":"%s","workaround":"%s","session_pid":"%s"}\n' \
        "$NOW" "$RULE_ID" "$RISK" "$ESC_CMD" "$ESC_WA" "$PPID" >> "$HARNESS_LOG" 2>/dev/null
    else
      # Destructive command event → harness-log.jsonl (existing behavior)
      HARNESS_LOG="$STATE_DIR/harness-log.jsonl"
      printf '{"v":2,"ts":"%s","error_type":"guard_blocked","command":"%s","workaround":"%s","session_pid":"%s"}\n' \
        "$NOW" "$ESC_CMD" "$ESC_WA" "$PPID" >> "$HARNESS_LOG" 2>/dev/null
    fi
  fi
  exit 0
fi

exit 0
