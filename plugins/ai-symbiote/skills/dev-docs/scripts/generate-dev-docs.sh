#!/usr/bin/env bash
# Generate Mermaid-heavy developer docs from repo structure.
#
# NOTE: This script is a baseline fallback for Codex bundles and standalone execution.
# Primary document generation is handled by the SKILL.md workflow in Claude Code sessions.
# Do NOT run this script after the SKILL.md workflow has enriched the docs.
#
# Usage:
#   generate-dev-docs.sh [repo-root] [all|readme|architecture|conventions|onboarding|dependencies|flows ...]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UPDATER="$SCRIPT_DIR/update-doc-section.sh"

if [ ! -x "$UPDATER" ]; then
  echo "error: updater helper not executable: $UPDATER" >&2
  exit 1
fi

KNOWN_DOCS="readme architecture conventions onboarding dependencies flows"

has_doc() {
  local target="$1"
  for item in $KNOWN_DOCS; do
    [ "$item" = "$target" ] && return 0
  done
  return 1
}

if [ "$#" -gt 0 ] && [ -d "$1" ]; then
  REPO_ROOT="$(cd "$1" && pwd)"
  shift
else
  REPO_ROOT="$(pwd)"
fi

if [ "$#" -eq 0 ]; then
  SELECTED_DOCS="$KNOWN_DOCS"
else
  SELECTED_DOCS=""
  for arg in "$@"; do
    if [ "$arg" = "all" ]; then
      SELECTED_DOCS="$KNOWN_DOCS"
      break
    fi
    if has_doc "$arg"; then
      SELECTED_DOCS="$SELECTED_DOCS $arg"
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
  local pattern_dir="$1"
  [ -d "$pattern_dir" ] || { echo 0; return; }
  find "$pattern_dir" -type f | wc -l | tr -d ' '
}

join_paths() {
  local search_dir="$1"
  local limit="${2:-20}"
  [ -d "$search_dir" ] || return 0
  find "$search_dir" -maxdepth 1 -type f | sed "s#^$REPO_ROOT/##" | sort | head -n "$limit"
}

dir_flag() {
  local dir="$1"
  if [ -d "$dir" ]; then
    echo yes
  else
    echo no
  fi
}

file_flag() {
  local file="$1"
  if [ -f "$file" ]; then
    echo yes
  else
    echo no
  fi
}

SKILL_COUNT="$(count_dirs "$REPO_ROOT/shared/skills")"
HOOK_COUNT="$(find "$REPO_ROOT/shared/hooks/scripts" -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ')"
DOC_COUNT="$(count_files "$REPO_ROOT/docs")"
if [ -d "$REPO_ROOT/scripts" ]; then
  BUILD_SCRIPT_COUNT="$(find "$REPO_ROOT/scripts" -maxdepth 1 -type f -name 'build-*.sh' 2>/dev/null | wc -l | tr -d ' ')"
  BUILD_SCRIPTS="$(find "$REPO_ROOT/scripts" -maxdepth 1 -type f -name 'build-*.sh' 2>/dev/null | sed "s#^$REPO_ROOT/##" | sort)"
else
  BUILD_SCRIPT_COUNT=0
  BUILD_SCRIPTS=""
fi
HAS_CLAUDE_OVERLAY="$(dir_flag "$REPO_ROOT/platforms/claude/overlay")"
HAS_CODEX_OVERLAY="$(dir_flag "$REPO_ROOT/platforms/codex/overlay")"
HAS_MESSENGER_DOC="$(file_flag "$REPO_ROOT/docs/MESSENGER.md")"

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

write_block() {
  local file="$1"
  local doc_id="$2"
  local section_id="$3"
  local heading="$4"
  local content_file="$5"
  bash "$UPDATER" "$file" "$doc_id" "$section_id" "$heading" "$content_file"
}

write_fallback_block() {
  local file="$1"
  local doc_id="$2"
  local section_id="$3"
  local heading="$4"
  local title="$5"
  local reason="$6"
  local evidence="$7"
  local fallback="$TMP_DIR/${doc_id}-${section_id}-fallback.md"
  cat > "$fallback" <<EOF
### 확인 필요: ${title}

- 현재 확인한 사실: ${evidence}
- 애매한 이유: ${reason}
- 다음 확인 위치: 관련 스크립트, overlay, 기존 문서
EOF
  write_block "$file" "$doc_id" "$section_id" "$heading" "$fallback"
}

