# Architecture

`ai-symbiote`는 공용 코어와 플랫폼 오버레이를 분리한 구조를 사용합니다.

## Core

`shared/`는 플랫폼에 독립적인 자산을 담습니다.

- `skills/` — 27개 스킬 정의
- `hooks/scripts/` — 훅 스크립트 6개 (setup-check, guard-shell, usage-tracker, harness-learn, comment-checker, messenger-notify)
- `hooks/scripts/lib/common.sh` — 훅 공용 라이브러리
- `taskmaster/` — PRD/task/state JSON 스키마 및 템플릿
- `messenger-bridge/` — Telegram/Slack/Discord 브릿지 (TypeScript)

이 디렉터리의 내용은 Claude 번들과 Codex 번들 모두에 공통으로 들어갑니다.

## Platform Overlay

플랫폼 차이는 `platforms/<name>/overlay/`에서 관리합니다.

- Claude: `.claude-plugin/plugin.json`, `hooks/hooks.json` (SessionStart, PreToolUse, PostToolUse)
- Codex: `.codex-plugin/plugin.json`, `hooks/hooks.json` (SessionStart, PreToolUse만 지원)

### Hooks 이벤트 매핑

| 이벤트 | 매처 | 스크립트 | Claude | Codex |
|--------|------|----------|--------|-------|
| SessionStart | — | setup-check.sh | O | O |
| PreToolUse | Bash | guard-shell.sh | O | O |
| PostToolUse | Read\|Skill | usage-tracker.sh | O | X |
| PostToolUse | Write\|Edit | harness-learn.sh | O | X |
| PostToolUse | Write\|Edit | comment-checker.sh | O | X |
| PostToolUse | Write\|Edit | messenger-notify.sh | O | X |

Codex CLI는 PostToolUse에서 Bash 매처만 지원하므로 Read, Write, Edit, Skill 매처 훅은 Claude 전용입니다.

## Build Flow

1. `shared/` 자산을 빌드 대상으로 복사
2. `platforms/<name>/overlay/`를 같은 위치에 덮어쓰기
3. 결과 번들을 설치 스크립트에서 사용

빌드 출력:

| 스크립트 | 출력 경로 | 용도 |
|----------|-----------|------|
| `build-claude.sh` | `plugins/ai-symbiote/` + `dist/claude-symbiote/` | Claude marketplace 번들 (Git에 포함) |
| `build-codex.sh` | `dist/codex-symbiote/` | Codex 설치용 번들 |
| `build-all.sh` | 위 두 가지 모두 | 전체 빌드 |

## State Strategy

모든 플랫폼은 `~/ai-symbiote/{slug}`를 공용 상태 루트로 사용합니다.

- 새 설치는 항상 `~/ai-symbiote/{slug}`를 기본값으로 사용
- 기존 `~/symbiote/{slug}`, `~/claude_symbiote/{slug}`, `~/codex_symbiote/{slug}`는 호환성 경로로만 유지

## Packaging Strategy

- 제품 이름: `ai-symbiote`
- Claude 플러그인 식별자: `ai-symbiote`
- Codex 플러그인 식별자: `ai-symbiote`
- 현재 버전: `0.5.5`

즉 저장소는 하나지만, 사용자에게 노출되는 플러그인 이름은 양쪽 모두 `ai-symbiote`로 통일됩니다.
