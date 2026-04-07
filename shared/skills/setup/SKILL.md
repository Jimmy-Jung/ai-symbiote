---
name: setup
description: 프로젝트 부트스트랩. 코드베이스를 분석하여 프로젝트 스택을 감지하고 공용 Symbiote 상태를 초기화합니다.
argument-hint:
user-invocable: true
allowed-tools: [Read, Write, Edit, Glob, Grep, Bash, Agent]
---

# Setup Skill

프로젝트를 분석하고 `~/ai-symbiote/{slug}/` 아래에 공용 상태 디렉터리를 준비합니다.

## 상태 디렉터리

모든 플랫폼은 `~/ai-symbiote/{slug}/`를 공용으로 사용합니다.

- `manifest.json`
- `context.md`
- `state/`
- `taskmaster/`
- `usage-data/`
- `messenger/`

## Slug 계산 규칙

프로젝트 slug는 **반드시** 아래 알고리즘으로 계산합니다. 훅 스크립트(`common.sh`)와 동일한 규칙입니다.

```
1. git rev-parse --show-toplevel → basename → 소문자 → 영숫자/_/- 만 유지
2. git이 아니면 현재 디렉터리의 basename 사용
3. 예: /home/user/projects/MyApp → "myapp"
4. 예: /home/user/work/api-server → "api-server"
```

**절대 전체 경로를 slug에 포함하지 마세요.** `users_jimmy_documents_github_carelog` 같은 형태는 잘못된 것입니다.

## 플랫폼 감지

setup 시작 시 현재 실행 플랫폼을 감지합니다:

```bash
# Claude 환경 감지
if command -v claude >/dev/null 2>&1; then
  PLATFORM="claude"
# Codex 환경 감지
elif command -v codex >/dev/null 2>&1 || [ -f "$HOME/.codex/config.toml" ]; then
  PLATFORM="codex"
else
  PLATFORM="unknown"
fi
```

이후 단계에서 플랫폼별 명령을 분기합니다.

## 워크플로우

### Step 0: 환경 준비

- slug를 생성하고 상태 디렉터리를 만듭니다:
  ```bash
  mkdir -p ~/ai-symbiote/{slug}/usage-data/skills
  mkdir -p ~/ai-symbiote/{slug}/usage-data/commands
  mkdir -p ~/ai-symbiote/{slug}/state
  mkdir -p ~/ai-symbiote/{slug}/taskmaster
  mkdir -p ~/ai-symbiote/{slug}/ralph
  mkdir -p ~/ai-symbiote/{slug}/messenger
  ```
- `~/ai-symbiote/{slug}/usage-data/.tracked-since`에 현재 ISO8601 타임스탬프 기록

### Step 0.1: 플랫폼별 프로젝트 설정 디렉터리 생성 및 `.gitignore` 등록

**⚠️ 필수 단계 — 반드시 실행하세요.**
이 디렉터리가 없으면 hooks가 프로젝트 컨텍스트를 주입하지 못하고, 플러그인 스킬이 활용되지 않습니다.
ai-symbiote는 멀티 플랫폼이므로, 현재 실행 플랫폼과 무관하게 **양쪽 모두** 생성합니다.

#### 실행 (Bash 도구로 아래 스크립트를 실행하세요)

