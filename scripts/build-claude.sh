#!/usr/bin/env bash
# Build Claude bundle from shared core + Claude overlay.
# Author: JunyoungJung
# Date: 2026-04-02

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST_DIR="$REPO_ROOT/dist/claude-symbiote"
PLUGIN_DIR="$REPO_ROOT/plugins/ai-symbiote"
SHARED_DIR="$REPO_ROOT/shared"
OVERLAY_DIR="$REPO_ROOT/platforms/claude/overlay"

build_bundle() {
  local target_dir="$1"

  rm -rf "$target_dir"
  mkdir -p "$target_dir"

  for entry in skills hooks taskmaster messenger-bridge; do
    if [ -e "$SHARED_DIR/$entry" ]; then
      rsync -a --exclude '.gitkeep' "$SHARED_DIR/$entry/" "$target_dir/$entry/"
    fi
  done

  rsync -a "$OVERLAY_DIR/" "$target_dir/"

  if [ ! -f "$target_dir/.claude-plugin/plugin.json" ]; then
    echo "error: missing Claude plugin manifest in $target_dir" >&2
    exit 1
  fi
}

build_bundle "$PLUGIN_DIR"
build_bundle "$DIST_DIR"

echo "built: $PLUGIN_DIR"
echo "built: $DIST_DIR"
