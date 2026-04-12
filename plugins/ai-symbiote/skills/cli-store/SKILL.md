---
name: cli-store
description: "Recommends and installs CLI tools matching your project stack. CLI tools are preferred over MCP servers when available — lighter, already authenticated, no extra process. Triggers on: cli recommendation, cli install, cli store, recommend cli, cli discovery."
user-invocable: true
argument-hint: [search query | --auto | --list <category>]
allowed-tools: [Read, Write, Bash, Glob, Grep, Agent]
---

# CLI Store

Recommends and installs CLI tools matching your project stack.
CLI tools are preferred over MCP servers — they are lighter, often already authenticated, and accessible directly via Bash without spawning extra processes.

## Why CLI over MCP

| Factor | CLI | MCP Server |
|--------|-----|------------|
| Process overhead | None (direct Bash call) | Separate Node.js process |
| Authentication | Already configured (e.g., `gh auth`) | Requires separate token/env vars |
| Feature coverage | Full CLI capability | Subset exposed via MCP protocol |
| Token cost | Lower (direct output) | Higher (MCP protocol overhead) |
| Startup time | Instant | Cold start on first call |

**Rule**: If a CLI is installed and authenticated, skip the equivalent MCP server.

## Catalog

The CLI-to-stack recommendation mapping is stored in `skills/cli-store/catalog.json` under the current plugin root.

Catalog structure:
- `stacks`: Recommendations by language/framework
- `services`: Recommendations by service
- `domains`: Recommendations by domain

Each catalog entry contains:
```json
{
  "id": "unique-cli-id",
  "name": "Display Name",
  "cmd": "command-name",
  "checkCmd": "command to verify installed + authenticated",
  "installCmd": {
    "brew": "brew install ...",
    "apt": "sudo apt install ...",
    "npm": "npm install -g ..."
  },
  "mcpEquivalent": "mcp-server-id or null",
  "category": "category-tag",
  "description": "Brief description"
}
```

### Key Fields

- `checkCmd`: Runs to determine if the CLI is installed **and** authenticated. Use `--version` for install-only check, `auth status` for auth-required tools.
- `installCmd`: Platform-specific install commands. Detect the user's platform and pick the appropriate one.
- `mcpEquivalent`: The MCP server ID from `mcp-store/catalog.json` that this CLI replaces. When non-null, the mcp-store should skip recommending that MCP server.

## Usage Modes

### Mode 1: Auto Recommend (`--auto`)

Reads `~/ai-symbiote/{slug}/manifest.json` and auto-recommends based on detected stack.

Workflow:
1. Read `project.languages`, `stack.frameworks`, `stack.packageManager` from manifest.json
2. Match against `stacks` in catalog.json by language/framework
3. Scan project dependency files to detect services (same patterns as mcp-store)
4. For each matched CLI, run `checkCmd` to determine install status:
   ```bash
   {checkCmd} 2>/dev/null && echo "ready" || echo "not-ready"
   ```
5. Classify each CLI into one of three states:
   - **✓ Ready**: CLI installed and authenticated → will replace equivalent MCP
   - **⚡ Installable**: CLI not installed but relevant → offer to install
   - **⚠️ Needs auth**: CLI installed but not authenticated → guide user
6. Display results and let user select CLIs to install

Output format:
```
[CLI Store] CLI tools detected for your project:

Ready (will skip equivalent MCP servers):
  ✓ gh (GitHub CLI) — authenticated, replaces github MCP
  ✓ docker — installed, replaces docker MCP

Recommended to install:
  1. supabase (Supabase CLI) — replaces supabase MCP
     Install: brew install supabase/tap/supabase
  2. stripe (Stripe CLI) — replaces stripe MCP
     Install: brew install stripe/stripe-cli/stripe

Needs authentication:
  ⚠️ aws — installed but run `aws configure` to authenticate

Select CLI numbers to install (e.g., 1,2 or "all" or "skip"):
```

7. After CLI detection, export the list of `mcpEquivalent` IDs that are covered by ready CLIs. This list is used by the subsequent mcp-store `--auto` step to skip those MCP servers.

### Mode 2: Search (`cli-store <query>`)

Searches CLI tools by keyword. Uses a 3-tier fallback to always find results.

Examples:
- `cli-store database` -> recommends psql, sqlite3, mongosh
- `cli-store cloud` -> recommends aws, gcloud, az, wrangler
- `cli-store github` -> recommends gh
- `cli-store redis` -> not in catalog, searches Homebrew/GitHub

Workflow (3-tier fallback):

#### Step 1: Local Catalog Search
- Match query against stacks, services, domains keys and entry descriptions in catalog.json
- If results found, display with install status and let user select

