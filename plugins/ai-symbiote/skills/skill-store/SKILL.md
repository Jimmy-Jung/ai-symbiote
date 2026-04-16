---
name: skill-store
description: "Recommends and installs community skills matching your project stack. Browses the awesome-agent-skills catalog (1,060+) by framework, service, and domain. Triggers on: skill recommendation, skill install, skill store, recommend skills, skill discovery."
user-invocable: true
argument-hint: [search query | --auto | --list <category>]
allowed-tools: [Read, Write, Bash, Glob, Grep, Agent]
---

# Skill Store

Recommends and installs community skills matching your project stack.
Source: [VoltAgent/awesome-agent-skills](https://github.com/VoltAgent/awesome-agent-skills) (1,060+ skills)

## Catalog

The skill-to-stack recommendation mapping is stored in `skills/skill-store/catalog.json` under the current plugin root.

Catalog structure:
- `stacks`: Recommendations by language/framework (nextjs, react, react-native, swift, python, typescript, rust, go, java, dotnet)
- `services`: Recommendations by service (supabase, neon, stripe, cloudflare, netlify, vercel, terraform, sanity, wordpress, sentry, figma, etc.)
- `domains`: Recommendations by domain (security, ai, scraping, marketing, product, document, video, design)

## Usage Modes

### Mode 1: Auto Recommend (`--auto`)

Reads `~/ai-symbiote/{slug}/manifest.json` and auto-recommends based on detected stack.

Workflow:
1. Read `project.languages`, `stack.frameworks`, `stack.packageManager` from manifest.json
2. Match against `stacks` in catalog.json by language/framework
3. Scan project dependency files (package.json, requirements.txt, etc.) to detect services:
   - `@supabase/supabase-js` -> supabase recommendation
   - `stripe` -> stripe recommendation
   - `@sentry/node` -> sentry recommendation
   - `better-auth` -> betterauth recommendation
   - `@cloudflare/workers-types` -> cloudflare recommendation
   - `@netlify/functions` -> netlify recommendation
   - `sanity` -> sanity recommendation
   - `terraform` (*.tf files) -> terraform recommendation
4. Display matched skill list with numbers
5. Install when user selects by number

Output format:
```
[Skill Store] Recommended skills based on project analysis:

Frameworks:
  1. Next.js Best Practices (vercel/next-best-practices)
  2. React Best Practices (vercel/react-best-practices)

Services:
  3. Supabase Postgres Best Practices (supabase-community/postgres-best-practices)
  4. Stripe Best Practices (nickcopi/stripe-best-practices)

Select skill numbers to install (e.g., 1,3,4 or "all"):
```

### Mode 2: Search (`skill-store <query>`)

Searches skills by keyword. Uses a 3-tier fallback to always find results.

Examples:
- `skill-store security` -> recommends 22 Trail of Bits security skills
- `skill-store ai` -> recommends Hugging Face, fal.ai, Replicate, Gemini
- `skill-store marketing` -> recommends 30+ marketing skills
- `skill-store figma` -> recommends Figma design skills
- `skill-store xcode build` -> auto-searches GitHub/web if not in catalog

Workflow (3-tier fallback):

#### Step 1: Local Catalog Search
- Match query against stacks, services, domains keys in catalog.json
- If results found, display and let user select

#### Step 2: awesome-agent-skills Source Search (when Step 1 yields no results)
- Fetch the awesome-agent-skills README via WebFetch and match against query:
  ```
  WebFetch(url: "https://raw.githubusercontent.com/VoltAgent/awesome-agent-skills/main/README.md")
  ```
- If results found, display and let user select

#### Step 3: GitHub/Web Search (when Step 2 also yields no results)
- Search GitHub for related skills/plugins:
  ```
  WebSearch(query: "{query} claude code skill site:github.com")
  WebSearch(query: "{query} (plugin OR agent skill) site:github.com")
  ```
- Prioritize repos with `.claude-plugin` or `.codex-plugin` directories
- Display candidate repos to user:
  ```
  [Skill Store] No "{query}" related skills found in catalog. Searched GitHub instead:

    1. {owner}/{repo} - {description} (stars: N)
    2. {owner}/{repo} - {description} (stars: N)

  Select a number to install (or "skip" to skip):
  ```
- If no search results either:
  ```
  [Skill Store] No skills found related to "{query}".
  Try searching GitHub directly or create your own skill:
  https://github.com/search?q={query}+codex+skill&type=repositories
  ```

### Mode 3: Category List (`--list <category>`)

Lists all skills in a specific category.

- `skill-store --list stacks` -> full list by language/framework
- `skill-store --list services` -> full list by service
- `skill-store --list domains` -> full list by domain

### Mode 4: Update Full Catalog (`--update`)

Fetches the awesome-agent-skills README via WebFetch and updates catalog.json.

## Installation Method

When installing a selected skill, detects the current platform and uses the appropriate method:

### Claude Environment

```bash
# 1. Register in marketplace (skip if already registered)
claude plugin marketplace add {owner}/{repo} 2>/dev/null

# 2. Install plugin (refer to name field in plugin.json)
claude plugin install {plugin-name}@{marketplace-name}

# If installation fails, provide manual instructions
echo "Manual install: see https://github.com/{owner}/{repo}"
```

### Codex Environment

```bash
# 1. Clone the repository
git clone https://github.com/{owner}/{repo} ~/plugins/{repo}

# 2. Verify plugin manifest
find ~/plugins/{repo} -maxdepth 2 \( -path "*/.claude-plugin/plugin.json" -o -path "*/.codex-plugin/plugin.json" \)

# 3. Add entry to marketplace.json and enable in config.toml
```

Notes:
- Claude family uses `.claude-plugin/plugin.json` and the marketplace registration flow.
- Codex family uses `.codex-plugin/plugin.json` and the local marketplace/config sync flow.
- Plugin name is based on the `name` field in each manifest.

Post-installation:
- Add installation record to the `plugins` section of manifest.json
- Provide usage instructions for the installed skill to the user

## Setup Integration

During the `setup` workflow, the `--auto` mode runs automatically at Step 2 (platform-specific skill pack request):

1. After project stack detection completes
2. Generate recommended skill list based on catalog.json
3. Display recommended skills to user
4. Install selected skills
5. Record in manifest.json

## Principles

- Never force-install (always user's choice)
- 3-tier fallback: local catalog -> awesome-agent-skills source -> GitHub/web search
- Always searches GitHub/web for skills not in the catalog
- Provides manual installation instructions on failure
- Does not duplicate-install already installed skills
- Prioritizes repos with `.claude-plugin` or `.codex-plugin` directories when searching GitHub
