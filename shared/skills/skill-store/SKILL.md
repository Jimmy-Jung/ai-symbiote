---
name: skill-store
description: "프로젝트 스택에 맞는 커뮤니티 스킬을 추천하고 설치합니다. awesome-agent-skills 카탈로그(1,060+개)에서 프레임워크, 서비스, 도메인별로 탐색합니다. Triggers on: 스킬 추천, 스킬 설치, skill store, recommend skills, 스킬 스토어, 스킬 탐색."
user-invocable: true
argument-hint: [search query | --auto | --list <category>]
allowed-tools: [Read, Write, Bash, Glob, Grep, Agent]
---

# Skill Store

프로젝트 스택에 맞는 커뮤니티 스킬을 추천하고 설치합니다.
소스: [VoltAgent/awesome-agent-skills](https://github.com/VoltAgent/awesome-agent-skills) (1,060+개 스킬)

## 카탈로그

현재 플러그인 루트의 `skills/skill-store/catalog.json`에 기술 스택별 추천 매핑이 저장되어 있습니다.

카탈로그 구조:
- `stacks`: 언어/프레임워크별 추천 (nextjs, react, react-native, swift, python, typescript, rust, go, java, dotnet)
- `services`: 서비스별 추천 (supabase, neon, stripe, cloudflare, netlify, vercel, terraform, sanity, wordpress, sentry, figma 등)
- `domains`: 도메인별 추천 (security, ai, scraping, marketing, product, document, video, design)

## 사용 모드

### 모드 1: 자동 추천 (`--auto`)

`~/ai-symbiote/{slug}/manifest.json`을 읽어 감지된 스택을 기반으로 자동 추천합니다.

워크플로우:
1. manifest.json에서 `project.languages`, `stack.frameworks`, `stack.packageManager` 읽기
2. catalog.json의 `stacks`에서 언어/프레임워크 매칭
3. 프로젝트의 의존성 파일(package.json, requirements.txt 등)을 스캔하여 서비스 감지:
   - `@supabase/supabase-js` -> supabase 추천
   - `stripe` -> stripe 추천
   - `@sentry/node` -> sentry 추천
   - `better-auth` -> betterauth 추천
   - `@cloudflare/workers-types` -> cloudflare 추천
   - `@netlify/functions` -> netlify 추천
   - `sanity` -> sanity 추천
   - `terraform` (*.tf 파일) -> terraform 추천
4. 매칭된 스킬 목록을 번호와 함께 표시
5. 사용자가 번호로 선택하면 설치 실행

출력 형식:
```
[Skill Store] 프로젝트 분석 결과 추천 스킬:

프레임워크:
  1. Next.js Best Practices (vercel/next-best-practices)
  2. React Best Practices (vercel/react-best-practices)

서비스:
  3. Supabase Postgres Best Practices (supabase-community/postgres-best-practices)
  4. Stripe Best Practices (nickcopi/stripe-best-practices)

설치할 스킬 번호를 선택하세요 (예: 1,3,4 또는 "all"):
```

### 모드 2: 검색 (`skill-store <query>`)

키워드로 스킬을 검색합니다. 3단계 폴백으로 반드시 결과를 찾습니다.

예시:
- `skill-store security` -> Trail of Bits 보안 스킬 22개 추천
- `skill-store ai` -> Hugging Face, fal.ai, Replicate, Gemini 추천
- `skill-store marketing` -> 마케팅 스킬 30개+ 추천
- `skill-store figma` -> Figma 디자인 스킬 추천
- `skill-store xcode build` -> 카탈로그에 없으면 GitHub/웹에서 자동 검색

워크플로우 (3단계 폴백):

#### Step 1: 로컬 카탈로그 검색
- 쿼리를 catalog.json의 stacks, services, domains 키와 매칭
- 매칭 결과가 있으면 표시 후 사용자 선택

#### Step 2: awesome-agent-skills 원본 검색 (Step 1에서 결과 없을 때)
- awesome-agent-skills README를 WebFetch로 가져와 쿼리와 매칭:
  ```
  WebFetch(url: "https://raw.githubusercontent.com/VoltAgent/awesome-agent-skills/main/README.md")
  ```
- 매칭 결과가 있으면 표시 후 사용자 선택

#### Step 3: GitHub/웹 검색 (Step 2에서도 결과 없을 때)
- GitHub에서 관련 스킬/플러그인을 검색:
  ```
  WebSearch(query: "{query} claude code skill site:github.com")
  WebSearch(query: "{query} (plugin OR agent skill) site:github.com")
  ```
- 검색 결과에서 `.claude-plugin` 또는 `.codex-plugin` 디렉터리가 있는 레포를 우선 검토
- 후보 레포를 사용자에게 표시:
  ```
  [Skill Store] 카탈로그에 "{query}" 관련 스킬이 없어 GitHub에서 검색했습니다:

    1. {owner}/{repo} - {description} (stars: N)
    2. {owner}/{repo} - {description} (stars: N)

  설치할 번호를 선택하세요 (건너뛰려면 "skip"):
  ```
- 검색 결과도 없으면:
  ```
  [Skill Store] "{query}" 관련 스킬을 찾지 못했습니다.
  직접 GitHub에서 검색하거나 스킬을 만들어 보세요:
  https://github.com/search?q={query}+codex+skill&type=repositories
  ```

### 모드 3: 카테고리 목록 (`--list <category>`)

특정 카테고리의 모든 스킬을 나열합니다.

- `skill-store --list stacks` -> 언어/프레임워크별 전체 목록
- `skill-store --list services` -> 서비스별 전체 목록
- `skill-store --list domains` -> 도메인별 전체 목록

### 모드 4: 전체 카탈로그 업데이트 (`--update`)

awesome-agent-skills README를 WebFetch로 가져와 catalog.json을 최신화합니다.

## 설치 방법

선택된 스킬을 설치할 때는 현재 플랫폼을 감지하여 적절한 방법을 사용합니다:

### Claude 환경

```bash
# 1. 마켓플레이스 등록 (이미 등록되어 있으면 무시)
claude plugin marketplace add {owner}/{repo} 2>/dev/null

# 2. 플러그인 설치 (plugin.json의 name 필드 참조)
claude plugin install {plugin-name}@{marketplace-name}

# 설치 실패 시 수동 안내
echo "수동 설치: https://github.com/{owner}/{repo} 참고"
```

### Codex 환경

```bash
# 1. 저장소 clone
git clone https://github.com/{owner}/{repo} ~/plugins/{repo}

# 2. 플러그인 manifest 확인
find ~/plugins/{repo} -maxdepth 2 \( -path "*/.claude-plugin/plugin.json" -o -path "*/.codex-plugin/plugin.json" \)

# 3. marketplace.json에 항목 추가 후 config.toml에서 활성화
```

참고:
- Claude 계열은 `.claude-plugin/plugin.json`과 marketplace 등록 흐름을 사용합니다.
- Codex 계열은 `.codex-plugin/plugin.json`과 local marketplace/config 동기화 흐름을 사용합니다.
- 플러그인 이름은 각 manifest의 `name` 필드 기준입니다.

설치 후:
- manifest.json의 `plugins` 섹션에 설치 기록 추가
- 사용자에게 설치된 스킬의 사용법 안내

## setup 연동

`setup` 워크플로우 실행 시 Step 2 (플랫폼별 스킬팩 요청) 단계에서 자동으로 `--auto` 모드가 실행됩니다:

1. 프로젝트 스택 감지 완료 후
2. catalog.json 기반으로 추천 스킬 목록 생성
3. 사용자에게 추천 스킬 표시
4. 선택한 스킬 설치
5. manifest.json에 기록

## 원칙

- 강제 설치하지 않음 (항상 사용자 선택)
- 3단계 폴백: 로컬 카탈로그 → awesome-agent-skills 원본 → GitHub/웹 검색
- 카탈로그에 없는 스킬도 반드시 GitHub/웹 검색으로 탐색
- 설치 실패 시 수동 설치 방법 안내
- 이미 설치된 스킬은 중복 설치하지 않음
- GitHub 검색 시 `.claude-plugin` 또는 `.codex-plugin` 디렉터리가 있는 레포를 우선
