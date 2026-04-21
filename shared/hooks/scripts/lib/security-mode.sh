#!/bin/bash
# ai-symbiote security mode helper (v0.13+).
#
# Author: JunyoungJung
# Date: 2026-04-21
#
# 제공하는 두 가지 공개 API:
#   is_hook_enabled    "<hookName>"                 — hook 자체가 활성화됐는지
#   is_feature_enabled "<hookName>" "<featureName>" — hook + 하위 기능이 활성화됐는지
#
# 데이터 흐름:
#   manifest.json (source of truth)
#     └─> ~/ai-symbiote/{slug}/state/security-mode.cache
#         (평문 key=value 스냅샷, manifest mtime 변화 시 재빌드)
#         └─> is_feature_enabled "guardShell" "echoSecrets" → 0/1
#
# Hot path 오버헤드 <5ms 목표.
#
# 스키마 (manifest.json):
#   "security": {
#     "mode": "balanced",        // minimal|balanced|strict|custom
#     "features": {              // mode=="custom"일 때만 읽힘
#       "guardShell": {
#         "enabled": true,
#         "echoSecrets": true,
#         "authHeaderLeak": true,
#         "gitAddEnv": true,
#         "base64Secret": true,
#         "exportSecret": true,
#         "remoteEval": true,
#         "chmod777": true,
#         "unsafeInstallFlags": true,
#         "dockerPrivileged": true,
#         "bindAllInterfaces": true,
#         "inlineNetworkExec": true,
#         "archiveSensitive": true,
#         "sensitiveTransfer": true,
#         "envDumpToFile": true,
#         "secretsInGitPush": true,
#         "netcatExfiltration": true
#       },
#       "securityGuard": {
#         "enabled": true,
#         "hardcodedSecrets": true,
#         "envFileLeak": true,
#         "sqlInjection": true,
#         "xssRisk": true,
#         "debugModeOn": true,
#         "evalUsage": true
#       },
#       "harnessLearn": {
#         "enabled": true,
#         "errorTracking": true,
#         "editChurn": true,
#         "ruleLearning": true,
#         "guardLogging": true
#       },
#       "commentChecker": {
#         "enabled": true,
#         "obviousComments": true,
#         "keywordComments": true,
#         "tagComments": true
#       },
#       "verifyQueue": {
#         "enabled": true
#       }
#     }
#   }
#
# 하위 호환: 구 스키마 `security.hooks.<name>: bool`은 읽을 때
# `security.features.<name>.enabled`로 자동 매핑되고, 하위 feature 기본값은
# true (fail-open)입니다.

if ! command -v get_state_dir >/dev/null 2>&1; then
  _SEC_MODE_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  # shellcheck source=common.sh
  source "$_SEC_MODE_LIB_DIR/common.sh"
fi

# 로드 완료 센티넬. 각 hook은 `source lib/security-mode.sh 2>/dev/null || true`
# 후 이 변수로 load 성공 여부를 확인. load 실패 시 hook은 fail-open (정상 실행)
_SEC_MODE_LIB_LOADED=1

# Canonical hook 목록. feature 테이블과 정합성 필수.
_SEC_MODE_HOOK_NAMES=(
  guardShell
  securityGuard
  harnessLearn
  commentChecker
  verifyQueue
)

# Canonical feature 목록. 형식: "hookName featureName"
# 새 feature 추가 시:
#   1) 여기에 한 줄 추가
#   2) 해당 hook 스크립트에 is_feature_enabled 체크 추가
#   3) docs/09-보안-기능-세부토글.md에 한국어 설명 추가
# 모든 feature 기본값은 true (안전 기본, fail-open).
_SEC_MODE_FEATURE_PAIRS=(
  # guardShell — 시크릿 노출 방지 (SEC-001~005)
  "guardShell echoSecrets"
  "guardShell authHeaderLeak"
  "guardShell gitAddEnv"
  "guardShell base64Secret"
  "guardShell exportSecret"
  # guardShell — 위험한 실행 방지 (SEC-006~011)
  "guardShell remoteEval"
  "guardShell chmod777"
  "guardShell unsafeInstallFlags"
  "guardShell dockerPrivileged"
  "guardShell bindAllInterfaces"
  "guardShell inlineNetworkExec"
  # guardShell — 데이터 빼돌리기 방지 (SEC-012~016)
  "guardShell archiveSensitive"
  "guardShell sensitiveTransfer"
  "guardShell envDumpToFile"
  "guardShell secretsInGitPush"
  "guardShell netcatExfiltration"
  # securityGuard — 쓴 파일 내용 스캔 (SEC-W01~W06)
  "securityGuard hardcodedSecrets"
  "securityGuard envFileLeak"
  "securityGuard sqlInjection"
  "securityGuard xssRisk"
  "securityGuard debugModeOn"
  "securityGuard evalUsage"
  # harnessLearn — 반복 실수 학습
  "harnessLearn errorTracking"
  "harnessLearn editChurn"
  "harnessLearn ruleLearning"
  "harnessLearn guardLogging"
  # commentChecker — 자명한 주석 감시
  "commentChecker obviousComments"
  "commentChecker keywordComments"
  "commentChecker tagComments"
  # verifyQueue — 세부 기능 없음 (enabled만)
)

