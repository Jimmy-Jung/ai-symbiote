# ai-symbiote

> Author: JunyoungJung
> Date: 2026-04-02

`ai-symbiote`는 Claude와 Codex가 함께 사용하는 단일 플러그인 소스입니다. 공용 자산은 `shared/`에 두고, 플랫폼 차이는 `platforms/`의 오버레이와 설치 스크립트로 분리합니다.

## 개요

- 플러그인 이름: `ai-symbiote`
- 공용 상태 경로: `~/ai-symbiote/{project-slug}`
- 공용 자산: `skills`, `hooks`, `taskmaster`, `messenger-bridge`
- 플랫폼 지원: Claude marketplace, Codex local plugin

## 디렉터리 구조

```text
ai-symbiote/
├── .claude-plugin/
│   └── marketplace.json
├── docs/
│   └── ARCHITECTURE.md
├── plugins/
│   └── ai-symbiote/          # Claude marketplace용 로컬 번들
├── shared/
│   ├── skills/
│   ├── hooks/
│   ├── taskmaster/
│   └── messenger-bridge/
├── platforms/
│   ├── claude/
│   │   ├── overlay/
│   │   └── install.sh
│   └── codex/
│       ├── overlay/
│       └── install.sh
├── scripts/
│   ├── build-claude.sh
│   ├── build-codex.sh
│   └── build-all.sh
```

## 빌드

```bash
bash scripts/build-claude.sh
```

```bash
bash scripts/build-codex.sh
```

```bash
bash scripts/build-all.sh
```

생성물:
- `plugins/ai-symbiote/`: Claude marketplace가 직접 읽는 로컬 번들
- `dist/claude-symbiote/`: Claude 검증/테스트용 생성물
- `dist/codex-symbiote/`: Codex 설치용 생성물

`dist/`는 생성물이며 저장소에서 유지하지 않습니다.

## 설치

Claude:

```text
/plugin marketplace add Jimmy-Jung/ai-symbiote
/plugin install ai-symbiote@ai-symbiote
```

Claude 로컬 marketplace 테스트:

```text
/plugin marketplace add /Users/jimmy/Documents/GitHub/ai-symbiote
/plugin install ai-symbiote@ai-symbiote
```

Claude 로컬 번들 준비:

```bash
bash platforms/claude/install.sh
```

Codex:

```bash
bash platforms/codex/install.sh
```

## 상태 저장

모든 플랫폼은 같은 상태 루트를 사용합니다: `~/ai-symbiote/{project-slug}/`

여기에 저장되는 항목:

- `manifest.json`
- `context.md`
- `state/`
- `taskmaster/`
- `usage-data/`
- `messenger/`

기존 `~/symbiote/{slug}`, `~/claude_symbiote/{slug}`, `~/codex_symbiote/{slug}`는 fallback 경로로만 읽습니다.

## 유지보수 원칙

- 공용 변경은 `shared/`만 수정
- 플랫폼 차이는 `platforms/claude/overlay`, `platforms/codex/overlay`만 수정
- 빌드 후 생성된 `plugins/ai-symbiote`와 `dist/`는 직접 편집하지 않음
- 구조 설명이 더 필요하면 [ARCHITECTURE.md](/Users/jimmy/Documents/GitHub/ai-symbiote/docs/ARCHITECTURE.md)를 기준 문서로 사용
