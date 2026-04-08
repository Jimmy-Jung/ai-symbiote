---
name: update
description: "Updates the ai-symbiote plugin to the latest version."
user-invocable: true
---

# Update -- Plugin Auto-Update

Pulls the ai-symbiote repository and reinstalls for the current platform.

## Workflow

### Step 1: Locate Repository

Searches for the ai-symbiote repository path in the following order:

```bash
# 1. Environment variable
echo "${AI_SYMBIOTE_REPO:-}"

# 2. Default paths
for candidate in ~/ai-symbiote-repo ~/Documents/GitHub/ai-symbiote; do
  [ -d "$candidate/.git" ] && echo "$candidate" && break
done
```

If the repository is not found:

```text
Cannot find the ai-symbiote repository.
To clone and install:
  git clone https://github.com/Jimmy-Jung/ai-symbiote.git ~/ai-symbiote-repo
  cd ~/ai-symbiote-repo && bash platforms/codex/install.sh
```

### Step 2: Fetch Latest Source

```bash
cd <repo-path>
git fetch origin
git pull origin main
```

If conflicts occur, report to the user and abort.

### Step 3: Detect Platform and Reinstall

Detects which platform the current session is running on:

- If `CLAUDE_PLUGIN_ROOT` environment variable exists -> Claude
- Otherwise -> Codex

**Claude:**

```bash
bash <repo-path>/scripts/build-claude.sh
```

After build, inform the user:

```text
Build complete. To update the plugin:
/plugin update ai-symbiote@ai-symbiote
```

**Codex:**

```bash
bash <repo-path>/platforms/codex/install.sh
```

### Step 4: Verify Version

```bash
# Check installed version
cat <repo-path>/platforms/codex/overlay/.codex-plugin/plugin.json | grep version
# or
cat <repo-path>/platforms/claude/overlay/.claude-plugin/plugin.json | grep version
```

Completion report:

```text
[Update] ai-symbiote update complete
- Version: {version}
- Platform: {claude/codex}
- Repository: {repo-path}
```