# 캐시 파일 경로. symlink 거부 — symlinked cache는 공격자가 재지향할 수 있어
# 전체 gate 무력화 위험.
_sec_mode_cache_path() {
  local state_dir state_subdir cache_file
  state_dir=$(get_state_dir 2>/dev/null) || return 1
  [ -z "$state_dir" ] && return 1
  state_subdir="$state_dir/state"
  cache_file="$state_subdir/security-mode.cache"
  if [ -L "$state_subdir" ]; then
    return 1
  fi
  mkdir -p "$state_subdir" 2>/dev/null || true
  if [ -e "$cache_file" ] && [ -L "$cache_file" ]; then
    return 1
  fi
  printf '%s' "$cache_file"
}

_sec_mode_manifest_path() {
  local state_dir
  state_dir=$(get_state_dir 2>/dev/null) || return 1
  [ -z "$state_dir" ] && return 1
  printf '%s/manifest.json' "$state_dir"
}

# 캐시 재빌드. tempfile + mv로 원자적 쓰기.
# 캐시 포맷 (v2):
#   mode=balanced
#   guardShell=true
#   guardShell.echoSecrets=true
#   guardShell.authHeaderLeak=true
#   ...
_sec_mode_rebuild_cache() {
  local manifest="$1"
  local cache_file="$2"

  local cache_dir
  cache_dir=$(dirname "$cache_file")
  mkdir -p "$cache_dir" 2>/dev/null || return 1
  local tmp_cache
  tmp_cache=$(mktemp "$cache_dir/security-mode.cache.XXXXXX" 2>/dev/null) || return 1

  if command -v python3 >/dev/null 2>&1 && [ -f "$manifest" ] && [ -s "$manifest" ]; then
    # hook + feature 목록을 argv로 전달. Python과 Bash가 항상 같은 목록을 공유.
    local cache_body
    cache_body=$(python3 - \
      "$manifest" \
      "HOOKS" "${_SEC_MODE_HOOK_NAMES[@]}" \
      "FEATURES" "${_SEC_MODE_FEATURE_PAIRS[@]}" \
      <<'PY' 2>/dev/null
import json
import sys
from pathlib import Path

DEFAULT_MODE = "balanced"
VALID_MODES = {"minimal", "balanced", "strict", "custom"}


def preset_default(mode: str) -> bool:
    # minimal만 전부 off, 나머지는 전부 on.
    return mode != "minimal"


def main() -> int:
    args = sys.argv[1:]
    manifest_path = Path(args.pop(0))

    # argv 파서: "HOOKS <names...> FEATURES <pairs...>"
    # 각 feature 페어는 "guardShell echoSecrets" 형태의 단일 argv로 들어옴
    # (bash 배열 원소는 element 경계 유지). 스페이스로 split해서 (hook, feature) 추출.
    hooks = []
    features = []  # [(hook, feature), ...]
    current = None
    for tok in args:
        if tok == "HOOKS":
            current = "hooks"
            continue
        if tok == "FEATURES":
            current = "features"
            continue
        if current == "hooks":
            hooks.append(tok)
        elif current == "features":
            parts = tok.split(" ", 1)
            if len(parts) == 2 and parts[0] and parts[1]:
                features.append((parts[0], parts[1]))

    if not hooks:
        return 1

    try:
        data = json.loads(manifest_path.read_text())
    except Exception:
        return 1

    security = data.get("security") or {}
    mode = security.get("mode") or DEFAULT_MODE
    if mode not in VALID_MODES:
        mode = DEFAULT_MODE

    # 신 스키마 우선, 구 스키마(security.hooks)를 fallback으로 통합.
    features_block = security.get("features") or {}
    legacy_hooks = security.get("hooks") or {}

    def hook_enabled(name: str) -> bool:
        if mode != "custom":
            return preset_default(mode)
        # custom: features 블록 우선
        fblock = features_block.get(name)
        if isinstance(fblock, dict):
            val = fblock.get("enabled")
            if isinstance(val, bool):
                return val
        # 구 스키마 fallback
        legacy = legacy_hooks.get(name)
        if isinstance(legacy, bool):
            return legacy
        return True  # custom + 명시 없음 = fail-open

    def feature_enabled(hook: str, feat: str) -> bool:
        if mode != "custom":
            return preset_default(mode)
        # hook 전체가 off면 feature도 off
        if not hook_enabled(hook):
            return False
        fblock = features_block.get(hook)
        if isinstance(fblock, dict):
            val = fblock.get(feat)
            if isinstance(val, bool):
                return val
        return True  # feature 키 미지정 = fail-open

    lines = [f"mode={mode}"]
    for hook in hooks:
        lines.append(f"{hook}={'true' if hook_enabled(hook) else 'false'}")
    for hook, feat in features:
        lines.append(f"{hook}.{feat}={'true' if feature_enabled(hook, feat) else 'false'}")

    sys.stdout.write("\n".join(lines) + "\n")
    return 0


sys.exit(main())
PY
)
    if [ -n "$cache_body" ]; then
      printf '%s' "$cache_body" > "$tmp_cache" 2>/dev/null || { rm -f "$tmp_cache"; return 1; }
      mv -f "$tmp_cache" "$cache_file" 2>/dev/null || { rm -f "$tmp_cache"; return 1; }
      return 0
    fi
  fi

  # Python 없음 또는 parse 실패 → balanced 기본값 fallback.
  {
    printf 'mode=balanced\n'
    for name in "${_SEC_MODE_HOOK_NAMES[@]}"; do
      printf '%s=true\n' "$name"
    done
    local pair hook feat
    for pair in "${_SEC_MODE_FEATURE_PAIRS[@]}"; do
      hook="${pair%% *}"
      feat="${pair#* }"
      printf '%s.%s=true\n' "$hook" "$feat"
    done
  } > "$tmp_cache" 2>/dev/null || { rm -f "$tmp_cache"; return 1; }
  mv -f "$tmp_cache" "$cache_file" 2>/dev/null || { rm -f "$tmp_cache"; return 1; }
}