#### Step 2: Homebrew Search (when Step 1 yields no results)

Search Homebrew formulae/casks for the CLI tool:
```bash
# macOS / Linux with Homebrew
brew search {query} 2>/dev/null | head -10
```

If Homebrew is not available, search the Homebrew Formulae API:
```
WebFetch(url: "https://formulae.brew.sh/api/search/{query}")
```

Display results:
```
[CLI Store] No "{query}" found in catalog. Searched Homebrew:

  1. {formula-name} — {description}
     Install: brew install {formula-name}
  2. {cask-name} — {description}
     Install: brew install --cask {cask-name}

Select a number to install (or "skip"):
```

For each result, attempt to get the description:
```bash
brew info --json=v2 {formula-name} 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['formulae'][0]['desc'])"
```

#### Step 3: GitHub/Web Search (when Step 2 also yields no results)

Search GitHub and the web for CLI tools:
```
WebSearch(query: "{query} CLI tool site:github.com")
WebSearch(query: "{query} command line tool install")
```

Display candidate repos:
```
[CLI Store] No "{query}" CLI found in catalog or Homebrew. Searched GitHub:

  1. owner/repo — description (stars: N)
     Install: brew install owner/tap/name  OR  npm install -g package
  2. owner/repo — description (stars: N)

  ⚠️ Install commands inferred from README. Verify before running.
  Select a number to install (or "skip"):
```

If no results at all:
```
[CLI Store] No CLI tools found for "{query}".
Try: brew search {query}
Or check MCP alternatives: /mcp-store {query}
```

### Mode 3: Category List (`--list <category>`)

Lists all CLIs in a specific category.

- `cli-store --list stacks` -> full list by language/framework
- `cli-store --list services` -> full list by service
- `cli-store --list domains` -> full list by domain

## Installation Method

### Platform Detection

Detect the user's package manager:
```bash
# macOS
command -v brew >/dev/null 2>&1 && echo "brew"

# Linux (Debian/Ubuntu)
command -v apt >/dev/null 2>&1 && echo "apt"

# Node.js available
command -v npm >/dev/null 2>&1 && echo "npm"

# Python available
command -v pip >/dev/null 2>&1 && echo "pip"
```

Pick the best available installer from the entry's `installCmd` object in priority order: `brew` > `apt` > `npm` > `pip`.

### Install Flow

1. Detect platform package manager
2. Select appropriate install command from `installCmd`
3. Run the install:
   ```bash
   {installCmd} 2>&1
   ```
4. Verify installation:
   ```bash
   {checkCmd} 2>/dev/null && echo "SUCCESS" || echo "FAILED"
   ```
5. If the CLI requires authentication, guide the user:
   ```
   ✓ {name} installed. Run the following to authenticate:
     gh auth login          (GitHub CLI)
     aws configure          (AWS CLI)
     gcloud auth login      (Google Cloud CLI)
     az login               (Azure CLI)
     stripe login           (Stripe CLI)
     wrangler login         (Cloudflare Wrangler)
     supabase login         (Supabase CLI)
     sentry-cli login       (Sentry CLI)
     kubectl config use-context <ctx>  (Kubernetes — select cluster)
   ```

### Post-Installation

- Record in manifest.json `cliTools` section:
  ```json
  "cliTools": {
    "{id}": {
      "cmd": "{cmd}",
      "installed": "{ISO8601 date}",
      "mcpEquivalent": "{mcp-id or null}",
      "status": "ready|installed|needs-auth"
    }
  }
  ```

## Setup Integration

During the `setup` workflow, the `--auto` mode runs at **Step 2.5** (between skill-store and mcp-store):

```
Step 2:   skill-store --auto    (community skills)
Step 2.5: cli-store --auto      (CLI tools — NEW)
Step 3:   mcp-store --auto      (MCP servers, skipping CLI-covered ones)
```

### MCP Deduplication

After cli-store completes, it produces a **skip list** of MCP IDs covered by ready CLIs:
```
cliCoveredMcpIds = ["github", "docker", "supabase", ...]
```

The mcp-store `--auto` step reads this list and:
- Skips recommending those MCP servers entirely
- Or displays them as: `~~GitHub MCP~~ — covered by gh CLI`

This skip list is stored at `~/ai-symbiote/{slug}/state/cli-covered-mcps.json`:
```json
{
  "coveredMcpIds": ["github", "docker"],
  "generatedAt": "ISO8601"
}
```

## Principles

- CLI is always preferred over equivalent MCP when installed and authenticated
- Never force-install (always user's choice)
- Detect platform package manager automatically
- Guide authentication for tools that need it
- Export covered MCP IDs to prevent duplicate recommendations
- Lightweight: no extra processes, no token management overhead
