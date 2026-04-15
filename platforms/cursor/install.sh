#!/usr/bin/env bash
# ai-symbiote Cursor local installer
# Author: JunyoungJung
# Date: 2026-04-15
#
# Installs the Cursor bundle to ~/.cursor/plugins/local/ai-symbiote
# by building from source and symlinking into the Cursor plugins directory.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DIST_BUNDLE_NAME="cursor-symbiote"
PLUGIN_NAME="ai-symbiote"
CURSOR_PLUGINS_DIR="${CURSOR_PLUGINS_DIR:-$HOME/.cursor/plugins/local}"
TARGET_PLUGIN_DIR="$CURSOR_PLUGINS_DIR/$PLUGIN_NAME"

bash "$REPO_ROOT/scripts/build-cursor.sh"
SOURCE_PLUGIN_DIR="$REPO_ROOT/dist/$DIST_BUNDLE_NAME"

echo "[1/2] plugin bundle sync"
mkdir -p "$CURSOR_PLUGINS_DIR"
rsync -a --delete \
  --exclude '.git' \
  --exclude '.DS_Store' \
  "$SOURCE_PLUGIN_DIR/" "$TARGET_PLUGIN_DIR/"

echo "[2/2] install summary"
echo "plugin: $TARGET_PLUGIN_DIR"
echo
echo "next:"
echo "  1. Cursor를 재시작하여 플러그인을 로드합니다"
echo "  2. 또는 Command Palette > Developer: Reload Window"
