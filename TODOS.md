# TODOS

## Future Consideration: ai-memory-mcp 도입 재검토

**What:** ai-memory-mcp (SQLite + FTS5 + 벡터 검색)를 하네스 규칙 저장소로 도입하여 의미 기반 검색, TTL 자동 만료, 프로젝트 간 규칙 공유를 지원.

**Why:** 현재 JSONL + grep 기반 시스템은 규칙 50개 이하에서 잘 동작하지만, 규모가 커지면 (1) 선택적 규칙 주입 (2) 의미 기반 유사 규칙 검색 (3) 프로젝트 간 규칙 재활용이 필요해질 수 있음.

**Pros:** 의미 검색으로 더 정확한 규칙 매칭, TTL 기반 자동 만료, 프로젝트 간 공유 가능

**Cons:** Rust 바이너리 + SQLite + 임베딩 모델(~256MB) 의존성 추가, 디버깅 복잡도 증가, 훅 스크립트 재작성 필요

**Context:** 2026-04-10 eng review에서 평가됨. 현재 harness-rules.md는 50줄 미만 수준이며, dedup 버그 수정 + auto-GC로 비대화 문제 해결. ai-memory-mcp는 규칙 50개+ 또는 프로젝트 간 규칙 공유가 필요할 때 재검토. 참고: https://mcpservers.org/servers/alphaonedev/ai-memory-mcp

**Depends on / blocked by:** dedup 버그 수정 및 auto-GC 구현 후 실제 규칙 누적 패턴 관찰 필요

**Trigger:** harness-rules.md 규칙이 50개 이상이거나 프로젝트 간 규칙 공유 요구 발생 시

## Future Consideration: MCP catalog 설치 커맨드 CI 검증

**What:** mcp-store catalog.json의 설치 커맨드가 실제로 작동하는지 CI에서 자동 검증하는 테스트 추가.

**Why:** catalog.json은 정적 파일로 npm 패키지 이름, args, transport 정보를 포함. 패키지가 이름 변경/삭제되면 설치 명령이 실패하지만 기존 테스트(JSON validity + schema)로는 감지 불가.

**Pros:** 카탈로그 staleness를 CI 단계에서 자동 감지, 사용자에게 항상 작동하는 설치 경험 제공

**Cons:** CI에서 `npx -y <package> --help` 실행 필요 (네트워크 의존, 실행 시간 증가), 일부 MCP는 API 키 없이 실행 불가

**Context:** 2026-04-10 eng review outside voice에서 지적됨. "catalog staleness is the actual failure mode." 현재 카탈로그 규모(~50 entries)에서는 수동 검증으로 충분하지만, 카탈로그 확장 시 필수.

**Depends on / blocked by:** mcp-store 기본 구현 완료 후

**Trigger:** catalog.json 엔트리가 20개 이상이거나 설치 실패 보고 발생 시
