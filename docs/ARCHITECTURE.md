# Architecture

`ai-symbiote`는 공용 코어와 플랫폼 오버레이를 분리한 구조를 사용합니다.

## Core

<!-- AI-SYMBIOTE:START architecture:subsystems -->
`shared/`는 플랫폼에 독립적인 자산을 담는 **유일한 편집 대상**입니다.

| 디렉터리 | 내용 | 수량 |
|-----------|------|------|
| `skills/` | 27개 스킬 정의 (SKILL.md + 보조 스크립트) | 27 |
| `hooks/scripts/` | 훅 스크립트 + `lib/common.sh` 공용 라이브러리 | 6개 |
| `harness-seeds/` | 스택별 초기 규칙 시드 (generic, swift, nextjs, python) | 4개 |
| `taskmaster/` | PRD/task JSON 스키마 및 템플릿 | — |
| `messenger-bridge/` | Telegram/Slack/Discord 브릿지 (TypeScript/Node.js) | — |

저장소 루트의 다른 주요 디렉터리:

| 디렉터리 | 역할 | 편집 가능 |
|-----------|------|-----------|
| `platforms/{claude,codex}/overlay/` | 플랫폼별 plugin.json, hooks.json 오버레이 | O |
| `scripts/` | 빌드 스크립트 (build-all/claude/codex.sh) + version_sync.py | O |
| `docs/` | 개발자 문서 6개 (마커 블록 기반 자동 갱신) | O |
| `tests/` | 셸 기반 통합 테스트 | O |
| `plugins/ai-symbiote/` | Claude 마켓플레이스 번들 (**빌드 생성물**) | X |
| `dist/` | 배포용 번들 (**빌드 생성물**) | X |

```mermaid
flowchart TD
    subgraph "shared/ (원본)"
        SK["skills/ (27)"]
        HK["hooks/scripts/ (6)"]
        HS["harness-seeds/ (4)"]
        TM["taskmaster/"]
        MB["messenger-bridge/"]
    end
    subgraph "플랫폼 오버레이"
        CL["platforms/claude/overlay/"]
        CX["platforms/codex/overlay/"]
    end
    subgraph "빌드 생성물"
        PL["plugins/ai-symbiote/"]
        DC["dist/claude-symbiote/"]
        DX["dist/codex-symbiote/"]
    end
    SK & HK & HS & TM & MB --> CL
    SK & HK & HS & TM & MB --> CX
    CL -->|"rsync + overlay"| PL
    CL -->|"rsync + overlay"| DC
    CX -->|"rsync + overlay"| DX
```
<!-- AI-SYMBIOTE:END architecture:subsystems -->

## Platform Overlay

플랫폼 차이는 `platforms/<name>/overlay/`에서 관리합니다.

- Claude: `.claude-plugin/plugin.json`, `hooks/hooks.json` (SessionStart, PreToolUse, PostToolUse)
- Codex: `.codex-plugin/plugin.json`, `hooks/hooks.json` (SessionStart, PreToolUse만 지원)

### Hooks 이벤트 매핑

| 이벤트 | 매처 | 스크립트 | Claude | Codex | 비고 |
|--------|------|----------|--------|-------|------|
| SessionStart | — | setup-check.sh | O | O | context.md 전체 주입 + rule_prevented 분석 |
| PreToolUse | Bash | guard-shell.sh | O | O | 차단 시 우회 경로 제시 + harness-log 기록 |
| PostToolUse | Read\|Skill | usage-tracker.sh | O | X | |
| PostToolUse | Write\|Edit | harness-learn.sh | O | X | auto-loop FAIL 연동 + 확장자 패턴 학습 |
| PostToolUse | Write\|Edit | comment-checker.sh | O | X | |
| PostToolUse | Write\|Edit | messenger-notify.sh | O | X | |

Codex CLI는 PostToolUse에서 Bash 매처만 지원하므로 Read, Write, Edit, Skill 매처 훅은 Claude 전용입니다.

### Harness Log Schema

`harness-log.jsonl`은 두 가지 스키마 버전을 사용합니다:

- **v1** (`"v"` 필드 없음): `tool_error`, `repeated_error`, `churn`, `rule_created`
- **v2** (`"v":2`): `loop_verify_fail`, `guard_blocked`, `pattern_*`, `rule_prevented`, `seed_loaded`

파서(gc, stats)는 알 수 없는 이벤트 타입을 gracefully skip합니다.

### Harness Seed Templates

`shared/harness-seeds/`에 스택별 초기 규칙 시드가 있습니다:

| 파일 | 대상 | 접두사 |
|------|------|--------|
| `generic.md` | 모든 프로젝트 | `[Seed #S1]` |
| `swift.md` | Swift/iOS | `[Seed #S1]` |
| `nextjs.md` | Next.js/React | `[Seed #S1]` |
| `python.md` | Python | `[Seed #S1]` |