generate_readme() {
  local file="$REPO_ROOT/README.md"
  local content="$TMP_DIR/readme-docs-map.md"
  cat > "$content" <<EOF
프로젝트를 빠르게 파악하려면 아래 문서부터 보는 게 가장 빠릅니다.

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — 시스템 구조, 빌드 흐름, 플랫폼 차이
- [docs/CONVENTIONS.md](docs/CONVENTIONS.md) — 어디를 수정해야 하는지, 생성물과 원본의 경계
- [docs/ONBOARDING.md](docs/ONBOARDING.md) — 처음 들어온 개발자를 위한 읽기 순서와 로컬 확인 절차
- [docs/DEPENDENCIES.md](docs/DEPENDENCIES.md) — 외부 도구, 플러그인, 런타임 의존성
- [docs/FLOWS.md](docs/FLOWS.md) — 시스템/데이터/운영 흐름을 Mermaid로 요약
EOF
  if [ "$HAS_MESSENGER_DOC" = "yes" ]; then
    cat >> "$content" <<'EOF'
- [docs/MESSENGER.md](docs/MESSENGER.md) — 메신저 브릿지 상세 설정
EOF
  fi
  cat >> "$content" <<'EOF'

이 문서 묶음은 `dev-docs` 스킬로 코드 기준 갱신을 전제로 설계되어 있습니다.
EOF
  write_block "$file" readme docs-map "## 개발자 문서" "$content"
}

