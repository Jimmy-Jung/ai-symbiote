---
name: mcp-store
description: "Recommends and installs MCP servers matching your project stack. Browses the awesome-mcp-servers catalog (530+) by framework, service, and domain. Triggers on: mcp recommendation, mcp install, mcp store, recommend mcp, mcp discovery."
user-invocable: true
argument-hint: [search query | --auto | --list <category> | --update]
allowed-tools: [Read, Write, Bash, Glob, Grep, Agent]
---

# MCP Store

Recommends and installs MCP (Model Context Protocol) servers matching your project stack.
Source: [wong2/awesome-mcp-servers](https://github.com/wong2/awesome-mcp-servers) (530+ servers)

## Catalog

The MCP-to-stack recommendation mapping is stored in `skills/mcp-store/catalog.json` under the current plugin root.

Catalog structure:
- `stacks`: Recommendations by language/framework (nextjs, react, react-native, swift, python, typescript, rust, go, java, dotnet)
- `services`: Recommendations by service (supabase, neon, stripe, cloudflare, sentry, github, postgres, sqlite, mongodb, notion, linear, slack, docker, grafana, vercel, terraform, aws)
- `domains`: Recommendations by domain (search, database, testing, monitoring, devops, ai, security, web-scraping, productivity, core)

Each catalog entry contains:
```json
{
  "id": "unique-mcp-id",
  "name": "Display Name",
  "repo": "owner/repo",
  "transport": "stdio|http",
  "command": "npx or URL",
  "args": ["command", "arguments"],
  "env": ["REQUIRED_ENV_VARS"],
  "category": "category-tag",
  "description": "Brief description"
}
```

## Usage Modes

### Mode 1: Auto Recommend (`--auto`)

Reads `~/ai-symbiote/{slug}/manifest.json` and auto-recommends based on detected stack.

Workflow:
1. Read `project.languages`, `stack.frameworks`, `stack.packageManager` from manifest.json
2. Match against `stacks` in catalog.json by language/framework
3. Scan project dependency files to detect services:
   - `@supabase/supabase-js` -> supabase recommendation
   - `stripe` -> stripe recommendation
   - `@sentry/*` -> sentry recommendation
   - `@cloudflare/*` -> cloudflare recommendation
   - `@neondatabase/*` -> neon recommendation
   - `firebase` or `firebase-admin` -> firebase recommendation
   - `@notionhq/*` -> notion recommendation
   - `@linear/sdk` -> linear recommendation
   - `pg` or `postgres` -> postgres recommendation
   - `better-sqlite3` or `sqlite3` -> sqlite recommendation
   - `mongodb` or `mongoose` -> mongodb recommendation
   - `@playwright/test` -> playwright recommendation
   - `*.tf` files -> terraform recommendation
   - `Dockerfile` -> docker recommendation
4. **CLI deduplication**: Check `~/ai-symbiote/{slug}/state/cli-covered-mcps.json` for MCP IDs already covered by CLI tools (produced by cli-store). Remove those IDs from the recommendation list and mark them as: `~~{name} MCP~~ — covered by CLI`
5. Check already installed MCPs:
   ```bash
   claude mcp list 2>/dev/null
   ```
6. Display matched MCP list with install status (excluding CLI-covered entries)
7. Install when user selects by number

Output format:
```
[MCP Store] Recommended MCP servers based on project analysis:

Frameworks:
  1. Context7 (upstash/context7-mcp) — Up-to-date documentation for any prompt
  2. Playwright (microsoft/playwright-mcp) — Browser automation and testing

Services:
  3. Supabase (supabase-community/supabase-mcp) — Database, auth, edge functions
     ⚠️ Requires: SUPABASE_ACCESS_TOKEN
  4. ✓ GitHub (already installed)

Select MCP numbers to install (e.g., 1,3 or "all"):
```

### Mode 2: Search (`mcp-store <query>`)

Searches MCP servers by keyword. Uses a 3-tier fallback to find results.

Examples:
- `mcp-store database` -> recommends PostgreSQL, SQLite, MongoDB, Supabase
- `mcp-store search` -> recommends Brave Search, Exa, Tavily
- `mcp-store kubernetes` -> searches Tier 2/3 if not in catalog

Workflow (3-tier fallback):

#### Step 1: Local Catalog Search
- Match query against stacks, services, domains keys and entry descriptions in catalog.json
- If results found, display and let user select

#### Step 2: awesome-mcp-servers Source Search (when Step 1 yields no results)
- Fetch the awesome-mcp-servers README via WebFetch and match against query:
  ```
  WebFetch(url: "https://raw.githubusercontent.com/wong2/awesome-mcp-servers/main/README.md")
  ```
- Extract matched server names, repo URLs, and descriptions
- AI constructs install commands from README information (repo URL, description)
- If install command cannot be determined, display repo URL for manual installation:
  ```
  [MCP Store] Found in awesome-mcp-servers (install command inferred):

    1. ServerName (owner/repo) — description
       Install: claude mcp add server-name -- npx -y @owner/package
       ⚠️ Verify install command from: https://github.com/owner/repo

    2. ServerName2 (owner/repo2) — description
       ❌ Install command unknown. See: https://github.com/owner/repo2
  ```
- If results found, let user select. Clearly mark inferred commands with "⚠️ Verify".

#### Step 3: GitHub/Web Search (when Step 2 also yields no results)
- Search GitHub and mcpservers.org for related MCP servers:
  ```
  WebSearch(query: "{query} mcp server site:github.com")
  WebSearch(query: "site:mcpservers.org {query}")
  ```
- Display candidate repos:
  ```
  [MCP Store] No "{query}" MCP servers found in catalog. Searched GitHub:

    1. owner/repo — description (stars: N)
    2. owner/repo — description (stars: N)

  ⚠️ Install commands not verified. Check each repo's README for setup.
  Select a number to attempt install (or "skip"):
  ```
- If no results:
  ```
  [MCP Store] No MCP servers found for "{query}".
  Browse available servers: https://mcpservers.org
  ```

### Mode 3: Category List (`--list <category>`)

Lists all MCP servers in a specific category.

- `mcp-store --list stacks` -> full list by language/framework
- `mcp-store --list services` -> full list by service
- `mcp-store --list domains` -> full list by domain
- `mcp-store --list core` -> reference servers (filesystem, memory, git, etc.)

### Mode 4: Update Catalog (`--update`)

Refreshes catalog.json from the awesome-mcp-servers README.

Workflow:
1. Fetch the awesome-mcp-servers README via WebFetch:
   ```
   WebFetch(url: "https://raw.githubusercontent.com/wong2/awesome-mcp-servers/main/README.md")
   ```
2. Compare with existing catalog.json entries
3. Report new/changed/removed servers
4. For new servers with clear npm packages, add entries with install commands
5. For servers without clear packages, add with `"command": ""` (empty = manual install)
6. Update `_updated` field with current date
7. Write updated catalog.json

Staleness warning:
- If `_updated` is older than 30 days, display:
  ```
  [MCP Store] ⚠️ Catalog last updated {N} days ago. Run `mcp-store --update` to refresh.
  ```

## Installation Method

### Duplicate Check (before any install)

```bash
# Check if MCP is already installed
claude mcp list 2>/dev/null | grep -q "{id}" && echo "installed" || echo "not-installed"
```

If already installed, skip with "✓ {name} already installed".

### Environment Variable Check (before install)

If the catalog entry has non-empty `env` array:
```
⚠️ Required environment variables for {name}:
  - {ENV_VAR_1}: (description/link to docs)
  - {ENV_VAR_2}: (description/link to docs)

Set them with: claude mcp add -e {ENV_VAR}=your-value ...
Or export them in your shell profile.
```

### Claude Environment

For stdio transport:
```bash
claude mcp add -s local {id} -- {command} {args...}

# With environment variables:
claude mcp add -s local -e {ENV_VAR}=value {id} -- {command} {args...}
```

For http transport:
```bash
claude mcp add -s local --transport http {id} {command}
```

If installation fails, provide manual instructions:
```
Installation failed. Manual setup:
  See: https://github.com/{repo}
  Or add manually: claude mcp add-json {id} '{...}'
```

### Codex Environment

Codex does not have a `claude mcp add` equivalent. Generate the MCP configuration JSON and guide the user:

```
[MCP Store] Codex MCP Configuration for {name}:

Add the following to your MCP config:

{
  "{id}": {
    "command": "{command}",
    "args": {args},
    "env": {
      "{ENV_VAR}": "your-value-here"
    }
  }
}

Copy this configuration to your Codex MCP settings file.
Refer to Codex documentation for the exact config location.
```

Record the intent in manifest.json regardless of platform.

### Post-Installation

- Record in manifest.json `mcpServers` section:
  ```json
  "mcpServers": {
    "{id}": {
      "transport": "{transport}",
      "installed": "{ISO8601 date}",
      "platform": "claude|codex"
    }
  }
  ```
- Display usage hint:
  ```
  ✓ {name} installed. It will be available in your next Claude Code session.
  ```

## Uninstall Method

To remove an installed MCP server:

```bash
# Claude
claude mcp remove {id}
```

After removal:
- Remove the entry from manifest.json `mcpServers` section
- Confirm: "✓ {name} removed."

## Setup Integration

During the `setup` workflow, the `--auto` mode runs automatically at Step 2.5 (after community skill recommendation):

1. After skill-store `--auto` completes (Step 2)
2. Read detected stack from manifest.json
3. Generate recommended MCP list based on catalog.json
4. Display recommended MCPs with required env vars
5. Install selected MCPs
6. Record in manifest.json `mcpServers` section

## Principles

- **CLI-first**: Skip MCP servers when an equivalent CLI tool is installed and authenticated (see `cli-covered-mcps.json` produced by cli-store)
- Never force-install (always user's choice)
- 3-tier fallback: local catalog -> awesome-mcp-servers source -> GitHub/web search
- Clearly mark Tier 2/3 results as "⚠️ install command not verified"
- Always show required environment variables before install
- Installation scope is always `local` (no API keys in project files)
- Does not duplicate-install already installed MCPs
- Provides manual installation instructions on failure
- Codex path outputs config JSON for manual setup
