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

## Future Consideration: 스킬 병합으로 토큰 추가 절감 (v0.8)

**What:** 관련 스킬을 병합하여 system-reminder 항목 수를 30 → 24로 줄여 토큰 추가 ~20% 절감.

**Why:** 2026-04-12 eng review에서 description 다이어트(51% 절감) 이후 추가 최적화로 평가됨. 단, 폭발 반경이 크므로 별도 PR로 진행.

**Pros:** 스킬 수 감소로 매 턴 토큰 절감, 사용자 관점에서 스킬 목록 간소화

**Cons:** 크로스 레퍼런스 업데이트 필요, 특히 auto-loop+autopilot(14개 파일) 및 store 스킬(런타임 의존성)

**Context:** 2026-04-12 eng review 폭발 반경 분석 결과:
- `plan` + `planning` → `plan` (9 files, medium risk)
- `tm-board` + `tm-init` + `tm-parse-prd` → `taskmaster` (2 files, low risk)
- `auto-loop` + `autopilot` → `auto` (14+ files, HIGH risk: synapse, team-templates, messenger, setup, verify-loop, harness-learn.sh, setup-check.sh, ARCHITECTURE.md, MESSENGER.md, codex plugin.json, session-control.ts)
- `mcp-store` + `cli-store` + `skill-store` → `store` (10+ files, HIGH risk: cli-store↔mcp-store 양방향 런타임 의존성, setup 순차 오케스트레이션, test script paths)
- `verify-loop`은 병합 제외 (Synapse가 주입하는 가이드라인, 사용자 호출 아님)

**Depends on / blocked by:** Description 다이어트 완료 후 실제 토큰 절감 측정

**Trigger:** description 다이어트 후에도 토큰 절감이 부족하다고 판단될 때
