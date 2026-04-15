# AI Symbiote

## Release rules

When bumping version, ALL of the following must be updated in a single commit:

1. `VERSION` — source of truth
2. `platforms/claude/overlay/.claude-plugin/plugin.json` — `"version"` field
3. `platforms/codex/overlay/.codex-plugin/plugin.json` — `"version"` field
4. `platforms/cursor/overlay/.cursor-plugin/plugin.json` — `"version"` field
5. `.claude-plugin/marketplace.json` — `"version"` field
6. `docs/02-아키텍처.md` — `현재 버전:` line
7. `CHANGELOG.md` — add `## [x.y.z] - YYYY-MM-DD` section with release notes

CI (`scripts/version_sync.py --check`) will fail if any of these are out of sync.
The release workflow also extracts notes from CHANGELOG.md, so a missing entry blocks the GitHub release.

After updating all files, run `bash scripts/build-all.sh` to sync bundles.

## Skill routing

When the user's request matches an available skill, ALWAYS invoke it using the Skill
tool as your FIRST action. Do NOT answer directly, do NOT use other tools first.
The skill has specialized workflows that produce better results than ad-hoc answers.

Key routing rules:
- Product ideas, "is this worth building", brainstorming → invoke office-hours
- Bugs, errors, "why is this broken", 500 errors → invoke investigate
- Ship, deploy, push, create PR → invoke ship
- QA, test the site, find bugs → invoke qa
- Code review, check my diff → invoke review
- Update docs after shipping → invoke document-release
- Weekly retro → invoke retro
- Design system, brand → invoke design-consultation
- Visual audit, design polish → invoke design-review
- Architecture review → invoke plan-eng-review
- Security audit, security scan, security status → invoke security
- Save progress, checkpoint, resume → invoke checkpoint
- Code quality, health check → invoke health
