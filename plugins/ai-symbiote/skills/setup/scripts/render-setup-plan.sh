#!/usr/bin/env bash
# ai-symbiote setup plan renderer.
#
# Author: JunyoungJung
# Date: 2026-04-15

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../hooks/scripts/lib/common.sh"

TEMPLATE_PATH="$SCRIPT_DIR/../templates/setup-plan.md"
PROJECT_ROOT="${SETUP_PLAN_PROJECT_ROOT:-}"
STATE_DIR="${SETUP_PLAN_STATE_DIR:-}"
MISSING_STATE_SUMMARY="${SETUP_PLAN_MISSING_STATE_SUMMARY:-}"
PLATFORM_SUMMARY="${SETUP_PLAN_PLATFORM_SUMMARY:-}"
CUSTOM_OPTIONAL_ITEM="${SETUP_PLAN_OPTIONAL_ITEM:-}"

usage() {
  echo "Usage: render-setup-plan.sh [--project-root PATH] [--state-dir PATH] [--missing-state TEXT] [--platform TEXT] [--optional-item TEXT]" >&2
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
    --missing-state)
      MISSING_STATE_SUMMARY="${2:-}"
      shift 2
      ;;
    --platform)
      PLATFORM_SUMMARY="${2:-}"
      shift 2
      ;;
    --optional-item)
      CUSTOM_OPTIONAL_ITEM="${2:-}"
      shift 2
      ;;
    *)
      usage
      exit 1
      ;;
  esac
done

if [ ! -f "$TEMPLATE_PATH" ]; then
  echo "[Setup] template not found: $TEMPLATE_PATH" >&2
  exit 1
fi

if [ -z "$PROJECT_ROOT" ]; then
  PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
fi

if [ -z "$STATE_DIR" ]; then
  STATE_DIR=$(get_state_dir)
fi

detect_missing_state_summary() {
  local missing=()
  [ -f "$STATE_DIR/manifest.json" ] || missing+=("manifest.json")
  [ -f "$STATE_DIR/context.md" ] || missing+=("context.md")
  [ -d "$STATE_DIR/state" ] || missing+=("state/")
  [ -d "$STATE_DIR/usage-data" ] || missing+=("usage-data/")

  if [ "${#missing[@]}" -eq 0 ]; then
    printf '%s' "none"
  else
    local joined="" item
    for item in "${missing[@]}"; do
      if [ -n "$joined" ]; then
        joined="${joined}, "
      fi
      joined="${joined}${item}"
    done
    printf '%s' "$joined"
  fi
}

detect_platform_summary() {
  local hints=()
  if command -v claude >/dev/null 2>&1; then
    hints+=("claude-cli")
  fi
  if command -v codex >/dev/null 2>&1 || [ -f "$HOME/.codex/config.toml" ]; then
    hints+=("codex")
  fi
  if [ -n "${CURSOR_PLUGIN_ROOT:-}" ] || [ -n "${CURSOR_PROJECT_DIR:-}" ]; then
    hints+=("cursor")
  fi

  if [ "${#hints[@]}" -eq 0 ]; then
    printf '%s' "unknown"
  else
    local joined="" item
    for item in "${hints[@]}"; do
      if [ -n "$joined" ]; then
        joined="${joined}, "
      fi
      joined="${joined}${item}"
    done
    printf '%s' "$joined"
  fi
}

if [ -z "$MISSING_STATE_SUMMARY" ]; then
  MISSING_STATE_SUMMARY=$(detect_missing_state_summary)
fi

if [ -z "$PLATFORM_SUMMARY" ]; then
  PLATFORM_SUMMARY=$(detect_platform_summary)
fi

if [ -z "$CUSTOM_OPTIONAL_ITEM" ]; then
  CUSTOM_OPTIONAL_ITEM="none"
fi

python3 - "$TEMPLATE_PATH" "$PROJECT_ROOT" "$MISSING_STATE_SUMMARY" "$PLATFORM_SUMMARY" "$CUSTOM_OPTIONAL_ITEM" <<'PY'
import sys
from pathlib import Path

template = Path(sys.argv[1]).read_text()
project_root = sys.argv[2]
missing_state = sys.argv[3]
platform_summary = sys.argv[4]
custom_optional = sys.argv[5]

rendered = (
    template
    .replace("{project_root}", project_root)
    .replace("{missing_state_summary}", missing_state)
    .replace("{platform_summary}", platform_summary)
    .replace("{project-specific optional item}", custom_optional)
)
print(rendered.rstrip())
PY