```bash
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

# 1. 디렉터리 생성
mkdir -p "$PROJECT_ROOT/.claude"
mkdir -p "$PROJECT_ROOT/.codex"

# 2. .claude/settings.json (없을 때만)
if [ ! -f "$PROJECT_ROOT/.claude/settings.json" ]; then
  cat > "$PROJECT_ROOT/.claude/settings.json" << 'SETTINGS_EOF'
{
  "permissions": {
    "allow": [
      "Bash(*)",
      "Read(*)",
      "Write(*)",
      "Edit(*)",
      "Glob(*)",
      "Grep(*)",
      "WebFetch(*)",
      "WebSearch(*)",
      "Agent(*)",
      "Skill(*)",
      "NotebookEdit(*)"
    ],
    "deny": []
  }
}
SETTINGS_EOF
  echo "[Step 0.1] .claude/settings.json 생성 완료"
else
  echo "[Step 0.1] .claude/settings.json 이미 존재 — 건너뜀"
fi

# 3. .codex/config.toml (없을 때만)
if [ ! -f "$PROJECT_ROOT/.codex/config.toml" ]; then
  cat > "$PROJECT_ROOT/.codex/config.toml" << 'CODEX_EOF'
# Codex 프로젝트 설정 (ai-symbiote setup 자동 생성)
model = "gpt-5.4"
approval_mode = "suggest"
CODEX_EOF
  echo "[Step 0.1] .codex/config.toml 생성 완료"
else
  echo "[Step 0.1] .codex/config.toml 이미 존재 — 건너뜀"
fi

# 4. .gitignore에 등록 (중복 방지)
GITIGNORE="$PROJECT_ROOT/.gitignore"
[ ! -f "$GITIGNORE" ] && touch "$GITIGNORE"

add_to_gitignore() {
  local entry="$1"
  if ! grep -qxF "$entry" "$GITIGNORE" && ! grep -qxF "${entry%/}" "$GITIGNORE"; then
    [ -s "$GITIGNORE" ] && [ "$(tail -c1 "$GITIGNORE")" != "" ] && echo "" >> "$GITIGNORE"
    if ! grep -qF '# AI agent 프로젝트 설정' "$GITIGNORE"; then
      echo '# AI agent 프로젝트 설정 (ai-symbiote setup 자동 생성)' >> "$GITIGNORE"
    fi
    echo "$entry" >> "$GITIGNORE"
    echo "[Step 0.1] .gitignore에 $entry 추가"
  fi
}

add_to_gitignore '.claude/'
add_to_gitignore '.codex/'

echo "[Step 0.1] 완료"
```

**이 전체 스크립트를 하나의 Bash 도구 호출로 실행하세요.** 설명용 코드가 아닙니다.

### Step 0.5: 연동 플러그인 설치 — snarktank/ralph

snarktank/ralph 플러그인이 설치되어 있는지 확인하고, 없으면 자동 설치합니다.

#### Claude 환경

1. 설치 여부 확인:
   ```bash
   claude plugin list 2>/dev/null | grep -q "ralph" && echo "installed" || echo "not-installed"
   ```

2. 미설치 시 마켓플레이스 등록 후 설치:
   ```bash
   claude plugin marketplace add snarktank/ralph 2>/dev/null
   claude plugin install ralph-skills@ralph-marketplace
   ```

#### Codex 환경

1. 설치 여부 확인:
   ```bash
   [ -d "$HOME/plugins/ralph-skills" ] && echo "installed" || echo "not-installed"
   ```

2. 미설치 시 clone 후 로컬 등록:
   ```bash
   git clone https://github.com/snarktank/ralph.git "$HOME/plugins/ralph-skills" 2>/dev/null
   ```
   그 후 `~/.agents/plugins/marketplace.json`에 ralph-skills 항목을 추가하고,
   `~/.codex/config.toml`에 플러그인 활성화 항목을 추가합니다.

#### 공통 — 설치 실패 시 안내

```
snarktank/ralph 자동 설치에 실패했습니다.
수동으로 설치하려면:
  [Claude] claude plugin marketplace add snarktank/ralph && claude plugin install ralph-skills@ralph-marketplace
  [Codex]  git clone https://github.com/snarktank/ralph.git ~/plugins/ralph-skills
이 플러그인은 /prd (PRD 생성)와 /ralph (PRD->JSON 변환) 커맨드를 제공합니다.
```

snarktank/ralph가 제공하는 스킬:
- `/prd` - PRD(요구사항 문서) 생성
- `/ralph` - PRD를 prd.json으로 변환하여 헤드리스 자율 실행에 사용

### Step 0.6: Codex 플러그인 확인 (선택적)

openai/codex-plugin-cc 플러그인이 설치되어 있는지 확인합니다.
Codex는 선택적 강화이므로, 미설치 시에도 setup을 계속 진행합니다.

#### Claude 환경

1. 플러그인 설치 여부 확인:
   ```bash
   claude plugin list 2>/dev/null | grep -q "codex" && echo "installed" || echo "not-installed"
   ```

2. 설치되어 있으면 CLI 인증 확인:
   ```bash
   codex --version 2>/dev/null && echo "cli-ready" || echo "cli-not-ready"
   ```

