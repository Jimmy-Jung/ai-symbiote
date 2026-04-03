---
name: setup
description: 프로젝트 부트스트랩. 코드베이스를 분석하여 프로젝트 스택을 감지하고 공용 Symbiote 상태를 초기화합니다.
argument-hint:
user-invocable: true
allowed-tools: [Read, Write, Edit, Glob, Grep, Bash]
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

## 기본 워크플로우

1. 위 규칙으로 프로젝트 slug를 계산합니다.
2. `~/ai-symbiote/{slug}/` 디렉터리를 만듭니다.
3. `usage-data/`, `state/`, `taskmaster/`, `messenger/`를 초기화합니다.
4. `manifest.json`을 생성하고, `projectPath` 필드에 프로젝트 절대 경로를 기록합니다.
5. `context.md` 생성 준비 상태를 점검합니다.
6. 후속 안내를 출력합니다.

### manifest.json 필수 필드

```json
{
  "path": "/absolute/path/to/project",
  "agentPlatforms": ["claude", "codex"]
}
```

`path`는 프로젝트의 절대 경로이며 slug 충돌 감지에 사용됩니다. 반드시 포함하세요.

## manifest.json의 platform 필드

ai-symbiote는 Claude와 Codex를 **동시에** 사용하는 멀티 플랫폼 플러그인입니다.

`manifest.json`의 `agentPlatforms` 필드는 항상 양쪽 모두를 포함해야 합니다:

```json
{
  "agentPlatforms": ["claude", "codex"]
}
```

**규칙:**
- 단일 플랫폼(`"claude"` 또는 `"codex"`)만 기록하지 마세요.
- 기존 manifest에 이미 `agentPlatforms`가 있으면 덮어쓰지 말고 병합하세요.
- 현재 세션이 어느 플랫폼에서 실행 중인지와 관계없이 항상 `["claude", "codex"]`를 유지합니다.
