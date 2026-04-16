---
name: code-accuracy
user-invocable: true
description: Verify symbol existence, validate imports, check library APIs, and prevent hallucinated code generation when writing or modifying code. This skill should be used when writing or modifying code to prevent hallucinated symbols, verify imports, check library APIs, and ensure compilable output.
---

# Code Accuracy

Core principles for writing code, applicable regardless of language/platform. Aims to prevent hallucinated code generation and produce actually working code.

## Core Principles

Only suggest code that actually exists in the project codebase. Never reference types, functions, or modules that do not exist.

## Symbol Verification Strategy

### Before Using Types/Functions/Classes
- Use Grep to check if the definition exists in the project.
- Search with class/struct/enum/protocol/interface + symbol name.
- Confirm the definition location before referencing it.

### Before Using Imports
- Verify the module is declared in the dependency file.
- package.json, Package.swift, requirements.txt, build.gradle, Cargo.toml, etc.
- If not present, suggest adding the dependency.

### Before Using Library APIs
- Verify API existence through project source or web search.
- Check version compatibility (whether the API exists in the current version).

## Dependency File Mapping

| Language/Platform | Dependency File |
|-------------------|-----------------|
| JavaScript/Node | package.json |
| Swift | Package.swift, Podfile |
| Python | requirements.txt, pyproject.toml |
| Java/Kotlin | build.gradle, pom.xml |
| C# | .csproj, packages.config |
| Go | go.mod |
| Rust | Cargo.toml |

## Type Selection Rules (General)

| Situation | Choice | Reason |
|-----------|--------|--------|
| Value type, immutable data | struct/record | Copy semantics, immutability |
| Reference type, shared state | class | Reference semantics |
| Abstraction, polymorphism | protocol/interface | Dependency inversion |
| Finite set of cases | enum | Pattern matching |
| State isolation needed | actor (if supported) | Concurrency safety |

## Project Structure Awareness

Identify architecture from folder structure:

- Domain/Entities, UseCases, Repositories: Clean Architecture
- Features/Model, View, ViewModel: MVVM
- Controllers, Models, Views: MVC
- src/components, src/services: Layered

Place new code in the appropriate location matching the architecture.

## Library API Verification (5 Steps)

1. Check dependency file: Is the library listed in the dependency manifest?
2. Check version: Confirm the version used in the project.
3. Search usage patterns in codebase: Reference existing usage.
4. If unfamiliar with the API: Verify via web search or official docs.
5. If uncertain: Mark with @unverified comment and request user confirmation.

## Fallback Behavior on Verification Failure

1. Ask the user. Do not guess.
2. Do not insert stubs or placeholders.
3. Show existing similar code and let the user choose.
4. Verify further via official docs or web search.

## Hallucination Pattern Prevention

| Pattern | Response |
|---------|----------|
| Inventing non-existent APIs | Verify via Grep or web search |
| Incorrect method signatures | Check actual definitions |
| Importing non-existent modules | Check dependency files |
| Using deprecated APIs | Check for latest replacement APIs |
| Guessing versions | Use project-declared version |

## Pre-Coding Checklist

```
- Do the referenced types/functions/modules exist in the project?
- Is the dependency listed in the package manager file?
- Is the import/require path correct?
- Do the function signatures and parameters match?
- Does it follow the existing architecture/patterns?
- Is this complete, compilable/runnable code?
- Does the API exist in the target version?
- Has deprecation status been verified?
- Do not auto-generate new types/classes without user permission.
```

## Code Generation Rules

1. Do not auto-generate types/classes/modules without user permission.
2. Produce complete, compilable code. Do not end with stubs, placeholders, or TODO comments.
3. Follow the existing project architecture/patterns.
4. If similar existing code exists, reference its patterns.

## Role Injection: Builder

This section is injected into the prompt when the synapse orchestrator spawns a Builder subagent.

The Builder follows the Symbol Verification Strategy, Dependency File Mapping, Library API Verification (5 Steps), and Pre-Coding Checklist above.
Only implement the exact steps assigned by the Architect. Do not perform out-of-scope improvements or refactoring.
Run lint/compile after implementation and report results.
Write results in markdown to the designated result file.
