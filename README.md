# ai-symbiote

> Author: JunyoungJung

Claude Code와 Codex CLI에서 **동일한 스킬, 훅, 태스크 매니저**를 공유하는 AI 에이전트 오케스트레이션 플러그인입니다. 하나의 소스(`shared/`)를 관리하면 양쪽 플랫폼에서 같은 방식으로 동작합니다.

## 설치

### Claude Code

1. marketplace 등록:

```text
/plugin marketplace add Jimmy-Jung/ai-symbiote
```

2. 플러그인 설치:

```text
/plugin install ai-symbiote@ai-symbiote
```

로컬 저장소를 사용하려면:

```text
/plugin marketplace add /path/to/ai-symbiote
```

```text
/plugin install ai-symbiote@ai-symbiote
```

설치 없이 세션 한 번만 테스트:

```bash
claude --plugin-dir /path/to/ai-symbiote/plugins/ai-symbiote
```

### Codex CLI

Codex 세션에서 아래 프롬프트를 입력하면 자동으로 클론 + 설치됩니다:

```text
https://github.com/Jimmy-Jung/ai-symbiote 저장소를 ~/ai-symbiote-repo에 클론하고 bash platforms/codex/install.sh를 실행해서 ai-symbiote 플러그인을 설치해줘
```

직접 설치:

```bash
git clone https://github.com/Jimmy-Jung/ai-symbiote.git ~/ai-symbiote-repo
cd ~/ai-symbiote-repo && bash platforms/codex/install.sh
```

`install.sh`가 빌드, `~/plugins/ai-symbiote/` 복사, marketplace 등록, `config.toml` 설정(`codex_hooks = true` 포함)을 한 번에 처리합니다.

### 업데이트

양쪽 플랫폼 모두에서 `update` 스킬로 최신 버전으로 업데이트할 수 있습니다:

- Claude: `/ai-symbiote:update`
- Codex: `$ai-symbiote:update` 또는 "ai-symbiote 업데이트해줘"

저장소를 자동으로 pull하고 플랫폼에 맞게 재설치합니다.

## 스킬 목록

설치 후 사용할 수 있는 25개 스킬입니다. Claude에서는 `/ai-symbiote:<name>`, Codex에서는 `$ai-symbiote:<name>`으로 호출합니다.

### 핵심 워크플로우

| 스킬 | 설명 |
|------|------|
| `synapse` | 사용자 의도를 분석하여 적절한 스킬과 팀을 자동 선택하는 오케스트레이터 |
| `auto-loop` | Analyze → Plan → Execute → Verify를 반복하여 작업을 자율 완료 (최대 10회) |
| `autopilot` | auto-loop의 병렬 극대화 모드. Builder를 최대한 동시 투입 (최대 3회) |
| `setup` | 프로젝트 스택 감지, 연동 플러그인 자동 설치, 상태 디렉터리 초기화 |

### 계획 및 분석

| 스킬 | 설명 |
|------|------|
| `plan` | Scout 2명 + Architect 1명으로 구현 계획을 수립 |
| `planning` | 요구사항 인터뷰, 영향도 평가, 계획 템플릿 등 계획 방법론 정의 |
| `analyze` | Scout 2~3명 + Architect 1명으로 대상을 심층 분석 |
| `deep-search` | Grep, Glob, Agent(Explore)를 병렬 3-Track으로 코드베이스 탐색 |

### 코드 품질

| 스킬 | 설명 |
|------|------|
| `review` | 현재 변경사항에 대해 코드 리뷰 실행 |
| `code-accuracy` | 심볼 존재 확인, import 검증, 환각 코드 방지 가드레일 |
| `verify-loop` | 자율 루프의 4-Level 완료 기준과 재시도 전략 정의 |

### Git 및 협업

| 스킬 | 설명 |
|------|------|
| `git-commit` | git diff를 분석하여 Conventional Commits 형식으로 커밋 메시지 생성 |
| `pr` | 현재 브랜치의 변경사항을 분석하고 Pull Request 생성 |
| `messenger` | Slack, Discord, Telegram 연동으로 세션 모니터링 및 원격 제어 |

### 태스크 관리

| 스킬 | 설명 |
|------|------|
| `tm-init` | Task Master 전역 task graph 초기화 |
| `tm-parse-prd` | `prd.json`을 읽어 작업별 `task.json` 초안 생성 |
| `tm-board` | task graph를 상태별로 요약 표시 |

### 유틸리티

| 스킬 | 설명 |
|------|------|
| `note` | Compaction 내성 메모장. 컨텍스트 윈도우 초과 시에도 정보 보존 |
| `evolve` | 프로젝트 변경을 감지하여 `manifest.json`과 `context.md` 동기화 |
| `update` | 저장소 pull + 플랫폼별 재설치를 자동 수행 |
| `clean` | 완료된 작업의 상태 폴더 정리 |
| `skill-store` | 커뮤니티 스킬 카탈로그(1,060+개)에서 프로젝트에 맞는 스킬 추천/설치 |
| `stats` | 스킬/커맨드 사용 빈도 분석 |

