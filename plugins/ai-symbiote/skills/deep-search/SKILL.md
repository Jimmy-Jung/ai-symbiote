---
name: deep-search
user-invocable: true
description: Multi-strategy deep codebase search workflow. Runs Grep, Glob, and subagent(explorer) in parallel to comprehensively analyze symbols, patterns, and dependencies. This skill should be used when performing deep codebase analysis or searching for complex code patterns and dependencies.
---

# Deep Search -- Multi-Strategy Codebase Exploration

Executes diverse search strategies in parallel for deep codebase exploration.
Discovers relationships, patterns, and hidden dependencies that are difficult to find with a single search.

## 4-Step Workflow

### Step 1: Define Search Objectives
- What are you looking for? (symbols, patterns, relationships, impact scope)
- Where to search? (entire codebase / specific module / specific layer)
- Why are you searching? (implementation reference, impact analysis, dependency identification)

### Step 2: Parallel 3-Track Search

Track A -- Exact Matching (Grep): Exact search by type name, symbol name, import/use patterns
Track B -- File Patterns (Glob): File exploration based on naming conventions, directory structure
Track C -- Deep Exploration (Agent Explore): Broad codebase exploration

All 3 Tracks must be executed simultaneously.

### Step 3: Dependency Tracing
- Import/use relationship graph, circular reference detection
- Protocol/interface adoption relationships
- Type references (parameters, returns, properties)

### Step 4: Structured Report
Organizes discovered files, dependency relationships, key findings, impact scope, and recommended follow-up exploration items.

## Scenario-Specific Strategies

Before feature implementation: Search similar implementations, check APIs/Repositories

Before refactoring: References to modification targets, inheritance/protocol chains, test references

Bug tracking: Search error messages/types, trace call chains

Legacy analysis: Mixed patterns, bridging references, legacy code location

## Principles

- Parallel first: Execute 3-Track simultaneously
- Evidence-based: Include source paths for all results
- Progressive deepening: Further exploration based on initial results
- Scope limiting: Filter results unrelated to the objective

## Role Injection: Scout

This section is injected into the prompt when the synapse orchestrator spawns a Scout sub-agent.

The Scout follows the 4-Step workflow and 3-Track parallel search strategy above.
Select and apply scenario-specific strategies appropriate to the situation.
Results must be written in markdown to the designated result file.
