#!/usr/bin/env python3
# Sync ai-symbiote version metadata across release artifacts.
# Author: JunyoungJung
# Date: 2026-04-08

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
VERSION_FILE = REPO_ROOT / "VERSION"
ARCHITECTURE_PATH = REPO_ROOT / "docs/ARCHITECTURE.md"
PLUGIN_NAME = "ai-symbiote"

JSON_TARGETS = {
    REPO_ROOT / "platforms/codex/overlay/.codex-plugin/plugin.json": "plugin_manifest",
    REPO_ROOT / "platforms/claude/overlay/.claude-plugin/plugin.json": "plugin_manifest",
    REPO_ROOT / "plugins/ai-symbiote/.claude-plugin/plugin.json": "plugin_manifest",
    REPO_ROOT / ".claude-plugin/marketplace.json": "claude_marketplace",
}


def load_version() -> str:
    version = VERSION_FILE.read_text(encoding="utf-8").strip()
    if not version:
        raise ValueError("VERSION file is empty")
    return version


def normalize_json(path: Path, version: str) -> str:
    data = json.loads(path.read_text(encoding="utf-8"))
    target_type = JSON_TARGETS[path]

    if target_type == "plugin_manifest":
        data["version"] = version
    elif target_type == "claude_marketplace":
        plugins = data.get("plugins", [])
        matched = False
        for entry in plugins:
            if isinstance(entry, dict) and entry.get("name") == PLUGIN_NAME:
                entry["version"] = version
                matched = True
                break
        if not matched:
            raise ValueError(f"{path} does not contain plugin entry {PLUGIN_NAME!r}")
    else:
        raise ValueError(f"Unsupported target type: {target_type}")

    return json.dumps(data, ensure_ascii=False, indent=2) + "\n"


def normalize_architecture(version: str) -> str:
    original = ARCHITECTURE_PATH.read_text(encoding="utf-8")
    updated, count = re.subn(
        r"^- 현재 버전: `[^`]+`$",
        f"- 현재 버전: `{version}`",
        original,
        flags=re.MULTILINE,
    )
    if count != 1:
        raise ValueError("docs/ARCHITECTURE.md current version line was not found exactly once")
    return updated


def sync_file(path: Path, expected: str, check_only: bool, mismatches: list[str]) -> None:
    current = path.read_text(encoding="utf-8")
    if current == expected:
        return

    if check_only:
        mismatches.append(str(path.relative_to(REPO_ROOT)))
        return

    path.write_text(expected, encoding="utf-8")
    print(f"updated: {path.relative_to(REPO_ROOT)}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Sync ai-symbiote release version files.")
    parser.add_argument("--check", action="store_true", help="Fail instead of writing when files are out of sync.")
    args = parser.parse_args()

    version = load_version()
    mismatches: list[str] = []

    for path in JSON_TARGETS:
        sync_file(path, normalize_json(path, version), args.check, mismatches)

    sync_file(ARCHITECTURE_PATH, normalize_architecture(version), args.check, mismatches)

    if mismatches:
        print("version sync mismatch:", file=sys.stderr)
        for path in mismatches:
            print(f" - {path}", file=sys.stderr)
        return 1

    print(f"version sync OK: {version}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
