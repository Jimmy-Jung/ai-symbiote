#!/usr/bin/env bash
# Generate numbered developer docs for first-time contributors.
#
# NOTE:
# - This script is the fallback baseline for Codex bundles and standalone execution.
# - The richer Claude workflow in SKILL.md remains the primary source of truth.
# - The output is intentionally ordered for onboarding: README hub + 00..07 docs.
# - Set AI_SYMBIOTE_DOC_LANG=ko|en to force fallback output language.
#
# Usage:
#   generate-dev-docs.sh [repo-root] [all|readme|start|overview|architecture|build|features|conventions|troubleshooting|operations|onboarding|dependencies|flows ...]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UPDATER="$SCRIPT_DIR/update-doc-section.sh"

if [ ! -x "$UPDATER" ]; then
  echo "error: updater helper not executable: $UPDATER" >&2
  exit 1
fi

PRIMARY_DOCS="readme start overview architecture build features conventions troubleshooting operations"

canonical_doc_id() {
  case "$1" in
    readme) echo "readme" ;;
    start|onboarding) echo "start" ;;
    overview) echo "overview" ;;
    architecture) echo "architecture" ;;
    build|dependencies) echo "build" ;;
    features) echo "features" ;;
    conventions) echo "conventions" ;;
    troubleshooting) echo "troubleshooting" ;;
    operations|flows) echo "operations" ;;
    *) return 1 ;;
  esac
}

if [ "$#" -gt 0 ] && [ -d "$1" ]; then
  REPO_ROOT="$(cd "$1" && pwd)"
  shift
else
  REPO_ROOT="$(pwd)"
fi

SELECTED_DOCS=""
if [ "$#" -eq 0 ]; then
  SELECTED_DOCS="$PRIMARY_DOCS"
else
  for arg in "$@"; do
    if [ "$arg" = "all" ]; then
      SELECTED_DOCS="$PRIMARY_DOCS"
      break
    fi
    if canonical=$(canonical_doc_id "$arg" 2>/dev/null); then
      case " $SELECTED_DOCS " in
        *" $canonical "*) ;;
        *) SELECTED_DOCS="$SELECTED_DOCS $canonical" ;;
      esac
    else
      echo "warning: unknown doc target '$arg' ignored" >&2
    fi
  done
  SELECTED_DOCS="$(printf '%s\n' "$SELECTED_DOCS" | xargs)"
fi

if [ -z "$SELECTED_DOCS" ]; then
  echo "error: no valid doc targets selected" >&2
  exit 1
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

count_dirs() {
  local dir="$1"
  [ -d "$dir" ] || { echo 0; return; }
  find "$dir" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' '
}

count_files() {
  local dir="$1"
  [ -d "$dir" ] || { echo 0; return; }
  find "$dir" -maxdepth 1 -type f | wc -l | tr -d ' '
}

count_matching_files() {
  local dir="$1"
  local pattern="$2"
  [ -d "$dir" ] || { echo 0; return; }
  find "$dir" -maxdepth 1 -type f -name "$pattern" | wc -l | tr -d ' '
}

detect_repo_doc_language() {
  local sample
  sample="$(cat \
    "$REPO_ROOT/README.md" \
    "$REPO_ROOT/docs/00-시작하기.md" \
    "$REPO_ROOT/docs/01-프로젝트-개요.md" \
    "$REPO_ROOT/docs/02-아키텍처.md" \
    "$REPO_ROOT/docs/03-빌드-및-실행.md" \
    "$REPO_ROOT/docs/04-주요-기능.md" \
    "$REPO_ROOT/docs/05-코딩-컨벤션.md" \
    "$REPO_ROOT/docs/06-문제해결-가이드.md" \
    "$REPO_ROOT/docs/07-운영-흐름-및-배포.md" 2>/dev/null || true)"
  if printf '%s' "$sample" | grep -q '[가-힣]'; then
    echo "ko"
  else
    echo "ko"
  fi
}

resolve_doc_language() {
  case "${AI_SYMBIOTE_DOC_LANG:-}" in
    ko|kr|KO|KR) echo "ko" ;;
    en|eng|EN|ENG) echo "en" ;;
    *) detect_repo_doc_language ;;
  esac
}

tr_text() {
  local key="$1"
  case "$DOC_LANG:$key" in
    en:fallback_prefix) echo "### Needs verification: " ;;
    en:fallback_known) echo "- Confirmed so far: " ;;
    en:fallback_ambiguous) echo "- Why it is ambiguous: " ;;
    en:fallback_next) echo "- Check next: related scripts, overlays, existing docs" ;;
    en:readme_intro) echo "README is the hub. The numbered docs are the real onboarding path." ;;
    en:readme_table_order) echo "Order" ;;
    en:readme_table_doc) echo "Document" ;;
    en:readme_table_purpose) echo "Purpose" ;;
    en:readme_note) echo "This numbered doc set is updated by the \`dev-docs\` skill using marker blocks." ;;
    *)
      case "$key" in
        fallback_prefix) echo "### 확인 필요: " ;;
        fallback_known) echo "- 현재 확인한 사실: " ;;
        fallback_ambiguous) echo "- 애매한 이유: " ;;
        fallback_next) echo "- 다음 확인 위치: 관련 스크립트, overlay, 기존 문서" ;;
        readme_intro) echo "README는 허브입니다. 실제 온보딩은 아래 번호형 문서 순서로 진행하면 됩니다." ;;
        readme_table_order) echo "순서" ;;
        readme_table_doc) echo "문서" ;;
        readme_table_purpose) echo "목적" ;;
        readme_note) echo "이 문서 세트는 \`dev-docs\` 스킬이 마커 블록 기준으로 갱신합니다." ;;
      esac
      ;;
  esac
}

DOC_LANG="$(resolve_doc_language)"

dir_flag() {
  [ -d "$1" ] && echo yes || echo no
}

file_flag() {
  [ -f "$1" ] && echo yes || echo no
}

