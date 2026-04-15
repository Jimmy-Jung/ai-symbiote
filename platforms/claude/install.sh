#!/usr/bin/env bash
# ai-symbiote Claude local bundle installer
# Author: JunyoungJung
# Date: 2026-04-02

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TARGET_DIR="${CLAUDE_PLUGIN_BUNDLE_DIR:-$HOME/plugins/ai-symbiote}"

bash "$REPO_ROOT/scripts/build-claude.sh"

mkdir -p "$(dirname "$TARGET_DIR")"
rsync -a --delete "$REPO_ROOT/plugins/ai-symbiote/" "$TARGET_DIR/"

echo "bundle: $TARGET_DIR"
echo "marketplace root: $REPO_ROOT"
echo
echo "next:"
echo "  1. Claude에서 /plugin marketplace add $REPO_ROOT"
echo "  2. /plugin install ai-symbiote@ai-symbiote"
