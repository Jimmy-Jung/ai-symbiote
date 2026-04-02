#!/usr/bin/env bash
# Build all platform bundles.
# Author: JunyoungJung
# Date: 2026-04-02

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

bash "$REPO_ROOT/scripts/build-claude.sh"
bash "$REPO_ROOT/scripts/build-codex.sh"
