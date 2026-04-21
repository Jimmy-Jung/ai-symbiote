# TODOS

Project-wide task tracker organized by skill/component, then priority (P0 most urgent → P4 nice-to-have, then Completed at bottom).

## verify

### Queue concurrent write race — `flock` or atomic temp+rename
**Priority:** P1
**What:** `shared/hooks/scripts/verify-queue.sh` appends to the shared queue with `printf ... >> $QUEUE_FILE`. POSIX `O_APPEND` guarantees atomicity only for writes ≤ `PIPE_BUF` (512 bytes on some platforms, 4096 on Linux). A single queue entry can exceed 512 bytes when the absolute file path + repo_root are long, so parallel PostToolUse invocations (Agent tool, parallel edits) can interleave and produce torn JSONL lines that jq silently drops.
**Why:** Silent data loss of verification entries. Detected by Claude + Codex adversarial review (cross-confirmed).
**Pros of fixing:** Guaranteed durability under concurrent edits.
**Cons / complexity:** `flock` is util-linux, not installed by default on macOS. Alternatives: `shlock`, atomic tempfile + rename, or detecting parallel invocations and serializing.
**Context:** Deferred from v0.11.0 ship. The current behavior is "probably fine on sequential edits, risky under Agent tool parallelism." Write a small design doc before picking an approach — flock vs shlock vs mktemp+mv each have tradeoffs (portability, error modes, lock leak recovery).
**Depends on / blocked by:** Platform compatibility research.

### Queue rotation / TTL — `gc` skill extension
**Priority:** P2
**What:** `~/.ai-symbiote/state/verify-queue.jsonl` grows unbounded. PASS entries are pruned by `/verify`, but FAIL entries and never-processed entries accumulate forever. Eventually `setup-check.sh`'s jq pass iterates the entire file on every SessionStart (O(N) per session).
**Why:** Performance degradation on long-running machines. Also noise from stale entries when user abandons a branch without running `/verify`.
**Pros of fixing:** Bounded queue size, faster SessionStart, less noise.
**Cons / complexity:** Need a GC policy — TTL vs LRU vs size cap. Deciding "30 days old" vs "FAIL entries after user moved to a new branch" requires heuristics.
**Context:** Deferred from v0.11.0 ship. The `/verify` SKILL.md already references "Related Skills — gc: 오래된 queue entry / qa artifact 정리 (향후 gc 확장)". Best home is extending the existing `gc` skill rather than adding another entrypoint.
**Depends on / blocked by:** `gc` skill's existing GC policy (review it first to stay consistent).

### Drop legacy `sha` field from queue schema
**Priority:** P3
**What:** `verify-queue.sh` emits both `base_sha` (v2, canonical) and `sha` (v1, mirror) fields. Once all consumers migrate, `sha` should be removed.
**Why:** Reduce queue entry size and remove a source of confusion. The v1 field was added for backward compat during the v2 schema introduction (2026-04-21).
**Pros of fixing:** Cleaner schema.
**Cons / complexity:** Must audit every consumer (setup-check.sh, SKILL.md diff contract, tests) before removal. Breaking change for any third-party consumer (none known today).
**Context:** Target version: v0.12.0. Already tagged as `TODO(0.12.0)` comment in `shared/hooks/scripts/verify-queue.sh`.
**Depends on / blocked by:** Nothing — mechanical removal once v0.12 is cut.

## general

### Cursor platform integration for verify pipeline
**Priority:** P2
**What:** `/verify` is currently Claude-only (PostToolUse Write|Edit hook). Cursor uses different hook event names (lower camelCase: `sessionStart`, `preToolUse`, `postToolUse`) and different matchers (`Shell`, `Read`, `Write`). Need to design an equivalent queue + notification flow.
**Why:** Cursor users are excluded from the feature. `docs/02-아키텍처.md` platform matrix says "Cursor: 후속 릴리즈(v0.11+)에서 별도 검토 예정."
**Pros of fixing:** Feature parity across platforms.
**Cons / complexity:** Cursor's hook capabilities differ. May need a different architecture (e.g., polling vs push).
**Context:** Deferred from v0.11.0 ship. Start by documenting Cursor's hook capabilities and contrasting with Claude's.
**Depends on / blocked by:** Nothing.

## Completed

<!-- Items completed in shipped releases move here with their version tag -->
