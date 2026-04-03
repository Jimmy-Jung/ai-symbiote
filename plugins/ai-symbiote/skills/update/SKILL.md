---
name: update
description: ai-symbiote 플러그인을 최신 버전으로 업데이트합니다. Triggers on: 업데이트, update, 플러그인 업데이트, 최신 버전.
user-invocable: true
---

# Update -- 플러그인 자동 업데이트

ai-symbiote 저장소를 pull하고 현재 플랫폼에 맞게 재설치합니다.

## 워크플로우

### Step 1: 저장소 찾기

다음 순서로 ai-symbiote 저장소 경로를 탐색합니다:

```bash
# 1. 환경 변수
echo "${AI_SYMBIOTE_REPO:-}"

# 2. 기본 경로
for candidate in ~/ai-symbiote-repo ~/Documents/GitHub/ai-symbiote; do
  [ -d "$candidate/.git" ] && echo "$candidate" && break
done
```

저장소를 찾지 못하면:

```text
ai-symbiote 저장소를 찾을 수 없습니다.
클론 후 설치하려면:
  git clone https://github.com/Jimmy-Jung/ai-symbiote.git ~/ai-symbiote-repo
  cd ~/ai-symbiote-repo && bash platforms/codex/install.sh
```

### Step 2: 최신 소스 가져오기

```bash
cd <repo-path>
git fetch origin
git pull origin main
```

충돌 발생 시 사용자에게 보고하고 중단합니다.

### Step 3: 플랫폼 감지 및 재설치

현재 세션이 어느 플랫폼인지 감지합니다:

- `CLAUDE_PLUGIN_ROOT` 환경 변수가 있으면 → Claude
- 그 외 → Codex

**Claude:**

```bash
bash <repo-path>/scripts/build-claude.sh
```

빌드 후 사용자에게 안내:

```text
빌드 완료. 플러그인을 업데이트하려면:
/plugin update ai-symbiote@ai-symbiote
```

**Codex:**

```bash
bash <repo-path>/platforms/codex/install.sh
```

### Step 4: 버전 확인

```bash
# 설치된 버전 확인
cat <repo-path>/platforms/codex/overlay/.codex-plugin/plugin.json | grep version
# 또는
cat <repo-path>/platforms/claude/overlay/.claude-plugin/plugin.json | grep version
```

완료 보고:

```text
[Update] ai-symbiote 업데이트 완료
- 버전: {version}
- 플랫폼: {claude/codex}
- 저장소: {repo-path}
```