# manifest가 cache보다 새로우면 stale.
_sec_mode_cache_stale() {
  local manifest="$1"
  local cache="$2"
  [ ! -f "$cache" ] && return 0
  [ ! -f "$manifest" ] && return 1
  local manifest_mtime cache_mtime
  manifest_mtime=$(stat -f '%m' "$manifest" 2>/dev/null || stat -c '%Y' "$manifest" 2>/dev/null || echo 0)
  cache_mtime=$(stat -f '%m' "$cache" 2>/dev/null || stat -c '%Y' "$cache" 2>/dev/null || echo 0)
  [ "$manifest_mtime" -gt "$cache_mtime" ] 2>/dev/null
}

# hook 이름이 canonical 목록에 있는지.
_sec_mode_is_known_hook() {
  local name="$1"
  local n
  for n in "${_SEC_MODE_HOOK_NAMES[@]}"; do
    [ "$n" = "$name" ] && return 0
  done
  return 1
}

# (hook, feature) 쌍이 canonical 목록에 있는지.
_sec_mode_is_known_feature() {
  local hook="$1"
  local feat="$2"
  local pair
  for pair in "${_SEC_MODE_FEATURE_PAIRS[@]}"; do
    [ "$pair" = "$hook $feat" ] && return 0
  done
  return 1
}

# 캐시를 사용할 수 있는 상태로 보장. 성공 시 cache 경로를 stdout에 출력, 실패 시 비어있음.
_sec_mode_ensure_cache() {
  local manifest cache
  manifest=$(_sec_mode_manifest_path) || return 1
  [ ! -f "$manifest" ] && return 1
  cache=$(_sec_mode_cache_path) || return 1
  [ -z "$cache" ] && return 1
  if _sec_mode_cache_stale "$manifest" "$cache"; then
    _sec_mode_rebuild_cache "$manifest" "$cache" || return 1
  fi
  printf '%s' "$cache"
}