### 내부 스킬 (synapse가 자동 참조)

| 스킬 | 설명 |
|------|------|
| `roles` | Scout, Architect, Builder, Inspector, Researcher, Codex 6개 역할의 계약 정의 |
| `team-templates` | analysis, implementation, review, planning, research, dynamic 6개 팀 템플릿 |

## 디렉터리 구조

```text
ai-symbiote/
├── shared/                    # 공용 원본 (여기만 편집)
│   ├── skills/                #   25개 스킬
│   ├── hooks/scripts/         #   훅 스크립트 (setup-check, guard-shell 등)
│   ├── taskmaster/            #   PRD/task 스키마 및 템플릿
│   └── messenger-bridge/      #   Slack/Discord/Telegram 브릿지
├── platforms/
│   ├── claude/
│   │   └── overlay/           #   .claude-plugin/plugin.json, hooks/hooks.json
│   └── codex/
│       └── overlay/           #   .codex-plugin/plugin.json, hooks/hooks.json
├── plugins/
│   └── ai-symbiote/           # Claude marketplace용 번들 (빌드 생성물, 직접 편집 금지)
├── scripts/
│   ├── build-claude.sh        #   shared + claude overlay → plugins/ai-symbiote/
│   ├── build-codex.sh         #   shared + codex overlay → dist/codex-symbiote/
│   └── build-all.sh
└── .claude-plugin/
    └── marketplace.json       # Claude marketplace 카탈로그
```

### 빌드 흐름

```
shared/  ──rsync──▶  plugins/ai-symbiote/   (Claude용, Git에 포함)
   +
claude/overlay/

shared/  ──rsync──▶  dist/codex-symbiote/   (Codex용, Git 미포함)
   +
codex/overlay/
```

빌드 명령:

```bash
bash scripts/build-all.sh      # 양쪽 모두
bash scripts/build-claude.sh   # Claude만
bash scripts/build-codex.sh    # Codex만
```

## 플랫폼 차이

| 항목 | Claude Code | Codex CLI |
|------|-------------|-----------|
| 플러그인 경로 | `${CLAUDE_PLUGIN_ROOT}` (자동 제공) | `~/plugins/ai-symbiote` |
| Hooks 이벤트 | SessionStart, PreToolUse, PostToolUse | SessionStart, PreToolUse |
| PostToolUse 매처 | Read, Write\|Edit, Bash 등 전체 | Bash만 지원 |
| Hooks 활성화 | 기본 활성 | `config.toml`에 `codex_hooks = true` 필요 |
| 스킬 호출 | `/ai-symbiote:setup` | `$ai-symbiote:setup` 또는 암시적 호출 |
| 연동 플러그인 설치 | `claude plugin install` | `git clone` + 로컬 등록 |

Codex에서 PostToolUse의 Read, Write|Edit 매처가 지원되지 않으므로, usage-tracker, comment-checker, messenger-notify 훅은 Claude에서만 동작합니다.

## 상태 저장

모든 플랫폼은 `~/ai-symbiote/{slug}/`를 공용 상태 루트로 사용합니다.

### Slug 규칙

slug는 **git 루트 디렉터리의 basename**을 소문자로 변환하여 생성합니다:

```
/home/user/projects/MyApp  →  myapp
/home/user/work/api-server →  api-server
```

같은 이름의 프로젝트가 다른 경로에 존재하면, `manifest.json`의 `path` 필드로 충돌을 감지하고 부모 디렉터리를 접두어로 추가합니다.

### 상태 디렉터리 구조

```text
~/ai-symbiote/{slug}/
├── manifest.json       # 프로젝트 스택, 설정, 경로, 연동 플러그인 상태
├── context.md          # 동적 컨텍스트 (스택, 컨벤션)
├── state/              # 작업별 상태 (ralph-state.md, 결과 파일)
├── taskmaster/         # PRD, task graph
├── usage-data/         # 스킬/커맨드 사용 통계
└── messenger/          # 메신저 브릿지 설정, 커맨드, 승인 요청
```

### 연동 플러그인

setup 시 자동으로 설치/확인되는 외부 플러그인:

| 플러그인 | 용도 | 필수 여부 |
|----------|------|-----------|
| [snarktank/ralph](https://github.com/snarktank/ralph) | PRD 생성(`/prd`) 및 JSON 변환(`/ralph`) | 자동 설치 |
| [openai/codex-plugin-cc](https://github.com/openai/codex-plugin-cc) | Codex(GPT-5.4) 서브에이전트 연동 | 선택적 |

## 유지보수 원칙

- **공용 변경**: `shared/`만 수정 → `build-all.sh`로 양쪽 번들 갱신
- **플랫폼 차이**: `platforms/<name>/overlay/`만 수정
- **빌드 생성물**: `plugins/ai-symbiote/`와 `dist/`는 직접 편집 금지
- **상세 구조**: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) 참조
