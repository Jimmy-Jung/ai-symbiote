---
name: evolve
description: 프로젝트 변경사항을 감지하여 manifest.json과 context.md를 동기화합니다. 의존성 추가, 프레임워크 변경, 아키텍처 변화를 반영합니다. Triggers on: 프로젝트 업데이트, 상태 동기화, 스택 변경, evolve.
argument-hint:
user-invocable: true
allowed-tools: [Read, Write, Edit, Glob, Grep, Bash, Agent]
---

# Evolve -- 프로젝트 상태 동기화

프로젝트 코드베이스의 현재 상태를 감지하여 manifest.json과 context.md를 최신으로 갱신합니다.
setup이 초기 1회 스냅샷이라면, evolve는 주기적 동기화입니다.

## 진입 조건

`~/ai-symbiote/{slug}/manifest.json`이 존재해야 합니다.
존재하지 않으면: "먼저 setup 워크플로우로 프로젝트를 초기화해주세요." 안내.

## 워크플로우

### Step 1: 기준선 로드

현재 manifest.json을 읽어 기존 상태를 기준선으로 확보합니다.

```
기준선 항목:
- project.languages
- project.platforms
- stack.packageManager
- stack.buildTool
- stack.frameworks
- stack.architecture
- stack.testFramework
- stack.cicd
- plugins.ralph.installed
- plugins.codex.installed
- plugins.codex.cliReady
```

### Step 2: 6-Track 병렬 재감지

setup의 Step 1과 동일한 감지를 재실행합니다.
Glob, Grep, Read를 병렬로 실행합니다.

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

### Step 3: 플러그인 상태 확인

```bash
# ralph
(
  rg -l '"name"[[:space:]]*:[[:space:]]*"(ralph|ralph-skills)"' \
    "$HOME/.agents/plugins" \
    "$HOME/plugins" \
    ./.agents/plugins \
    ./plugins 2>/dev/null || true
) | head -1 | grep -q . && echo "ralph:installed" || echo "ralph:not-installed"

# codex runtime
codex --version 2>/dev/null && echo "codex-cli:ready" || echo "codex-cli:not-ready"
```

### Step 4: Diff 생성

기준선(Step 1)과 재감지 결과(Step 2~3)를 비교합니다.

변경 유형:
- `[추가]` 새로 감지된 항목 (기준선에 없음)
- `[제거]` 더 이상 감지되지 않는 항목 (기준선에 있었음)
- `[변경]` 값이 달라진 항목

변경이 없으면: "프로젝트 상태가 최신입니다. 변경사항이 없습니다." 출력 후 종료.

### Step 5: 변경 리포트

변경된 항목만 사용자에게 보고합니다:

```
[Evolve] 프로젝트 변경사항 감지:

언어:
  [추가] Rust (Cargo.toml 감지)

프레임워크:
  [추가] Tailwind CSS (tailwind.config 감지)
  [제거] Bootstrap (import 패턴 미감지)

아키텍처:
  [변경] Layered -> Clean Architecture (/domain/, /data/ 디렉터리 감지)

CI/CD:
  [추가] GitHub Actions (.github/workflows/ci.yml 감지)

플러그인:
  [변경] codex CLI 준비 완료 (cliReady: false -> true)

이 변경사항을 manifest.json과 context.md에 반영하시겠습니까? (yes/no):
```

### Step 6: 갱신 (사용자 승인 시)

1. manifest.json 갱신:
   - 변경된 필드만 업데이트
   - `lastEvolved` 타임스탬프를 현재 시간으로 갱신

2. context.md 재생성:
   - 갱신된 manifest 기반으로 context.md를 재작성
   - 기존 context.md의 수동 추가 섹션은 보존 (있으면)
   - 프로젝트 스택 요약, 코딩 컨벤션, 파일 네이밍 패턴, 아키텍처 패턴

3. 완료 보고:
   ```
   [Evolve] 완료:
   - manifest.json 갱신됨
   - context.md 갱신됨
   - lastEvolved: {ISO8601}
   ```

## 자동 권장 (setup-check 훅 연동)

setup-check 훅에서 다음 조건일 때 evolve 실행을 권장합니다 (자동 실행 아님):

- `lastEvolved`가 7일 이상 경과
- 주요 의존성 파일(package.json, requirements.txt 등)의 mtime이 lastEvolved보다 최근

권장 메시지:
```
프로젝트 상태가 {N}일 전에 마지막으로 동기화되었습니다.
evolve 워크플로우로 최신 상태를 확인하세요.
```

## 원칙

- 자동 실행 금지: 항상 사용자에게 변경 리포트를 보여주고 승인을 받음
- 기준선 보존: diff 방식으로 변경된 항목만 표시 (전체 재출력 아님)
- 수동 추가 보존: context.md에 사용자가 직접 추가한 내용은 유지
- 최소 변경: 변경이 없으면 파일을 건드리지 않음