generate_architecture() {
  local file="$REPO_ROOT/docs/ARCHITECTURE.md"
  ensure_doc_file "$file" "Architecture" "\`$(basename "$REPO_ROOT")\`의 구조를 설명하는 문서입니다."

  local subsystems="$TMP_DIR/architecture-subsystems.md"
  cat > "$subsystems" <<EOF
\`shared/\`는 플랫폼에 독립적인 자산을 담습니다.

- \`skills/\` — ${SKILL_COUNT}개 스킬 정의
- \`hooks/scripts/\` — ${HOOK_COUNT}개 훅 스크립트
- \`docs/\` — ${DOC_COUNT}개 상세 문서
- \`scripts/\` — ${BUILD_SCRIPT_COUNT}개 빌드 스크립트

이 디렉터리의 내용은 Claude 번들과 Codex 번들 모두에 공통으로 들어갑니다.

\`\`\`mermaid
flowchart LR
    A["shared/"] --> B["skills/"]
    A --> C["hooks/scripts/"]
    A --> D["docs/"]
    A --> E["scripts/"]
    B --> F["Claude/Codex bundles"]
\`\`\`
EOF

  local buildflow="$TMP_DIR/architecture-build-flow.md"
  if [ "$BUILD_SCRIPT_COUNT" -gt 0 ] && [ "$HAS_CLAUDE_OVERLAY" = "yes" -o "$HAS_CODEX_OVERLAY" = "yes" ]; then
    cat > "$buildflow" <<EOF
1. \`shared/\` 자산을 빌드 대상으로 복사
2. \`platforms/<name>/overlay/\`를 같은 위치에 덮어쓰기
3. 결과 번들을 설치 스크립트에서 사용

플랫폼 지원:
- Claude overlay: ${HAS_CLAUDE_OVERLAY}
- Codex overlay: ${HAS_CODEX_OVERLAY}

\`\`\`mermaid
flowchart LR
    S["shared/"] --> C["platforms/claude/overlay"]
    S --> X["platforms/codex/overlay"]
    C --> P["plugins/ai-symbiote / dist/claude-symbiote"]
    X --> D["dist/codex-symbiote"]
\`\`\`

빌드 스크립트:
EOF
    while IFS= read -r line; do
      [ -n "$line" ] && printf -- '- `%s`\n' "$line" >> "$buildflow"
    done <<< "$BUILD_SCRIPTS"
    write_block "$file" architecture build-flow "## Build Flow" "$buildflow"
  else
    write_fallback_block "$file" architecture build-flow "## Build Flow" \
      "빌드 흐름" \
      "build-*.sh 또는 플랫폼 overlay 증거가 부족합니다." \
      "build script 수=${BUILD_SCRIPT_COUNT}, claude overlay=${HAS_CLAUDE_OVERLAY}, codex overlay=${HAS_CODEX_OVERLAY}"
  fi

  write_block "$file" architecture subsystems "## Core" "$subsystems"
}

generate_conventions() {
  local file="$REPO_ROOT/docs/CONVENTIONS.md"
  ensure_doc_file "$file" "Conventions" "이 문서는 저장소 수정 규칙을 정리합니다."

  local decision="$TMP_DIR/conventions-decision.md"
  cat > "$decision" <<'EOF'
```mermaid
flowchart TD
    A["변경 대상 파악"] --> B{"공용 동작인가?"}
    B -->|"예"| C["shared/ 수정"]
    B -->|"아니오"| D{"플랫폼 차이인가?"}
    D -->|"예"| E["platforms/<name>/overlay/ 수정"]
    D -->|"아니오"| F{"문서/가이드인가?"}
    F -->|"예"| G["README.md 또는 docs/ 수정"]
    F -->|"아니오"| H["tests/ 또는 scripts/ 검토"]
```
EOF

  local editing="$TMP_DIR/conventions-editing.md"
  cat > "$editing" <<'EOF'
- 공용 동작 변경은 `shared/`를 먼저 본다.
- `plugins/ai-symbiote/`와 `dist/`는 빌드 산출물이다. 직접 수정하지 않는다.
- 플랫폼 차이는 `platforms/<name>/overlay/`에 둔다.
- 새 스킬은 `shared/skills/<name>/SKILL.md`에 추가하고 빌드로 반영한다.
EOF

  local layout="$TMP_DIR/conventions-layout.md"
  cat > "$layout" <<'EOF'
- 스킬은 `shared/skills/<name>/SKILL.md` 구조를 따른다.
- 테스트는 `tests/test-*.sh` 패턴을 우선 사용한다.
- 빌드 스크립트는 `scripts/build-*.sh`에 둔다.
- 상세 문서는 `docs/` 아래에 두고 README는 허브 역할을 유지한다.
EOF

  local boundaries="$TMP_DIR/conventions-boundaries.md"
  cat > "$boundaries" <<'EOF'
`shared/`는 사람이 수정하는 원본이다. `plugins/ai-symbiote/`와 `dist/`는 빌드로 재생성되므로 수동 수정은 다음 빌드에서 사라진다.
EOF

  write_block "$file" conventions decision-tree "## 어디를 수정할까?" "$decision"
  write_block "$file" conventions editing-rules "## 편집 규칙" "$editing"
  write_block "$file" conventions naming-layout "## 네이밍과 배치" "$layout"
  write_block "$file" conventions generated-boundaries "## 생성물 경계" "$boundaries"
}

generate_onboarding() {
  local file="$REPO_ROOT/docs/ONBOARDING.md"
  ensure_doc_file "$file" "Onboarding" "이 문서는 처음 들어온 개발자가 가장 먼저 따라야 할 흐름을 정리합니다."

  local first="$TMP_DIR/onboarding-first.md"
  cat > "$first" <<'EOF'
```mermaid
flowchart LR
    A["README 읽기"] --> B["docs/ARCHITECTURE 확인"]
    B --> C["docs/CONVENTIONS 확인"]
    C --> D["테스트 실행"]
    D --> E["빌드 실행"]
    E --> F["수정 대상 찾기"]
```
EOF

  local read_order="$TMP_DIR/onboarding-read.md"
  cat > "$read_order" <<EOF
1. \`README.md\`
2. \`docs/ARCHITECTURE.md\`
3. \`docs/CONVENTIONS.md\`
4. \`docs/DEPENDENCIES.md\`
5. 필요한 기능의 \`shared/skills/*/SKILL.md\`
EOF

  local checks="$TMP_DIR/onboarding-checks.md"
  cat > "$checks" <<'EOF'
```mermaid
sequenceDiagram
    participant Dev as Developer
    participant Repo as Repository
    Dev->>Repo: bash tests/test-dev-docs-skill.sh
    Dev->>Repo: bash scripts/build-all.sh
    Repo-->>Dev: plugins/ + dist/ 번들 갱신
```
EOF

  local tasks="$TMP_DIR/onboarding-tasks.md"
  cat > "$tasks" <<'EOF'
- 새 스킬 추가: `shared/skills/<name>/SKILL.md` 작성 후 `bash scripts/build-all.sh`
- 문서 갱신: `README.md`, `docs/*.md` 수정 후 관련 테스트 실행
- 훅 수정: `shared/hooks/scripts/` 수정 후 영향 범위 테스트
EOF

  write_block "$file" onboarding first-day-path "## 첫날 경로" "$first"
  write_block "$file" onboarding read-order "## 읽기 순서" "$read_order"
  write_block "$file" onboarding local-checks "## 로컬 확인 절차" "$checks"
  write_block "$file" onboarding common-tasks "## 자주 하는 작업" "$tasks"
}

generate_dependencies() {
  local file="$REPO_ROOT/docs/DEPENDENCIES.md"
  ensure_doc_file "$file" "Dependencies" "이 문서는 저장소가 기대하는 외부 도구와 내부 의존성을 정리합니다."

  local depmap="$TMP_DIR/dependencies-map.md"
  cat > "$depmap" <<'EOF'
```mermaid
flowchart TD
    A["Repository"] --> B["bash scripts"]
    A --> C["rsync"]
    A --> D["grep / sed / awk / find"]
    A --> E["선택적 외부 플러그인"]
    E --> F["snarktank/ralph"]
    E --> G["openai/codex-plugin-cc"]
```
EOF

  local runtime="$TMP_DIR/dependencies-runtime.md"
  cat > "$runtime" <<'EOF'
- `bash`: 빌드 및 테스트 스크립트 실행
- `rsync`: shared/와 overlay를 번들로 복사
- `grep`, `sed`, `awk`, `find`: 훅과 테스트 스크립트에서 사용
- `jq`: JSON 검증 테스트가 있을 때 사용
EOF

  local platforms="$TMP_DIR/dependencies-platforms.md"
  cat > "$platforms" <<'EOF'
```mermaid
flowchart LR
    A["shared/"] --> B["Claude bundle"]
    A --> C["Codex bundle"]
    B --> D[".claude-plugin/plugin.json"]
    C --> E[".codex-plugin/plugin.json"]
```
EOF

  local update="$TMP_DIR/dependencies-update.md"
  cat > "$update" <<EOF
- 공용 변경은 \`bash scripts/build-all.sh\`로 양쪽 번들을 함께 갱신한다.
- Claude 사용자는 \`bash scripts/build-claude.sh\` 경로를 사용할 수 있다.
- Codex 사용자는 \`bash scripts/build-codex.sh\` 또는 설치 스크립트 경로를 사용한다.
EOF

  write_block "$file" dependencies dependency-map "## 의존성 맵" "$depmap"
  write_block "$file" dependencies runtime-dev-tools "## 런타임 / 개발 도구" "$runtime"
  write_block "$file" dependencies platform-dependencies "## 플랫폼별 의존성" "$platforms"
  write_block "$file" dependencies update-path "## 업데이트 경로" "$update"
}

generate_flows() {
  local file="$REPO_ROOT/docs/FLOWS.md"
  ensure_doc_file "$file" "Flows" "이 문서는 프로젝트의 주요 흐름을 Mermaid로 요약합니다."

  local system="$TMP_DIR/flows-system.md"
  cat > "$system" <<'EOF'
```mermaid
flowchart LR
    A["사용자 요청"] --> B["적절한 스킬 선택"]
    B --> C["shared/ 원본 수정"]
    C --> D["테스트 실행"]
    D --> E["build-all.sh"]
    E --> F["Claude/Codex 번들 반영"]
```
EOF

  local data="$TMP_DIR/flows-data.md"
  cat > "$data" <<'EOF'
```mermaid
flowchart TD
    A["프로젝트 코드"] --> B["setup/evolve 감지"]
    B --> C["manifest.json / context.md"]
    C --> D["SessionStart 주입"]
    D --> E["에이전트 작업"]
    E --> F["harness-log.jsonl"]
    F --> G["stats / gc / 다음 세션 분석"]
```
EOF

  local userflow="$TMP_DIR/flows-user.md"
  if [ "$BUILD_SCRIPT_COUNT" -gt 0 ]; then
    cat > "$userflow" <<'EOF'
```mermaid
sequenceDiagram
    participant Dev as Developer
    participant Skill as Skill
    participant Build as Build Scripts
    Dev->>Skill: shared/ 또는 docs/ 수정
    Dev->>Build: bash scripts/build-all.sh
    Build-->>Dev: plugins/ + dist/ 갱신
    Dev->>Dev: 결과 확인 및 테스트
```
EOF
    write_block "$file" flows user-or-operator-flow "## 사용자 / 운영자 흐름" "$userflow"
  else
    write_fallback_block "$file" flows user-or-operator-flow "## 사용자 / 운영자 흐름" \
      "사용자 / 운영자 흐름" \
      "반복 가능한 실행 경로를 보여 주는 build/test 스크립트 근거가 부족합니다." \
      "build script 수=${BUILD_SCRIPT_COUNT}"
  fi

  local ops="$TMP_DIR/flows-ops.md"
  if [ "$BUILD_SCRIPT_COUNT" -gt 0 ]; then
    cat > "$ops" <<'EOF'
```mermaid
flowchart TD
    A["공용 변경"] --> B["shared/ 수정"]
    B --> C["테스트"]
    C --> D["build-claude.sh / build-codex.sh"]
    D --> E["번들 산출물 생성"]
    E --> F["설치 또는 업데이트"]
```
EOF
    write_block "$file" flows operational-flow "## 운영 흐름" "$ops"
  else
    write_fallback_block "$file" flows operational-flow "## 운영 흐름" \
      "운영 흐름" \
      "배포/빌드 파이프라인을 재구성할 근거가 부족합니다." \
      "build script 수=${BUILD_SCRIPT_COUNT}"
  fi

  write_block "$file" flows system-flow "## 시스템 상위 흐름" "$system"
  write_block "$file" flows data-flow "## 데이터 흐름" "$data"
}

for doc_id in $SELECTED_DOCS; do
  case "$doc_id" in
    readme) generate_readme ;;
    architecture) generate_architecture ;;
    conventions) generate_conventions ;;
    onboarding) generate_onboarding ;;
    dependencies) generate_dependencies ;;
    flows) generate_flows ;;
  esac
done

echo "updated docs: $SELECTED_DOCS"