SKILL_COUNT="$(count_dirs "$REPO_ROOT/shared/skills")"
HOOK_SCRIPT_COUNT="$(count_matching_files "$REPO_ROOT/shared/hooks/scripts" '*.sh')"
BUILD_SCRIPT_COUNT="$(count_matching_files "$REPO_ROOT/scripts" 'build-*.sh')"
TEST_COUNT="$(count_matching_files "$REPO_ROOT/tests" 'test-*.sh')"
SEED_COUNT="$(count_matching_files "$REPO_ROOT/shared/harness-seeds" '*.md')"
HAS_CLAUDE_OVERLAY="$(dir_flag "$REPO_ROOT/platforms/claude/overlay")"
HAS_CODEX_OVERLAY="$(dir_flag "$REPO_ROOT/platforms/codex/overlay")"
HAS_MESSENGER_DOC="$(file_flag "$REPO_ROOT/docs/08-메신저-브릿지.md")"

write_block() {
  local file="$1"
  local doc_id="$2"
  local section_id="$3"
  local heading="$4"
  local content_file="$5"
  bash "$UPDATER" "$file" "$doc_id" "$section_id" "$heading" "$content_file"
}

ensure_doc_file() {
  local file="$1"
  local title="$2"
  local intro="$3"
  if [ ! -f "$file" ]; then
    mkdir -p "$(dirname "$file")"
    {
      printf '# %s\n\n' "$title"
      printf '%s\n' "$intro"
    } > "$file"
  fi
}

write_fallback_block() {
  local file="$1"
  local doc_id="$2"
  local section_id="$3"
  local heading="$4"
  local title="$5"
  local reason="$6"
  local evidence="$7"
  local content="$TMP_DIR/${doc_id}-${section_id}-fallback.md"
  cat > "$content" <<EOF
$(tr_text fallback_prefix)${title}

$(tr_text fallback_known)${evidence}
$(tr_text fallback_ambiguous)${reason}
$(tr_text fallback_next)
EOF
  write_block "$file" "$doc_id" "$section_id" "$heading" "$content"
}

generate_readme() {
  local file="$REPO_ROOT/README.md"
  local content="$TMP_DIR/readme-docs-map.md"
  if [ "$DOC_LANG" = "en" ]; then
    cat > "$content" <<EOF
$(tr_text readme_intro)

| $(tr_text readme_table_order) | $(tr_text readme_table_doc) | $(tr_text readme_table_purpose) |
|------|------|------|
| 00 | [docs/00-시작하기.md](docs/00-시작하기.md) | first-day path |
| 01 | [docs/01-프로젝트-개요.md](docs/01-프로젝트-개요.md) | project context |
| 02 | [docs/02-아키텍처.md](docs/02-아키텍처.md) | system structure |
| 03 | [docs/03-빌드-및-실행.md](docs/03-빌드-및-실행.md) | build and install path |
| 04 | [docs/04-주요-기능.md](docs/04-주요-기능.md) | core capabilities |
| 05 | [docs/05-코딩-컨벤션.md](docs/05-코딩-컨벤션.md) | edit boundaries |
| 06 | [docs/06-문제해결-가이드.md](docs/06-문제해결-가이드.md) | recovery path |
| 07 | [docs/07-운영-흐름-및-배포.md](docs/07-운영-흐름-및-배포.md) | release flow |
EOF
    if [ "$HAS_MESSENGER_DOC" = "yes" ]; then
      cat >> "$content" <<'EOF'
| 08 | [docs/08-메신저-브릿지.md](docs/08-메신저-브릿지.md) | remote operations |
EOF
    fi
  else
    cat > "$content" <<EOF
$(tr_text readme_intro)

| $(tr_text readme_table_order) | $(tr_text readme_table_doc) | $(tr_text readme_table_purpose) |
|------|------|------|
| 00 | [docs/00-시작하기.md](docs/00-시작하기.md) | 첫날 경로 |
| 01 | [docs/01-프로젝트-개요.md](docs/01-프로젝트-개요.md) | 프로젝트 맥락 |
| 02 | [docs/02-아키텍처.md](docs/02-아키텍처.md) | 시스템 구조 |
| 03 | [docs/03-빌드-및-실행.md](docs/03-빌드-및-실행.md) | 빌드와 설치 경로 |
| 04 | [docs/04-주요-기능.md](docs/04-주요-기능.md) | 핵심 기능 |
| 05 | [docs/05-코딩-컨벤션.md](docs/05-코딩-컨벤션.md) | 수정 경계 |
| 06 | [docs/06-문제해결-가이드.md](docs/06-문제해결-가이드.md) | 복구 경로 |
| 07 | [docs/07-운영-흐름-및-배포.md](docs/07-운영-흐름-및-배포.md) | 릴리즈 흐름 |
EOF
    if [ "$HAS_MESSENGER_DOC" = "yes" ]; then
      cat >> "$content" <<'EOF'
| 08 | [docs/08-메신저-브릿지.md](docs/08-메신저-브릿지.md) | 원격 운영 |
EOF
    fi
  fi
  cat >> "$content" <<EOF

$(tr_text readme_note)
EOF
  write_block "$file" readme docs-map "## 개발자 문서" "$content"
}

