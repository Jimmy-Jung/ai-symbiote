# Setup Plan Template

Author: JunyoungJung
Date: 2026-04-15

Use this template for the **first response** whenever `setup` is invoked.
Do not execute Bash commands before presenting this checklist and receiving approval.

```text
[Setup Plan]
1. Prepare state directories and baseline manifest/context
2. Check optional platform integrations
3. Detect project stack
4. Recommend/apply skills, CLI tools, and MCP servers
5. Generate or normalize manifest/context defaults

Optional items needing approval:
- project agent config generation (`.claude/`, `.codex/`, `.gitignore`)
- ralph workflow enable/check
- codex plugin install or integration check
- guided store selections (skill / cli / mcp)
- {project-specific optional item}

Current context:
- Project root: {project_root}
- Missing state: {missing_state_summary}
- Platform hints: {platform_summary}

Reply with approval before execution.
```
