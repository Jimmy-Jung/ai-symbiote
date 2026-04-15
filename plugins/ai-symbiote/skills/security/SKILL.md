---
name: security
description: "Project security baseline and audit workflow. Generates a security baseline, shows current score, and recommends deeper secret/static-analysis tooling when useful."
user-invocable: true
argument-hint: [scan | status | install-tools [--execute]]
allowed-tools: [Read, Bash, Glob, Grep]
---

# Security

Runs the Security OS Phase 2 core workflow for the current project.

This skill does three things:

- `scan` — run a full project security baseline scan, update `security-baseline.json`, and sync the security summary block in `context.md`
- `status` — read the latest baseline and show the current score, recent security activity, plus the top risks
- `install-tools` — read the pending security tool recommendations and hand off each tool to `cli-store` (`--execute` for real install)

State directory:

- `~/ai-symbiote/{slug}/security-baseline.json`
- `~/ai-symbiote/{slug}/security-log.jsonl`
- `~/ai-symbiote/{slug}/context.md`
- `~/ai-symbiote/{slug}/state/security-tool-recommendations.json`

## Command Resolution

Default to `status` when no argument is provided.

## Execution

Run the bundled script below via Bash:

```bash
PLUGIN_ROOT="${CURSOR_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-${CODEX_PLUGIN_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}}}"
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
source "$PLUGIN_ROOT/hooks/scripts/lib/common.sh"
STATE_DIR=$(ensure_state_dir)
CONTEXT_FILE="$STATE_DIR/context.md"

SUBCOMMAND="${1:-status}"

case "$SUBCOMMAND" in
  scan)
    bash "$PLUGIN_ROOT/skills/security/scripts/security-scan.sh" scan \
      --project-root "$PROJECT_ROOT" \
      --state-dir "$STATE_DIR" \
      --context-file "$CONTEXT_FILE" \
      --install-hints active
    ;;
  status)
    bash "$PLUGIN_ROOT/skills/security/scripts/security-scan.sh" status \
      --project-root "$PROJECT_ROOT" \
      --state-dir "$STATE_DIR" \
      --context-file "$CONTEXT_FILE"
    ;;
  install-tools)
    bash "$PLUGIN_ROOT/skills/security/scripts/security-scan.sh" install-tools \
      --project-root "$PROJECT_ROOT" \
      --state-dir "$STATE_DIR" \
      --context-file "$CONTEXT_FILE" \
      ${2:+$2}
    ;;
  *)
    echo "Usage: /security [scan|status|install-tools [--execute]]"
    exit 1
    ;;
esac
```

## Output Rules

- Put the score first.
- Show severity counts in one line.
- Show recent blocked/warned activity from `security-log.jsonl` when available.
- Show the top 3 risks only.
- If `gitleaks` or `semgrep` are not installed, recommend them after the scan.
- Persist pending tool recommendations so `/security status` can show them again later.
- `install-tools` defaults to dry-run. Add `--execute` only when you want real installation.
- Do not auto-fix anything in this skill. `/security fix` is intentionally out of scope for this release.
