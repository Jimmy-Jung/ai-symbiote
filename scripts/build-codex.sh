#!/usr/bin/env bash
# Build Codex bundle from shared core + Codex overlay.
# Author: JunyoungJung
# Date: 2026-04-02

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST_DIR="$REPO_ROOT/dist/codex-symbiote"
SHARED_DIR="$REPO_ROOT/shared"
OVERLAY_DIR="$REPO_ROOT/platforms/codex/overlay"

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

for entry in skills hooks taskmaster messenger-bridge harness-seeds; do
  if [ -e "$SHARED_DIR/$entry" ]; then
    rsync -a --exclude '.gitkeep' "$SHARED_DIR/$entry/" "$DIST_DIR/$entry/"
  fi
done

rsync -a "$OVERLAY_DIR/" "$DIST_DIR/"

if [ ! -f "$DIST_DIR/.codex-plugin/plugin.json" ]; then
  echo "error: missing Codex plugin manifest" >&2
  exit 1
fi

echo "built: $DIST_DIR"