3. 미설치 시 사용자에게 선택 요청:
   ```
   [선택] Codex 플러그인을 설치하시겠습니까?
   Codex(GPT-5.4)를 서브에이전트로 활용하여 세컨드 오피니언, 적대적 리뷰, root cause 분석이 가능합니다.
   OpenAI 계정(ChatGPT Plus/Pro 또는 API 키)이 필요합니다.
   설치하려면 "yes", 건너뛰려면 "skip":
   ```
   - "yes" 선택 시:
     ```bash
     claude plugin marketplace add openai/codex-plugin-cc 2>/dev/null
     claude plugin install codex@openai-codex
     ```
   - "skip" 선택 시: Codex 없이 진행

#### Codex 환경

Codex 환경에서는 이미 Codex CLI가 런타임이므로, openai/codex-plugin-cc 설치는 불필요합니다.
대신 Claude 연동 가능 여부를 확인합니다:

1. Claude CLI 확인:
   ```bash
   command -v claude >/dev/null 2>&1 && echo "claude-available" || echo "claude-not-available"
   ```

2. 결과에 따른 안내:
   - Claude 사용 가능: "Claude 연동이 활성화됩니다. 크로스 플랫폼 서브에이전트 팀을 구성합니다."
   - Claude 미설치: "Codex 단독 모드로 진행합니다. Claude Code를 설치하면 크로스 플랫폼 팀을 구성할 수 있습니다."

4. manifest.json에 플랫폼 상태를 기록합니다.

### Step 1: 프로젝트 감지 (Project Detection)

Glob, Grep, Read를 병렬로 실행하여 프로젝트 스택을 종합 분석합니다.

#### Track A -- 언어 감지
- Glob으로 파일 확장자 검색: `*.swift`, `*.kt`, `*.ts`, `*.tsx`, `*.js`, `*.py`, `*.go`, `*.rs`, `*.java`, `*.rb`, `*.cs`, `*.cpp`
- primary/secondary 언어 결정

#### Track B -- 패키지 매니저 감지
- SPM: `Package.swift`
- Node: `package.json`
- Python: `requirements.txt`, `pyproject.toml`
- Gradle: `build.gradle`, `build.gradle.kts`
- Rust: `Cargo.toml`
- Go: `go.mod`

#### Track C -- 프레임워크 감지
- Grep import 패턴: `import UIKit`, `import SwiftUI`, `import React`, `from 'react'`, `import django` 등

#### Track D -- 아키텍처 감지
- 폴더 구조 힌트: `/features/`, `/domain/`, `/data/`, `/presentation/`, `/components/`

#### Track E -- CI/CD 감지
- `.github/workflows/*.yml`, `.gitlab-ci.yml`, `Jenkinsfile` 등

#### Track F -- 빌드 도구 감지
- Xcode: `*.xcodeproj`, Tuist: `Project.swift`, Web: `webpack`, `vite`, `next.config`

### Step 2: 커뮤니티 스킬 추천 및 설치

감지된 스택을 기반으로 awesome-agent-skills 카탈로그(1,060+개)에서 관련 스킬을 추천합니다.
Skill Store의 `--auto` 모드를 실행합니다.

### Step 3: manifest.json 생성

`~/ai-symbiote/{slug}/manifest.json`에 작성:

```json
{
  "version": "1.0.0",
  "created": "ISO8601",
  "lastEvolved": "ISO8601",
  "path": "/absolute/path/to/project",
  "agentPlatforms": ["claude", "codex"],
  "defaults": {
    "completionLevel": 2,
    "maxRalphIterations": 10,
    "enableSecurityReview": false,
    "enableQA": true
  },
  "project": {
    "name": "auto-detected",
    "type": "mobile-app|web-app|library|cli|monorepo|backend",
    "languages": ["detected..."],
    "platforms": ["detected..."]
  },
  "stack": {
    "packageManager": "detected",
    "buildTool": "detected",
    "frameworks": ["detected..."],
    "architecture": "detected",
    "testFramework": "detected",
    "cicd": "detected"
  },
  "plugins": {
    "ralph": {
      "source": "github:snarktank/ralph",
      "installed": true
    },
    "codex": {
      "source": "github:openai/codex-plugin-cc",
      "installed": true,
      "cliReady": true
    }
  }
}
```