`setup` 스킬이 감지된 스택에 맞는 시드를 context.md에 로딩합니다. `[Seed #SN]` 접두사는 자동 생성 규칙 `[Harness #N]`과 분리되어 gc에서 독립적으로 관리됩니다.

### Synapse Intent-Based Routing (v0.8.0)

Synapse 오케스트레이터는 v0.8.0부터 키워드 매칭 대신 **Intent Contract 기반 의도 라우팅**을 사용합니다.

```mermaid
flowchart TD
    A["사용자 요청"] --> B{"Skill Direct Routes?"}
    B -->|"매칭"| C["스킬 직접 실행"]
    B -->|"없음"| D{"Intent Contract"}
    D -->|"none"| E["직접 처리 (단순 작업)"]
    D -->|"analysis"| F["analysis 팀"]
    D -->|"implementation"| G["implementation 팀"]
    D -->|"review"| H["review 팀"]
    D -->|"planning"| I["planning 팀"]
    D -->|"research"| J["research 팀"]
    D -->|"dynamic"| K["dynamic 팀 (fallback)"]
```

각 팀 템플릿은 ADK 패턴이 명시적으로 매핑되어 있습니다:
- analysis: Parallel Fan-Out/Gather + Hierarchical
- implementation: Sequential Pipeline + Reflection + Retry/Fallback
- review: Parallel Fan-Out/Gather + Multi-Agent Collaboration
- planning: Sequential Pipeline + Planning
- research: Parallel Fan-Out/Gather + Routing
- dynamic: Routing + ReAct

### Scope Verification (Auto-Freeze)

auto-loop에서 Architect가 `## Affected Files` 섹션을 작성하면, Inspector가 Builder의 실제 변경과 비교하여 범위 밖 변경을 scope violation으로 보고합니다. `manifest.json`의 `autoFreeze: false`로 비활성화 가능합니다.

## Build Flow

<!-- AI-SYMBIOTE:START architecture:build-flow -->
빌드는 3단계로 구성됩니다:

1. **복사** — `shared/`의 skills, hooks, taskmaster, messenger-bridge, harness-seeds를 `rsync -a`로 대상 디렉터리에 복사
2. **오버레이** — `platforms/<name>/overlay/`를 같은 위치에 덮어쓰기 (plugin.json, hooks.json)
3. **검증** — `.claude-plugin/plugin.json` 또는 `.codex-plugin/plugin.json` 존재 확인

```mermaid
flowchart TD
    subgraph "1. 복사"
        S["shared/"] -->|"rsync -a"| T1["skills/ hooks/ taskmaster/<br/>messenger-bridge/ harness-seeds/"]
    end
    subgraph "2. 오버레이"
        T1 --> OV{"플랫폼?"}
        OV -->|"Claude"| CL["platforms/claude/overlay/<br/>(.claude-plugin/ + hooks/)"]
        OV -->|"Codex"| CX["platforms/codex/overlay/<br/>(.codex-plugin/ + hooks/)"]
    end
    subgraph "3. 출력"
        CL --> P["plugins/ai-symbiote/"]
        CL --> DC["dist/claude-symbiote/"]
        CX --> DX["dist/codex-symbiote/"]
    end
```

| 스크립트 | 출력 | 용도 |
|----------|------|------|
| `scripts/build-all.sh` | Claude + Codex 모두 | 릴리즈 전 필수 |
| `scripts/build-claude.sh` | `plugins/ai-symbiote/` + `dist/claude-symbiote/` | Claude만 |
| `scripts/build-codex.sh` | `dist/codex-symbiote/` | Codex만 |

CI(`ci.yml`)는 `build-all.sh` 후 `git diff --exit-code`로 빌드 산출물이 최신인지 검증합니다.
<!-- AI-SYMBIOTE:END architecture:build-flow -->

## State Strategy

모든 플랫폼은 `~/ai-symbiote/{slug}`를 공용 상태 루트로 사용합니다.

- 새 설치는 항상 `~/ai-symbiote/{slug}`를 기본값으로 사용
- 기존 `~/symbiote/{slug}`, `~/claude_symbiote/{slug}`, `~/codex_symbiote/{slug}`는 호환성 경로로만 유지

## Packaging Strategy

- 제품 이름: `ai-symbiote`
- Claude 플러그인 식별자: `ai-symbiote`
- Codex 플러그인 식별자: `ai-symbiote`
- 현재 버전: `0.8.1`

즉 저장소는 하나지만, 사용자에게 노출되는 플러그인 이름은 양쪽 모두 `ai-symbiote`로 통일됩니다.
