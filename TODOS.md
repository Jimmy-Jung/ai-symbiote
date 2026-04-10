# TODOS

## Future Consideration: ai-memory-mcp 도입 재검토

**What:** ai-memory-mcp (SQLite + FTS5 + 벡터 검색)를 하네스 규칙 저장소로 도입하여 의미 기반 검색, TTL 자동 만료, 프로젝트 간 규칙 공유를 지원.

**Why:** 현재 JSONL + grep 기반 시스템은 규칙 50개 이하에서 잘 동작하지만, 규모가 커지면 (1) 선택적 규칙 주입 (2) 의미 기반 유사 규칙 검색 (3) 프로젝트 간 규칙 재활용이 필요해질 수 있음.

**Pros:** 의미 검색으로 더 정확한 규칙 매칭, TTL 기반 자동 만료, 프로젝트 간 공유 가능

**Cons:** Rust 바이너리 + SQLite + 임베딩 모델(~256MB) 의존성 추가, 디버깅 복잡도 증가, 훅 스크립트 재작성 필요

**Context:** 2026-04-10 eng review에서 평가됨. 현재 harness-rules.md는 50줄 미만 수준이며, dedup 버그 수정 + auto-GC로 비대화 문제 해결. ai-memory-mcp는 규칙 50개+ 또는 프로젝트 간 규칙 공유가 필요할 때 재검토. 참고: https://mcpservers.org/servers/alphaonedev/ai-memory-mcp

**Depends on / blocked by:** dedup 버그 수정 및 auto-GC 구현 후 실제 규칙 누적 패턴 관찰 필요

**Trigger:** harness-rules.md 규칙이 50개 이상이거나 프로젝트 간 규칙 공유 요구 발생 시