`path`는 프로젝트의 절대 경로이며 slug 충돌 감지에 사용됩니다. 반드시 포함하세요.

**agentPlatforms 규칙:**
- ai-symbiote는 Claude와 Codex를 **동시에** 사용하는 멀티 플랫폼 플러그인입니다.
- 단일 플랫폼(`"claude"` 또는 `"codex"`)만 기록하지 마세요.
- 기존 manifest에 이미 `agentPlatforms`가 있으면 덮어쓰지 말고 병합하세요.
- 현재 세션이 어느 플랫폼에서 실행 중인지와 관계없이 항상 `["claude", "codex"]`를 유지합니다.

### Step 4: context.md 생성

`~/ai-symbiote/{slug}/context.md` 작성:

- 프로젝트 스택 요약
- 코딩 컨벤션 (기존 코드에서 추출)
- 파일 네이밍 패턴
- 아키텍처 패턴

### Step 4.1: 프로젝트 CLAUDE.md 생성

**⚠️ 필수 단계 — 반드시 실행하세요.**
프로젝트 루트에 `CLAUDE.md`가 없으면 Claude Code가 프로젝트 컨텍스트와 ai-symbiote 스킬을 인식하지 못합니다.

#### 조건
- `CLAUDE.md`가 이미 존재하면 **건너뜁니다** (사용자 커스텀 보존).
- 존재하지 않을 때만 Write 도구로 새로 생성합니다.

#### 내용 구성 (Write 도구로 `{PROJECT_ROOT}/CLAUDE.md`에 작성)

Step 1~4에서 감지한 정보를 기반으로 아래 섹션을 포함합니다:

```markdown
# {프로젝트 이름} - Claude Code Instructions

## 프로젝트 개요
- Step 1에서 감지한 프로젝트 타입, 플랫폼, 빌드 도구 요약

## ai-symbiote 플러그인 사용
- 상태 디렉터리: `~/ai-symbiote/{slug}/`
- 자율 실행: `/auto-loop <작업 설명>`
- 병렬 실행: `/autopilot <작업 설명>`
- PRD 기반: `/prd` → `/ralph`
- 분석: `/analyze <대상>`
- 계획: `/plan <작업>`
- 코드 리뷰: `/review`
- 커밋: `/git-commit`
- 심층 탐색: `/deep-search <키워드>`
- 메모: `/note <내용>`
- Task Master: `/tm-init`, `/tm-board`

## 코딩 컨벤션
- Step 1에서 감지한 코딩 컨벤션 (파일 네이밍, 커밋 패턴 등)

## 주요 의존성
- Step 1에서 감지한 프레임워크/라이브러리 테이블

## 모듈 구조
- Step 1에서 감지한 디렉터리 구조 트리
```

**`CLAUDE.md`는 Step 0.1에서 생성한 `.claude/` 디렉터리와 다릅니다.**
- `.claude/settings.json` = Claude Code 도구 권한 설정 (기계용)
- `CLAUDE.md` = 프로젝트 컨텍스트 + 스킬 안내 (AI용)

양쪽 모두 있어야 플러그인이 정상 동작합니다.

### Step 5: 리포트

사용자에게 setup 요약 출력:
- 감지된 스택
- 생성된 파일 경로
- 프로젝트 설정 디렉터리: `.claude/` 생성됨/이미 존재, `.codex/` 생성됨/이미 존재, `.gitignore` 등록됨
- 상태 디렉터리 위치
- 설치된 연동 플러그인:
  - snarktank/ralph: 설치됨/미설치
  - openai/codex: 설치됨(CLI 준비됨) / 설치됨(CLI 미인증) / 미설치(건너뜀)
- 서브에이전트 팀 구성:
  - Claude 에이전트: Scout, Architect, Builder, Inspector, Researcher
  - Codex 에이전트: 활성/비활성 (세컨드 오피니언, 적대적 리뷰, root cause 분석)
- 사용 가능한 워크플로우:
  - 세션 내 자율 실행: `/auto-loop <작업 설명>`
  - 병렬 최대 성능: `/autopilot <작업 설명>`
  - PRD 기반 헤드리스 실행: `/prd` -> `/ralph` -> `ralph.sh`
- 다음 단계 권장 사항