generate_start() {
  local file="$REPO_ROOT/docs/00-시작하기.md"
  if [ "$DOC_LANG" = "en" ]; then
    ensure_doc_file "$file" "00. Getting Started" "This document gives first-time contributors the shortest path through the repository."
  else
    ensure_doc_file "$file" "00. 시작하기" "이 문서는 처음 이 저장소를 여는 개발자가 가장 먼저 따라야 할 순서를 정리합니다."
  fi

  local quick="$TMP_DIR/start-quick.md"
  if [ "$DOC_LANG" = "en" ]; then
    cat > "$quick" <<'EOF'
The goal for a first-time contributor is not to read everything. The goal is to complete the minimum path that makes the structure visible and the build reproducible.

1. skim `README.md` for the project purpose
2. read `docs/01-프로젝트-개요.md` and `docs/02-아키텍처.md`
3. `python3 scripts/version_sync.py --check`
4. `bash scripts/build-all.sh`
5. `bash tests/test-dev-docs-skill.sh && bash tests/test-dev-docs-updater.sh`
EOF
  else
    cat > "$quick" <<'EOF'
처음 보는 개발자에게 필요한 것은 전체를 다 읽는 것이 아니라, 빌드가 되고 구조가 보이는 최소 경로를 먼저 통과하는 것입니다. 이 문서는 그 최소 경로만 모아 둡니다.

1. `README.md`에서 프로젝트 목적을 빠르게 훑기
2. `docs/01-프로젝트-개요.md`와 `docs/02-아키텍처.md` 읽기
3. `python3 scripts/version_sync.py --check`
4. `bash scripts/build-all.sh`
5. `bash tests/test-dev-docs-skill.sh && bash tests/test-dev-docs-updater.sh`
EOF
  fi

  local first_day="$TMP_DIR/start-first-day.md"
  if [ "$DOC_LANG" = "en" ]; then
    cat > "$first_day" <<'EOF'
```mermaid
flowchart LR
    A["README"] --> B["01-Project Overview"]
    B --> C["02-Architecture"]
    C --> D["03-Build and Run"]
    D --> E["build-all.sh + baseline tests"]
    E --> F["04-Key Features"]
    F --> G["target code to edit"]
```
EOF
  else
    cat > "$first_day" <<'EOF'
```mermaid
flowchart LR
    A["README"] --> B["01-프로젝트-개요"]
    B --> C["02-아키텍처"]
    C --> D["03-빌드-및-실행"]
    D --> E["build-all.sh + 기본 테스트"]
    E --> F["04-주요-기능"]
    F --> G["수정 대상 코드"]
```
EOF
  fi

  local checks="$TMP_DIR/start-checks.md"
  if [ "$DOC_LANG" = "en" ]; then
    cat > "$checks" <<EOF
| Check | Command | Purpose |
|------|------|------|
| version sync | \`python3 scripts/version_sync.py --check\` | confirm VERSION and release metadata are aligned |
| bundle build | \`bash scripts/build-all.sh\` | rebuild Claude and Codex artifacts |
| doc contract | \`bash tests/test-dev-docs-skill.sh\` | validate the doc skill contract |
| updater contract | \`bash tests/test-dev-docs-updater.sh\` | validate marker replacement behavior |

Visible automation assets:
- skills: ${SKILL_COUNT}
- hook/utility scripts: ${HOOK_SCRIPT_COUNT}
- build scripts: ${BUILD_SCRIPT_COUNT}
- test scripts: ${TEST_COUNT}
EOF
  else
    cat > "$checks" <<EOF
| 체크 | 명령 | 목적 |
|------|------|------|
| 버전 동기화 | \`python3 scripts/version_sync.py --check\` | VERSION과 release 메타데이터 일치 확인 |
| 번들 생성 | \`bash scripts/build-all.sh\` | Claude/Codex 산출물 갱신 |
| 문서 계약 | \`bash tests/test-dev-docs-skill.sh\` | 문서 스킬 계약 확인 |
| 업데이터 계약 | \`bash tests/test-dev-docs-updater.sh\` | 마커 치환 동작 확인 |

현재 확인 가능한 자동화 자산:
- 스킬: ${SKILL_COUNT}개
- 훅/유틸 스크립트: ${HOOK_SCRIPT_COUNT}개
- 빌드 스크립트: ${BUILD_SCRIPT_COUNT}개
- 테스트 스크립트: ${TEST_COUNT}개
EOF
  fi

  if [ "$DOC_LANG" = "en" ]; then
    write_block "$file" start quick-start "## Quick Start" "$quick"
    write_block "$file" start first-day-path "## First-Day Path" "$first_day"
    write_block "$file" start local-checks "## What To Verify Immediately" "$checks"
  else
    write_block "$file" start quick-start "## 빠른 시작" "$quick"
    write_block "$file" start first-day-path "## 첫날 경로" "$first_day"
    write_block "$file" start local-checks "## 바로 확인할 것" "$checks"
  fi
}

generate_overview() {
  local file="$REPO_ROOT/docs/01-프로젝트-개요.md"
  if [ "$DOC_LANG" = "en" ]; then
    ensure_doc_file "$file" "01. Project Overview" "This document helps a first-time contributor understand the product purpose and repository layout quickly."
  else
    ensure_doc_file "$file" "01. 프로젝트 개요" "이 문서는 프로젝트를 처음 보는 개발자가 제품 목적과 저장소 구성을 빠르게 이해하도록 돕습니다."
  fi

  local summary="$TMP_DIR/overview-summary.md"
  if [ "$DOC_LANG" = "en" ]; then
    cat > "$summary" <<'EOF'
`ai-symbiote` is an AI agent orchestration plugin that shares one core across Claude Code and Codex CLI. Its center of gravity is the harness: state files, hooks, skills, and logs are tied together so the agent can learn from repeated mistakes instead of repeating them forever.

```mermaid
flowchart LR
    A["user request"] --> B["synapse"]
    B --> C["skills"]
    C --> D["hooks"]
    D --> E["state dir"]
    C --> F["platform overlays"]
    F --> G["Claude / Codex bundles"]
```
EOF
  else
    cat > "$summary" <<'EOF'
`ai-symbiote`는 Claude Code와 Codex CLI에서 같은 공용 코어를 공유하는 AI 에이전트 오케스트레이션 플러그인입니다. 핵심은 에이전트가 반복 실수하지 않도록 상태 파일, 훅, 스킬, 로그를 하나의 하네스로 묶는 데 있습니다. 신규 개발자는 이 프로젝트를 "AI 에이전트 실행 환경 + 자동 학습 가드레일"로 이해하면 가장 빠릅니다.

```mermaid
flowchart LR
    A["사용자 요청"] --> B["synapse"]
    B --> C["skills"]
    C --> D["hooks"]
    D --> E["state dir"]
    C --> F["platform overlays"]
    F --> G["Claude / Codex bundles"]
```
EOF
  fi

  local repo_map="$TMP_DIR/overview-repo-map.md"
  if [ "$DOC_LANG" = "en" ]; then
    cat > "$repo_map" <<EOF
| Path | Role |
|------|------|
| \`shared/\` | shared skills, hooks, seeds, taskmaster, messenger bridge |
| \`platforms/\` | overlays that contain only Claude/Codex differences |
| \`scripts/\` | build and version-sync entry points |
| \`tests/\` | shell-based contract and regression tests |
| \`plugins/\`, \`dist/\` | generated build outputs |
| \`docs/\` | numbered developer docs |

- shared skill count: ${SKILL_COUNT}
- seed rule count: ${SEED_COUNT}
- platform overlays: Claude=${HAS_CLAUDE_OVERLAY}, Codex=${HAS_CODEX_OVERLAY}
EOF
  else
    cat > "$repo_map" <<EOF
| 경로 | 역할 |
|------|------|
| \`shared/\` | 공용 스킬, 훅, 시드, 태스크마스터, 메신저 브리지 |
| \`platforms/\` | Claude/Codex 차이만 담는 오버레이 |
| \`scripts/\` | 빌드/버전 동기화 진입점 |
| \`tests/\` | 셸 기반 계약/회귀 테스트 |
| \`plugins/\`, \`dist/\` | 빌드 결과물 |
| \`docs/\` | 번호형 개발자 문서 세트 |

- 공용 스킬 수: ${SKILL_COUNT}
- 시드 규칙 수: ${SEED_COUNT}
- 플랫폼 오버레이: Claude=${HAS_CLAUDE_OVERLAY}, Codex=${HAS_CODEX_OVERLAY}
EOF
  fi

  local journey="$TMP_DIR/overview-journey.md"
  if [ "$DOC_LANG" = "en" ]; then
    cat > "$journey" <<'EOF'
For a first pass through the project, keep this reading order.

1. `00-시작하기` — what to run first
2. `01-프로젝트-개요` — why the project is shaped this way
3. `02-아키텍처` — where each concern lives
4. `04-주요-기능` — what the system actually does
5. `07-운영-흐름-및-배포` — how a change reaches release
EOF
  else
    cat > "$journey" <<'EOF'
프로젝트를 빠르게 이해하려면 아래 문서 순서를 유지하는 편이 좋습니다.

1. `00-시작하기` — 당장 무엇을 실행해야 하는지
2. `01-프로젝트-개요` — 왜 이런 구조인지
3. `02-아키텍처` — 어디에 무엇이 있는지
4. `04-주요-기능` — 실제로 무엇을 해주는지
5. `07-운영-흐름-및-배포` — 변경이 어떻게 배포까지 이어지는지
EOF
  fi

  if [ "$DOC_LANG" = "en" ]; then
    write_block "$file" overview project-summary "## At a Glance" "$summary"
    write_block "$file" overview repo-map "## Repository Map" "$repo_map"
    write_block "$file" overview docs-journey "## Recommended Reading Order" "$journey"
  else
    write_block "$file" overview project-summary "## 한눈에 보기" "$summary"
    write_block "$file" overview repo-map "## 저장소 지도" "$repo_map"
    write_block "$file" overview docs-journey "## 추천 읽기 순서" "$journey"
  fi
}

generate_architecture() {
  local file="$REPO_ROOT/docs/02-아키텍처.md"
  if [ "$DOC_LANG" = "en" ]; then
    ensure_doc_file "$file" "02. Architecture" "This document explains the shared core, platform overlays, and state structure."
  else
    ensure_doc_file "$file" "02. 아키텍처" "이 문서는 공용 코어, 플랫폼 오버레이, 상태 구조를 설명합니다."
  fi

  local system="$TMP_DIR/architecture-system.md"
  if [ "$DOC_LANG" = "en" ]; then
    cat > "$system" <<'EOF'
The source of truth in this repository lives in `shared/` and `platforms/*/overlay/`. Build scripts merge those inputs into Claude/Codex bundles, and tests verify the outputs still match the source.

```mermaid
flowchart TD
    A["shared/"] --> B["platforms/claude/overlay"]
    A --> C["platforms/codex/overlay"]
    A --> D["scripts/build-*.sh"]
    D --> E["plugins/ai-symbiote/"]
    D --> F["dist/claude-symbiote/"]
    D --> G["dist/codex-symbiote/"]
```
EOF
  else
    cat > "$system" <<'EOF'
이 저장소의 실제 원본은 `shared/`와 `platforms/*/overlay/`입니다. 빌드 스크립트가 이 둘을 합쳐 Claude/Codex 번들을 만들고, 테스트가 그 산출물이 소스와 맞는지 확인합니다.

```mermaid
flowchart TD
    A["shared/"] --> B["platforms/claude/overlay"]
    A --> C["platforms/codex/overlay"]
    A --> D["scripts/build-*.sh"]
    D --> E["plugins/ai-symbiote/"]
    D --> F["dist/claude-symbiote/"]
    D --> G["dist/codex-symbiote/"]
```
EOF
  fi

  local subsystems="$TMP_DIR/architecture-subsystems.md"
  if [ "$DOC_LANG" = "en" ]; then
    cat > "$subsystems" <<EOF
\`\`\`mermaid
flowchart LR
    A["shared/skills (${SKILL_COUNT})"] --> B["orchestration"]
    A --> C["code work"]
    A --> D["docs / operations"]
    E["hooks/scripts (${HOOK_SCRIPT_COUNT})"] --> F["execution guards"]
    E --> G["learning / tracing"]
    H["harness-seeds (${SEED_COUNT})"] --> I["initial rules"]
\`\`\`

| Subsystem | Description |
|-----------|------|
| \`shared/skills/\` | skill definitions and helper scripts |
| \`shared/hooks/scripts/\` | guard, setup, learning, tracing, and security scripts |
| \`shared/harness-seeds/\` | stack-specific initial rules |
| \`shared/taskmaster/\` | PRD/task schema |
| \`shared/messenger-bridge/\` | Telegram/Slack/Discord bridge |
EOF
  else
    cat > "$subsystems" <<EOF
\`\`\`mermaid
flowchart LR
    A["shared/skills (${SKILL_COUNT})"] --> B["오케스트레이션"]
    A --> C["코드 작업"]
    A --> D["문서/운영"]
    E["hooks/scripts (${HOOK_SCRIPT_COUNT})"] --> F["실행 가드"]
    E --> G["학습/추적"]
    H["harness-seeds (${SEED_COUNT})"] --> I["초기 규칙"]
\`\`\`

| 서브시스템 | 설명 |
|-----------|------|
| \`shared/skills/\` | 스킬 정의와 보조 스크립트 |
| \`shared/hooks/scripts/\` | guard, setup, 학습, 추적, 보안 스크립트 |
| \`shared/harness-seeds/\` | 스택별 초기 규칙 |
| \`shared/taskmaster/\` | PRD/task 스키마 |
| \`shared/messenger-bridge/\` | Telegram/Slack/Discord 브리지 |
EOF
  fi

  local platform="$TMP_DIR/architecture-platform.md"
  if [ "$DOC_LANG" = "en" ]; then
    cat > "$platform" <<EOF
| Item | Claude | Codex |
|------|--------|-------|
| manifest path | \`platforms/claude/overlay/.claude-plugin/plugin.json\` | \`platforms/codex/overlay/.codex-plugin/plugin.json\` |
| hooks strength | can use Read/Skill, Write/Edit, and Bash matchers | PostToolUse is centered on Bash matchers |
| install script | \`platforms/claude/install.sh\` | \`platforms/codex/install.sh\` |

Current version sync line:
- Current version: \`$(cat "$REPO_ROOT/VERSION")\`
EOF
  else
    cat > "$platform" <<EOF
| 항목 | Claude | Codex |
|------|--------|-------|
| manifest 경로 | \`platforms/claude/overlay/.claude-plugin/plugin.json\` | \`platforms/codex/overlay/.codex-plugin/plugin.json\` |
| hooks 강점 | Read/Skill, Write/Edit, Bash 매처 사용 가능 | PostToolUse는 Bash 매처 중심 |
| 설치 스크립트 | \`platforms/claude/install.sh\` | \`platforms/codex/install.sh\` |

현재 버전 동기화 기준 줄:
- 현재 버전: \`$(cat "$REPO_ROOT/VERSION")\`
EOF
  fi

  if [ "$DOC_LANG" = "en" ]; then
    write_block "$file" architecture system-overview "## System Overview" "$system"
    write_block "$file" architecture subsystems "## Core Subsystems" "$subsystems"
    write_block "$file" architecture platform-differences "## Platform Differences" "$platform"
  else
    write_block "$file" architecture system-overview "## 시스템 개요" "$system"
    write_block "$file" architecture subsystems "## 핵심 서브시스템" "$subsystems"
    write_block "$file" architecture platform-differences "## 플랫폼 차이" "$platform"
  fi
}

generate_build() {
  local file="$REPO_ROOT/docs/03-빌드-및-실행.md"
  if [ "$DOC_LANG" = "en" ]; then
    ensure_doc_file "$file" "03. Build and Run" "This document explains the required tools and the build, install, and update paths."
  else
    ensure_doc_file "$file" "03. 빌드 및 실행" "이 문서는 필요한 도구와 빌드, 설치, 업데이트 경로를 정리합니다."
  fi

  local tools="$TMP_DIR/build-tools.md"
  if [ "$DOC_LANG" = "en" ]; then
    cat > "$tools" <<'EOF'
| Tool | Actual usage |
|------|----------------|
| `bash` | all build/test/hook scripts |
| `rsync` | bundle copy |
| `python3` | `scripts/version_sync.py`, install helpers |
| `git` | slug calculation, install/update, CI verification |
| `jq` | hook JSON parsing |
| `grep`, `sed`, `awk`, `find` | text processing and tests |
| `node`, `npm`, `tsc` | messenger bridge development/runtime |
EOF
  else
    cat > "$tools" <<'EOF'
| 도구 | 실제 사용 위치 |
|------|----------------|
| `bash` | build/test/hook 스크립트 전체 |
| `rsync` | 번들 복사 |
| `python3` | `scripts/version_sync.py`, 설치 보조 |
| `git` | slug 계산, 설치/업데이트, CI 검증 |
| `jq` | hook JSON 파싱 |
| `grep`, `sed`, `awk`, `find` | 텍스트 처리와 테스트 |
| `node`, `npm`, `tsc` | 메신저 브리지 개발/실행 |
EOF
  fi

  local build_flow="$TMP_DIR/build-flow.md"
  if [ "$BUILD_SCRIPT_COUNT" -gt 0 ]; then
    if [ "$DOC_LANG" = "en" ]; then
      cat > "$build_flow" <<'EOF'
```mermaid
flowchart LR
    A["version_sync.py --check"] --> B["build-all.sh"]
    B --> C["build-claude.sh"]
    B --> D["build-codex.sh"]
    C --> E["plugins/ + dist/claude"]
    D --> F["dist/codex"]
```

1. `python3 scripts/version_sync.py --check`
2. `bash scripts/build-all.sh`
3. run platform-specific install scripts if needed
EOF
    else
      cat > "$build_flow" <<'EOF'
```mermaid
flowchart LR
    A["version_sync.py --check"] --> B["build-all.sh"]
    B --> C["build-claude.sh"]
    B --> D["build-codex.sh"]
    C --> E["plugins/ + dist/claude"]
    D --> F["dist/codex"]
```

1. `python3 scripts/version_sync.py --check`
2. `bash scripts/build-all.sh`
3. 필요하면 플랫폼별 설치 스크립트 실행
EOF
    fi
  else
    write_fallback_block "$file" build build-run-flow "$( [ "$DOC_LANG" = "en" ] && echo "## Build Flow" || echo "## 빌드 흐름" )" \
      "빌드 흐름" \
      "$( [ "$DOC_LANG" = "en" ] && echo "build-*.sh evidence is missing." || echo "build-*.sh 근거가 부족합니다." )" \
      "build script 수=${BUILD_SCRIPT_COUNT}"
  fi

  local install="$TMP_DIR/build-install.md"
  if [ "$DOC_LANG" = "en" ]; then
    cat > "$install" <<EOF
| Goal | Command |
|------|------|
| local Claude install | \`bash platforms/claude/install.sh\` |
| local Codex install | \`bash platforms/codex/install.sh\` |
| rebuild shared bundles | \`bash scripts/build-all.sh\` |
| user update | \`/ai-symbiote:update\`, \`\$ai-symbiote:update\` |

- Claude overlay present: ${HAS_CLAUDE_OVERLAY}
- Codex overlay present: ${HAS_CODEX_OVERLAY}
EOF
  else
    cat > "$install" <<EOF
| 목적 | 명령 |
|------|------|
| Claude 로컬 설치 | \`bash platforms/claude/install.sh\` |
| Codex 로컬 설치 | \`bash platforms/codex/install.sh\` |
| 공용 번들 갱신 | \`bash scripts/build-all.sh\` |
| 사용자 업데이트 | \`/ai-symbiote:update\`, \`\$ai-symbiote:update\` |

- Claude overlay 존재: ${HAS_CLAUDE_OVERLAY}
- Codex overlay 존재: ${HAS_CODEX_OVERLAY}
EOF
  fi

  write_block "$file" build toolchain "$( [ "$DOC_LANG" = "en" ] && echo "## Required Tools" || echo "## 필요한 도구" )" "$tools"
  if [ -f "$build_flow" ]; then
    write_block "$file" build build-run-flow "$( [ "$DOC_LANG" = "en" ] && echo "## Build Flow" || echo "## 빌드 흐름" )" "$build_flow"
  fi
  write_block "$file" build install-update-path "$( [ "$DOC_LANG" = "en" ] && echo "## Install and Update" || echo "## 설치와 업데이트" )" "$install"
}

generate_features() {
  local file="$REPO_ROOT/docs/04-주요-기능.md"
  if [ "$DOC_LANG" = "en" ]; then
    ensure_doc_file "$file" "04. Key Features" "This document explains the core capabilities the project actually provides."
  else
    ensure_doc_file "$file" "04. 주요 기능" "이 문서는 이 프로젝트가 실제로 제공하는 핵심 기능을 설명합니다."
  fi

  local harness="$TMP_DIR/features-harness.md"
  if [ "$DOC_LANG" = "en" ]; then
    cat > "$harness" <<'EOF'
The center of the product is the harness. It injects project context at session start, blocks risky commands, stores failure patterns in logs, and turns repeated mistakes into reusable rules.

```mermaid
flowchart TD
    A["SessionStart"] --> B["setup-check.sh"]
    B --> C["inject context.md"]
    D["PreToolUse"] --> E["guard-shell.sh"]
    F["PostToolUse"] --> G["build-watcher / harness-learn / security-guard"]
    G --> H["harness-log.jsonl / security-log.jsonl"]
    H --> I["stats / gc / next session"]
```
EOF
  else
    cat > "$harness" <<'EOF'
핵심 기능은 하네스입니다. 프로젝트 컨텍스트를 세션 시작에 주입하고, 위험한 명령을 막고, 실패 패턴을 로그로 남기고, 반복 오류를 규칙으로 학습합니다.

```mermaid
flowchart TD
    A["SessionStart"] --> B["setup-check.sh"]
    B --> C["context.md 주입"]
    D["PreToolUse"] --> E["guard-shell.sh"]
    F["PostToolUse"] --> G["build-watcher / harness-learn / security-guard"]
    G --> H["harness-log.jsonl / security-log.jsonl"]
    H --> I["stats / gc / 다음 세션"]
```
EOF
  fi

  local orchestration="$TMP_DIR/features-orchestration.md"
  if [ "$DOC_LANG" = "en" ]; then
    cat > "$orchestration" <<'EOF'
`synapse` decides whether a request should route directly to a skill or be composed with a team template. `team-templates` and `roles` support analysis, implementation, review, planning, research, and dynamic flows.

| Axis | Role |
|----|------|
| `synapse` | intent routing |
| `team-templates` | team composition templates |
| `roles` | contracts for Scout, Architect, Builder, Inspector, Researcher, Codex |
| `auto` | autonomous execution loop |
EOF
  else
    cat > "$orchestration" <<'EOF'
`synapse`는 사용자 요청을 직접 스킬로 보낼지, 팀 템플릿으로 조합할지 판단합니다. `team-templates`와 `roles`는 analysis, implementation, review, planning, research, dynamic 흐름을 지원합니다.

| 축 | 역할 |
|----|------|
| `synapse` | 의도 라우팅 |
| `team-templates` | 팀 구성 템플릿 |
| `roles` | Scout, Architect, Builder, Inspector, Researcher, Codex 계약 |
| `auto` | 자율 실행 루프 |
EOF
  fi

  local skill_map="$TMP_DIR/features-skill-map.md"
  if [ "$DOC_LANG" = "en" ]; then
    cat > "$skill_map" <<'EOF'
Skills that matter first for a new contributor:

- `setup` — initialize the state directory and context
- `dev-docs` — refresh the numbered doc set
- `review` — review current changes
- `analyze` / `plan` — understand structure and plan implementation
- `security` — inspect the security baseline and current state
- `stats` / `gc` — inspect how the harness evolved over time
EOF
  else
    cat > "$skill_map" <<'EOF'
처음 보는 개발자가 먼저 알면 좋은 스킬:

- `setup` — 상태 디렉터리와 컨텍스트 초기화
- `dev-docs` — 번호형 문서 세트 갱신
- `review` — 현재 변경사항 코드 리뷰
- `analyze` / `plan` — 구조 파악과 구현 계획
- `security` — 보안 baseline과 상태 확인
- `stats` / `gc` — 하네스가 어떻게 진화했는지 확인
EOF
  fi

  write_block "$file" features harness-pillars "$( [ "$DOC_LANG" = "en" ] && echo "## Harness Pillars" || echo "## 하네스 핵심 축" )" "$harness"
  write_block "$file" features orchestration "$( [ "$DOC_LANG" = "en" ] && echo "## Orchestration" || echo "## 오케스트레이션" )" "$orchestration"
  write_block "$file" features key-skills "$( [ "$DOC_LANG" = "en" ] && echo "## Skills To Learn First" || echo "## 먼저 알아둘 스킬" )" "$skill_map"
}

generate_conventions() {
  local file="$REPO_ROOT/docs/05-코딩-컨벤션.md"
  if [ "$DOC_LANG" = "en" ]; then
    ensure_doc_file "$file" "05. Coding Conventions" "This document explains where to edit and how generated-output boundaries work."
  else
    ensure_doc_file "$file" "05. 코딩 컨벤션" "이 문서는 어디를 수정해야 하는지와 생성물 경계를 설명합니다."
  fi

  local decision="$TMP_DIR/conventions-decision.md"
  if [ "$DOC_LANG" = "en" ]; then
    cat > "$decision" <<'EOF'
```mermaid
flowchart TD
    A["change request"] --> B{"shared behavior?"}
    B -->|"yes"| C["shared/"]
    B -->|"no"| D{"platform-specific difference?"}
    D -->|"yes"| E["platforms/*/overlay/"]
    D -->|"no"| F{"AI-managed doc section?"}
    F -->|"yes"| G["dev-docs / updater"]
    F -->|"no"| H["scripts/ or tests/"]
```
EOF
  else
    cat > "$decision" <<'EOF'
```mermaid
flowchart TD
    A["변경 요청"] --> B{"공용 동작?"}
    B -->|"예"| C["shared/"]
    B -->|"아니오"| D{"플랫폼 차이?"}
    D -->|"예"| E["platforms/*/overlay/"]
    D -->|"아니오"| F{"문서 자동 구간?"}
    F -->|"예"| G["dev-docs / updater"]
    F -->|"아니오"| H["scripts/ 또는 tests/"]
```
EOF
  fi

  local editing="$TMP_DIR/conventions-editing.md"
  if [ "$DOC_LANG" = "en" ]; then
    cat > "$editing" <<'EOF'
- edit shared behavior in `shared/`
- keep platform differences in `platforms/*/overlay/`
- do not edit `plugins/` and `dist/` directly
- marker sections in docs are owned by `dev-docs`
- new skills should follow `shared/skills/<name>/SKILL.md`
EOF
  else
    cat > "$editing" <<'EOF'
- 공용 동작은 `shared/`에서 수정한다.
- 플랫폼 차이는 `platforms/*/overlay/`에 둔다.
- `plugins/`와 `dist/`는 직접 수정하지 않는다.
- 문서 마커 내부는 `dev-docs`가 관리한다.
- 새 스킬은 `shared/skills/<name>/SKILL.md` 구조를 따른다.
EOF
  fi

  local boundaries="$TMP_DIR/conventions-boundaries.md"
  if [ "$DOC_LANG" = "en" ]; then
    cat > "$boundaries" <<'EOF'
| Area | Edit directly |
|------|-----------|
| `shared/` | O |
| `platforms/*/overlay/` | O |
| `scripts/`, `tests/` | O |
| `plugins/`, `dist/` | X |
| inside docs marker blocks | X |
| outside docs marker blocks | O |
EOF
  else
    cat > "$boundaries" <<'EOF'
| 구역 | 직접 수정 |
|------|-----------|
| `shared/` | O |
| `platforms/*/overlay/` | O |
| `scripts/`, `tests/` | O |
| `plugins/`, `dist/` | X |
| docs 마커 블록 내부 | X |
| docs 마커 바깥 | O |
EOF
  fi

  write_block "$file" conventions decision-tree "$( [ "$DOC_LANG" = "en" ] && echo "## Where Should I Edit?" || echo "## 어디를 수정할까?" )" "$decision"
  write_block "$file" conventions editing-rules "$( [ "$DOC_LANG" = "en" ] && echo "## Editing Rules" || echo "## 편집 규칙" )" "$editing"
  write_block "$file" conventions generated-boundaries "$( [ "$DOC_LANG" = "en" ] && echo "## Generated Boundaries" || echo "## 생성물 경계" )" "$boundaries"
}

generate_troubleshooting() {
  local file="$REPO_ROOT/docs/06-문제해결-가이드.md"
  if [ "$DOC_LANG" = "en" ]; then
    ensure_doc_file "$file" "06. Troubleshooting Guide" "This document collects common failure modes and recovery paths for first-time contributors."
  else
    ensure_doc_file "$file" "06. 문제해결 가이드" "이 문서는 신규 개발자가 자주 마주치는 문제와 복구 경로를 정리합니다."
  fi

  local diagnosis="$TMP_DIR/troubleshooting-diagnosis.md"
  if [ "$DOC_LANG" = "en" ]; then
    cat > "$diagnosis" <<'EOF'
```mermaid
flowchart TD
    A["problem appears"] --> B{"version/build issue?"}
    B -->|"yes"| C["version_sync.py --check"]
    B -->|"no"| D{"docs/marker issue?"}
    D -->|"yes"| E["inspect test-dev-docs-*"]
    D -->|"no"| F{"state/session issue?"}
    F -->|"yes"| G["setup, stats, gc, clean"]
    F -->|"no"| H["read related hook / skill"]
```
EOF
  else
    cat > "$diagnosis" <<'EOF'
```mermaid
flowchart TD
    A["문제 발생"] --> B{"버전/빌드 문제?"}
    B -->|"예"| C["version_sync.py --check"]
    B -->|"아니오"| D{"문서/마커 문제?"}
    D -->|"예"| E["test-dev-docs-* 확인"]
    D -->|"아니오"| F{"상태/세션 문제?"}
    F -->|"예"| G["setup, stats, gc, clean"]
    F -->|"아니오"| H["관련 hook / skill 읽기"]
```
EOF
  fi

  local failures="$TMP_DIR/troubleshooting-failures.md"
  if [ "$DOC_LANG" = "en" ]; then
    cat > "$failures" <<'EOF'
| Symptom | First place to inspect |
|------|-------------|
| `version sync mismatch` | `VERSION`, `scripts/version_sync.py`, `02-아키텍처.md` |
| diff remains after build | `scripts/build-all.sh`, `platforms/*/overlay/`, `plugins/`, `dist/` |
| `manifest.json not found` | `setup` skill, `shared/hooks/scripts/setup-check.sh` |
| some hooks do not show in Codex | `platforms/codex/overlay/hooks/hooks.json` and platform limitations |
| too many repeated rules | `gc`, `stats`, `harness-log.jsonl` |
EOF
  else
    cat > "$failures" <<'EOF'
| 증상 | 먼저 볼 곳 |
|------|-------------|
| `version sync mismatch` | `VERSION`, `scripts/version_sync.py`, `02-아키텍처.md` |
| 빌드 후 diff 남음 | `scripts/build-all.sh`, `platforms/*/overlay/`, `plugins/`, `dist/` |
| `manifest.json not found` | `setup` 스킬, `shared/hooks/scripts/setup-check.sh` |
| Codex에서 일부 훅이 안 뜸 | `platforms/codex/overlay/hooks/hooks.json`와 플랫폼 제한 |
| 반복 규칙이 너무 많음 | `gc`, `stats`, `harness-log.jsonl` |
EOF
  fi

  local recovery="$TMP_DIR/troubleshooting-recovery.md"
  if [ "$DOC_LANG" = "en" ]; then
    cat > "$recovery" <<'EOF'
Common recovery order:

1. `python3 scripts/version_sync.py --check`
2. `bash scripts/build-all.sh`
3. `bash tests/test-dev-docs-skill.sh && bash tests/test-dev-docs-updater.sh`
4. if state looks suspicious, inspect `setup`, `stats`, `gc`, then `clean`
5. if it is still ambiguous, read the target skill `SKILL.md` and the related hook script headers first
EOF
  else
    cat > "$recovery" <<'EOF'
자주 쓰는 복구 순서:

1. `python3 scripts/version_sync.py --check`
2. `bash scripts/build-all.sh`
3. `bash tests/test-dev-docs-skill.sh && bash tests/test-dev-docs-updater.sh`
4. 상태 문제가 의심되면 `setup`, `stats`, `gc`, `clean` 순으로 확인
5. 그래도 모호하면 해당 스킬의 `SKILL.md`와 관련 hook 스크립트 header를 먼저 읽기
EOF
  fi

  write_block "$file" troubleshooting quick-diagnosis "$( [ "$DOC_LANG" = "en" ] && echo "## Quick Diagnosis" || echo "## 빠른 진단" )" "$diagnosis"
  write_block "$file" troubleshooting common-failures "$( [ "$DOC_LANG" = "en" ] && echo "## Common Failures" || echo "## 자주 만나는 문제" )" "$failures"
  write_block "$file" troubleshooting recovery-commands "$( [ "$DOC_LANG" = "en" ] && echo "## Recovery Order" || echo "## 복구 순서" )" "$recovery"
}

generate_operations() {
  local file="$REPO_ROOT/docs/07-운영-흐름-및-배포.md"
  if [ "$DOC_LANG" = "en" ]; then
    ensure_doc_file "$file" "07. Operating Flow and Release" "This document summarizes request handling, state flow, and the CI/release pipeline."
  else
    ensure_doc_file "$file" "07. 운영 흐름 및 배포" "이 문서는 요청 처리, 상태 흐름, CI/Release 파이프라인을 요약합니다."
  fi

  local request="$TMP_DIR/operations-request.md"
  if [ "$DOC_LANG" = "en" ]; then
    cat > "$request" <<'EOF'
```mermaid
flowchart TD
    A["user request"] --> B["synapse"]
    B --> C["direct route or team template"]
    C --> D["hooks intervene"]
    D --> E["state/log update"]
    E --> F["result returned"]
```
EOF
  else
    cat > "$request" <<'EOF'
```mermaid
flowchart TD
    A["사용자 요청"] --> B["synapse"]
    B --> C["direct route 또는 team template"]
    C --> D["hooks 개입"]
    D --> E["state/log 갱신"]
    E --> F["결과 전달"]
```
EOF
  fi

  local data="$TMP_DIR/operations-data.md"
  if [ "$DOC_LANG" = "en" ]; then
    cat > "$data" <<'EOF'
```mermaid
flowchart LR
    A["setup/evolve"] --> B["manifest.json"]
    A --> C["context.md"]
    D["hook events"] --> E["harness-log.jsonl"]
    D --> F["security-log.jsonl"]
    E --> G["stats / gc"]
    F --> H["security status"]
```
EOF
  else
    cat > "$data" <<'EOF'
```mermaid
flowchart LR
    A["setup/evolve"] --> B["manifest.json"]
    A --> C["context.md"]
    D["hook events"] --> E["harness-log.jsonl"]
    D --> F["security-log.jsonl"]
    E --> G["stats / gc"]
    F --> H["security status"]
```
EOF
  fi

  local ci="$TMP_DIR/operations-ci.md"
  if [ "$BUILD_SCRIPT_COUNT" -gt 0 ]; then
    if [ "$DOC_LANG" = "en" ]; then
      cat > "$ci" <<'EOF'
```mermaid
flowchart TD
    A["code change"] --> B["version_sync.py --check"]
    B --> C["build-all.sh"]
    C --> D["git diff --exit-code"]
    D --> E["CI"]
    E --> F["Release workflow"]
```

| Stage | Evidence file |
|------|-----------|
| CI validation | `.github/workflows/ci.yml` |
| Release publishing | `.github/workflows/release.yml` |
EOF
    else
      cat > "$ci" <<'EOF'
```mermaid
flowchart TD
    A["코드 변경"] --> B["version_sync.py --check"]
    B --> C["build-all.sh"]
    C --> D["git diff --exit-code"]
    D --> E["CI"]
    E --> F["Release workflow"]
```

| 단계 | 근거 파일 |
|------|-----------|
| CI 검증 | `.github/workflows/ci.yml` |
| Release 발행 | `.github/workflows/release.yml` |
EOF
    fi
  else
    write_fallback_block "$file" operations ci-release-flow "$( [ "$DOC_LANG" = "en" ] && echo "## CI and Release" || echo "## CI와 릴리즈" )" \
      "CI와 릴리즈 흐름" \
      "$( [ "$DOC_LANG" = "en" ] && echo "build-*.sh evidence is missing." || echo "build-*.sh 근거가 부족합니다." )" \
      "build script 수=${BUILD_SCRIPT_COUNT}"
  fi

  write_block "$file" operations request-flow "$( [ "$DOC_LANG" = "en" ] && echo "## Request Flow" || echo "## 요청 처리 흐름" )" "$request"
  write_block "$file" operations data-flow "$( [ "$DOC_LANG" = "en" ] && echo "## State and Log Flow" || echo "## 상태와 로그 흐름" )" "$data"
  if [ -f "$ci" ]; then
    write_block "$file" operations ci-release-flow "$( [ "$DOC_LANG" = "en" ] && echo "## CI and Release" || echo "## CI와 릴리즈" )" "$ci"
  fi
}

for doc_id in $SELECTED_DOCS; do
  case "$doc_id" in
    readme) generate_readme ;;
    start) generate_start ;;
    overview) generate_overview ;;
    architecture) generate_architecture ;;
    build) generate_build ;;
    features) generate_features ;;
    conventions) generate_conventions ;;
    troubleshooting) generate_troubleshooting ;;
    operations) generate_operations ;;
  esac
done

echo "updated docs: $SELECTED_DOCS"
