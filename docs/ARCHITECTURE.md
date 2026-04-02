# Architecture

`ai-symbiote`는 공용 코어와 플랫폼 오버레이를 분리한 구조를 사용합니다.

## Core

`shared/`는 플랫폼에 독립적인 자산을 담습니다.

- `skills/`
- `hooks/`
- `taskmaster/`
- `messenger-bridge/`

이 디렉터리의 내용은 Claude 번들과 Codex 번들 모두에 공통으로 들어갑니다.

## Platform Overlay

플랫폼 차이는 `platforms/<name>/overlay/`에서 관리합니다.

- Claude: `.claude-plugin/plugin.json`, Claude용 문서/메타데이터
- Codex: `.codex-plugin/plugin.json`, Codex용 문서/메타데이터

## Build Flow

1. `shared/` 자산을 `dist/<platform-plugin-name>/`으로 복사
2. `platforms/<name>/overlay/`를 같은 위치에 덮어쓰기
3. 결과 번들을 설치 스크립트에서 사용

## State Strategy

모든 플랫폼은 `~/ai-symbiote/{slug}`를 공용 상태 루트로 사용합니다.

- 새 설치는 항상 `~/ai-symbiote/{slug}`를 기본값으로 사용
- 기존 `~/symbiote/{slug}`, `~/claude_symbiote/{slug}`, `~/codex_symbiote/{slug}`는 호환성 경로로만 유지

## Packaging Strategy

- 제품 이름: `ai-symbiote`
- Claude 플러그인 식별자: `ai-symbiote`
- Codex 플러그인 식별자: `ai-symbiote`

즉 저장소는 하나지만, 사용자에게 노출되는 플러그인 이름은 양쪽 모두 `ai-symbiote`로 통일됩니다.
