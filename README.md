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

### Claude Code

**방법 1: GitHub marketplace (권장)**

```text
/plugin marketplace add Jimmy-Jung/ai-symbiote
/plugin install ai-symbiote@ai-symbiote
```

**방법 2: 로컬 marketplace**

```text
/plugin marketplace add /path/to/ai-symbiote
/plugin install ai-symbiote@ai-symbiote
```

**방법 3: 설치 없이 즉시 로드**

```bash
claude --plugin-dir /path/to/ai-symbiote/plugins/ai-symbiote
```

매번 입력하지 않으려면 shell alias를 추가합니다:

```bash
# ~/.zshrc 또는 ~/.bashrc
alias claude='claude --plugin-dir /path/to/ai-symbiote/plugins/ai-symbiote'
```

**방법 4: CLI 비대화형 설치**

```bash
claude plugin install ai-symbiote@ai-symbiote --scope user
```

### Codex CLI

**방법 1: 프롬프트로 자동 설치**

Codex 세션에서 아래 프롬프트를 입력하면 자동으로 설치됩니다:

```text
https://github.com/Jimmy-Jung/ai-symbiote 저장소를 ~/ai-symbiote-repo에 클론하고 bash platforms/codex/install.sh를 실행해서 ai-symbiote 플러그인을 설치해줘
```

**방법 2: 직접 설치**

```bash
git clone https://github.com/Jimmy-Jung/ai-symbiote.git ~/ai-symbiote-repo
cd ~/ai-symbiote-repo && bash platforms/codex/install.sh
```

설치 스크립트가 다음을 자동 처리합니다:

- 플러그인 번들 빌드 및 복사 (`~/plugins/ai-symbiote/`)
- marketplace 등록 (`~/.agents/plugins/marketplace.json`)
- config.toml에 플러그인 활성화 + hooks 기능 플래그 설정
- Codex 캐시에 동기화

### 플랫폼 차이

| 항목 | Claude Code | Codex CLI |
|------|-------------|-----------|
| 플러그인 경로 | `${CLAUDE_PLUGIN_ROOT}` (자동) | `~/plugins/ai-symbiote` |
| Hooks 이벤트 | SessionStart, PreToolUse, PostToolUse (전체 매처) | SessionStart, PreToolUse (Bash 매처만) |
| Hooks 기능 | 기본 활성 | `config.toml`에 `codex_hooks = true` 필요 (install.sh가 자동 설정) |
| 스킬 호출 | `/ai-symbiote:setup` | `$ai-symbiote:setup` 또는 암시적 호출 |

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