# 공용 env 오버라이드 (테스트 전용). 프로덕션에서는 SYMBIOTE_TESTING=1이
# 함께 있어야 적용됨. 상세 설명은 이전 버전 참조.
_sec_mode_env_override() {
  if [ -n "${SYMBIOTE_SECURITY_FORCE:-}" ] && [ "${SYMBIOTE_TESTING:-0}" = "1" ]; then
    case "$SYMBIOTE_SECURITY_FORCE" in
      off)
        [ -z "${_SEC_MODE_FORCE_WARNED:-}" ] && {
          printf >&2 '[security-mode] WARNING: SYMBIOTE_SECURITY_FORCE=off — 모든 gated hook/feature 비활성.\n'
          export _SEC_MODE_FORCE_WARNED=1
        }
        return 1
        ;;
      on)
        return 0
        ;;
    esac
  fi
  if [ -n "${SYMBIOTE_SECURITY_FORCE:-}" ] && [ "${SYMBIOTE_TESTING:-0}" != "1" ]; then
    [ -z "${_SEC_MODE_UNGATED_WARNED:-}" ] && {
      printf >&2 '[security-mode] WARNING: SYMBIOTE_SECURITY_FORCE는 SYMBIOTE_TESTING=1 없으면 무시됩니다.\n'
      export _SEC_MODE_UNGATED_WARNED=1
    }
  fi
  return 2  # override 없음 — 호출자는 정상 경로로
}

# Public API: hook이 활성화되어 있나?
is_hook_enabled() {
  local hook_name="$1"
  [ -z "$hook_name" ] && return 0

  # `|| ov=$?` 패턴으로 set -e 우회: _sec_mode_env_override가 2를 반환해도
  # 상위의 set -e가 subshell을 죽이지 않도록.
  local ov=0
  _sec_mode_env_override || ov=$?
  [ "$ov" = 0 ] && return 0
  [ "$ov" = 1 ] && return 1

  _sec_mode_is_known_hook "$hook_name" || return 0  # 모르는 hook = fail-open

  local cache
  cache=$(_sec_mode_ensure_cache) || return 0
  [ -z "$cache" ] && return 0

  local value
  value=$(awk -F= -v k="$hook_name" '$1==k {print $2; exit}' "$cache" 2>/dev/null)
  case "$value" in
    false) return 1 ;;
    *) return 0 ;;  # true / 미지정 모두 fail-open
  esac
}

# Public API: (hook, feature) 조합이 활성화되어 있나?
# hook 자체가 off면 feature도 off. 나머지는 cache 값으로 판정.
is_feature_enabled() {
  local hook_name="$1"
  local feature_name="$2"
  [ -z "$hook_name" ] && return 0
  [ -z "$feature_name" ] && {
    is_hook_enabled "$hook_name"
    return $?
  }

  # `|| ov=$?` 패턴으로 set -e 우회: _sec_mode_env_override가 2를 반환해도
  # 상위의 set -e가 subshell을 죽이지 않도록.
  local ov=0
  _sec_mode_env_override || ov=$?
  [ "$ov" = 0 ] && return 0
  [ "$ov" = 1 ] && return 1

  _sec_mode_is_known_feature "$hook_name" "$feature_name" || return 0  # 모르는 feature = fail-open

  # 먼저 hook 레벨 체크 (hook 꺼져 있으면 feature도 꺼짐).
  is_hook_enabled "$hook_name" || return 1

  local cache
  cache=$(_sec_mode_ensure_cache) || return 0
  [ -z "$cache" ] && return 0

  local key="$hook_name.$feature_name"
  local value
  value=$(awk -F= -v k="$key" '$1==k {print $2; exit}' "$cache" 2>/dev/null)
  case "$value" in
    false) return 1 ;;
    *) return 0 ;;
  esac
}

# 진단용: 현재 모드 출력.
get_security_mode() {
  local cache
  cache=$(_sec_mode_ensure_cache) || { printf 'balanced'; return 0; }
  if [ -n "$cache" ] && [ -f "$cache" ]; then
    local mode
    mode=$(awk -F= '$1=="mode" {print $2; exit}' "$cache" 2>/dev/null)
    [ -n "$mode" ] && { printf '%s' "$mode"; return 0; }
  fi
  printf 'balanced'
}

# 진단용: 전체 feature 매트릭스를 "hook.feature=bool" 라인으로 출력.
# `/security feature`가 사람이 읽기 쉬운 포맷으로 가공.
get_security_matrix() {
  local cache
  cache=$(_sec_mode_ensure_cache) || return 1
  [ -n "$cache" ] && [ -f "$cache" ] && cat "$cache"
}
