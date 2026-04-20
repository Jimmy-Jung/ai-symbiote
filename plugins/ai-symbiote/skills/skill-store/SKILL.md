---
name: skill-store
description: "Recommends and installs community Claude Code / Codex plugins matching your project stack. Starts from a curated local catalog and falls back to live GitHub / web search when the catalog has no coverage. Triggers on: skill recommendation, skill install, skill store, recommend skills, skill discovery."
user-invocable: true
argument-hint: [search query | --auto | --list <category>]
allowed-tools: [Read, Write, Bash, Glob, Grep, WebFetch, WebSearch, Agent]
---

# Skill Store

Recommends and installs community agent skills / plugins matching your project stack.

**No single upstream catalog is required.** The bundled `catalog.json` is a curated seed list of well-known plugins (e.g. Swift / iOS, Next.js, Supabase). Anything outside that seed is resolved via live GitHub / web search.

## Catalog

The curated seed is stored in `skills/skill-store/catalog.json` under the current plugin root.

Structure:
- `stacks`: Recommendations by language/framework (nextjs, react, react-native, swift, python, typescript, rust, go, java, dotnet)
- `services`: Recommendations by service (supabase, neon, stripe, cloudflare, netlify, vercel, terraform, sanity, wordpress, sentry, figma, …)
- `domains`: Recommendations by domain (security, ai, scraping, marketing, product, document, video, design)

Each entry references a real GitHub repo installable via `/plugin marketplace add {owner}/{repo}`.

To grow the seed, add entries directly to `catalog.json`. There is no external mirror to sync.

## Usage Modes

### Mode 1: Auto Recommend (`--auto`)

Reads `~/ai-symbiote/{slug}/manifest.json` and auto-recommends based on detected stack.

Workflow:
1. Collect lookup keys from manifest.json:
   - `project.languages`
   - `project.platforms` (ios, ipados, macos, tvos, watchos, visionos, android, web)
   - `project.type`
   - `stack.frameworks`
   - `stack.buildTool`
2. Expand keys through `shared/lib/stack-aliases.json` (e.g. `ios`, `ipados`, `swiftui`, `uikit` → `swift`; `next.js` → `nextjs`; `expo` → `react-native`)
3. Match expanded keys against `stacks` in catalog.json
4. Scan project dependency files (`package.json`, `Podfile`, `Project.swift`, `*.xcodeproj/project.pbxproj`, `requirements.txt`, etc.) to detect services:
   - `@supabase/supabase-js` / `supabase-swift` -> supabase recommendation
   - `stripe` / `stripe-ios` -> stripe recommendation
   - `@sentry/node` / `sentry-cocoa` -> sentry recommendation
   - `firebase/firebase-ios-sdk` -> firebase recommendation
   - `revenuecat/purchases-ios` -> revenuecat recommendation
   - `@cloudflare/workers-types` -> cloudflare recommendation
   - `@netlify/functions` -> netlify recommendation
   - `terraform` (*.tf files) -> terraform recommendation
5. Display matched skill list with numbers
6. **If zero matches are returned** (no catalog coverage for the detected stack), automatically run Mode 2 Step 2 with the primary platform/language as the query (e.g. `ios`, `swiftui`). Never return an empty recommendation without attempting live search.
7. Install when the user selects by number

Output format:
```
[Skill Store] Recommended skills based on project analysis:

Frameworks:
  1. Swift iOS Skills (dpearson2699/swift-ios-skills)
  2. Axiom (CharlesWiltgen/Axiom)

Services:
  3. Supabase Postgres Best Practices (supabase-community/postgres-best-practices)

Select skill numbers to install (e.g., 1,3 or "all"):
```

### Mode 2: Search (`skill-store <query>`)

Searches skills by keyword with a 2-tier fallback — no external catalog dependency.

Examples:
- `skill-store security` -> local seed hits (Trail of Bits, etc.)
- `skill-store ios simulator` -> falls through to GitHub search
- `skill-store figma` -> local seed for Figma design skills

Workflow (2-tier fallback):

#### Step 1: Local Catalog Search
- Substring match against `repo`, `name`, `category`, `_group` in catalog.json
- If any results found, display numbered list and let the user select

#### Step 2: Live GitHub / Web Search (when Step 1 yields no results)
Run **both** of the following searches via `WebSearch` (or `WebFetch` against GitHub when a specific repo is known):

```
WebSearch(query: "{query} claude code plugin site:github.com")
WebSearch(query: "{query} (agent skill OR codex plugin) site:github.com")
```

Ranking / filtering rules:
- Prioritize repos whose root contains `.claude-plugin/plugin.json` or `.codex-plugin/plugin.json`
- Prefer higher-star repos that mention "Claude Code", "agent skill", or "plugin" in the README
- Deduplicate by `{owner}/{repo}`
- Cap to the top 5 candidates

Display:
```
[Skill Store] No "{query}" results in the local catalog. GitHub search:

  1. {owner}/{repo} — {short description} (★ {stars})
  2. {owner}/{repo} — {short description} (★ {stars})

Select a number to install (or "skip" to skip):
```

If the live search also returns nothing:
```
[Skill Store] No plugins found for "{query}".
Try searching GitHub directly:
https://github.com/search?q={query}+claude-plugin&type=repositories
```

### Mode 3: Category List (`--list <category>`)

Lists all seed entries in a specific category.

- `skill-store --list stacks` -> full list by language/framework
- `skill-store --list services` -> full list by service
- `skill-store --list domains` -> full list by domain

## Installation Method

When installing a selected skill, detect the current platform and use the appropriate method:

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
- Add an installation record to the `plugins` section of `manifest.json`
- Provide usage instructions for the installed skill to the user

## Setup Integration

During the `setup` workflow, `--auto` runs at Step 2 (platform-specific skill pack request):

1. After project stack detection completes
2. Generate the recommended skill list from catalog.json + (if needed) live search fallback
3. Display recommended skills to the user
4. Install selected skills
5. Record in manifest.json

## Principles

- Never force-install — always user's choice
- Catalog is a **curated seed**, not a mirror of any external source
- When the seed has no match, always run live GitHub / web search before reporting "nothing found"
- Prioritize repos with `.claude-plugin` or `.codex-plugin` directories
- Provide manual installation instructions on failure
- Do not duplicate-install already installed skills
