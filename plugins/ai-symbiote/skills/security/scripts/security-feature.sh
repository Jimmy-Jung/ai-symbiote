#!/usr/bin/env bash
# /security feature — 세부 보안 기능 개별 토글 + 상태 표시.
#
# Author: JunyoungJung
# Date: 2026-04-21
#
# 사용법:
#   security-feature.sh --state-dir DIR                              # 전체 matrix 표시
#   security-feature.sh --state-dir DIR --target hook.feature --value on
#   security-feature.sh --state-dir DIR --target hook.feature --value off
#
# 허용 target 예시:
#   guardShell.chmod777
#   guardShell.echoSecrets
#   securityGuard.xssRisk
#   harnessLearn.editChurn
#   commentChecker.tagComments
#   verifyQueue            (hook-level, 세부 feature 없음)
#
# 세부 feature를 토글하면 mode가 자동으로 `custom`으로 전환됩니다 (prereset과
# 구분). 설정은 manifest.json의 `security.features.<hook>.<feature>`에 저장되고
# 다음 hook fire부터 즉시 반영됩니다 (Claude Code 재시작 불필요).

set -euo pipefail

STATE_DIR=""
TARGET=""
VALUE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --state-dir)
      STATE_DIR="${2:-}"
      shift 2
      ;;
    --target)
      TARGET="${2:-}"
      shift 2
      ;;
    --value)
      VALUE="${2:-}"
      shift 2
      ;;
    -h|--help)
      sed -n '1,22p' "$0"
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [ -z "$STATE_DIR" ]; then
  echo "Usage: security-feature.sh --state-dir DIR [--target hook.feature --value on|off]" >&2
  exit 1
fi

MANIFEST="$STATE_DIR/manifest.json"
CACHE_FILE="$STATE_DIR/state/security-mode.cache"

if [ ! -f "$MANIFEST" ]; then
  echo "[Security] manifest.json not found: $MANIFEST" >&2
  echo "/ai-symbiote:setup으로 프로젝트를 먼저 초기화하세요." >&2
  exit 1
fi

# --- No target ⇒ show matrix ---
show_matrix() {
  if [ ! -f "$CACHE_FILE" ]; then
    echo "[Security] cache가 아직 생성되지 않았습니다 (다음 hook fire 때 자동 생성)."
    return 0
  fi

  local mode
  mode=$(awk -F= '$1=="mode" {print $2; exit}' "$CACHE_FILE")
  echo "[Security] current mode: ${mode:-balanced}"
  echo ""
  echo "Hook-level 상태 (enabled: false면 하위 feature 전부 무시):"
  awk -F= '$1!="mode" && $1 !~ /\./ { printf "  %-20s  %s\n", $1, $2 }' "$CACHE_FILE" | sort
  echo ""
  echo "세부 feature 상태:"
  awk -F= '$1 ~ /\./ { printf "  %-40s  %s\n", $1, $2 }' "$CACHE_FILE" | sort
  echo ""
  echo "세부 설명: docs/09-보안-기능-세부토글.md"
  echo ""
  echo "한 feature만 토글:"
  echo "  /ai-symbiote:security feature guardShell.chmod777 off"
  echo "  /ai-symbiote:security feature securityGuard.xssRisk on"
  echo ""
  echo "전체 preset 전환:"
  echo "  /ai-symbiote:security mode minimal      # 전부 off"
  echo "  /ai-symbiote:security mode balanced     # 전부 on (기본)"
}

if [ -z "$TARGET" ]; then
  show_matrix
  exit 0
fi

if [ -z "$VALUE" ]; then
  echo "Usage: security-feature.sh --state-dir DIR --target hook.feature --value on|off" >&2
  exit 1
fi

case "$VALUE" in
  on|true|yes|1) BOOL="true" ;;
  off|false|no|0) BOOL="false" ;;
  *)
    echo "[Security] invalid value '$VALUE' — must be on|off (또는 true|false)" >&2
    exit 1
    ;;
esac

# TARGET 파싱: "hook.feature" 형태 또는 "hook" (hook-level)
HOOK="${TARGET%%.*}"
FEATURE=""
if [ "$HOOK" != "$TARGET" ]; then
  FEATURE="${TARGET#*.}"
fi

# --- manifest.json 업데이트 ---
python3 - "$MANIFEST" "$HOOK" "$FEATURE" "$BOOL" <<'PY'
import json
import sys
from pathlib import Path

manifest_path = Path(sys.argv[1])
hook = sys.argv[2]
feature = sys.argv[3]
bool_str = sys.argv[4]
value = bool_str == "true"

# Canonical hook + feature 목록 (security-mode.sh의 _SEC_MODE_FEATURE_PAIRS와 동기화).
HOOKS = {"guardShell", "securityGuard", "harnessLearn", "commentChecker", "verifyQueue"}
FEATURES = {
    "guardShell": {
        "echoSecrets", "authHeaderLeak", "gitAddEnv", "base64Secret", "exportSecret",
        "remoteEval", "chmod777", "unsafeInstallFlags", "dockerPrivileged",
        "bindAllInterfaces", "inlineNetworkExec",
        "archiveSensitive", "sensitiveTransfer", "envDumpToFile", "secretsInGitPush",
        "netcatExfiltration",
    },
    "securityGuard": {"hardcodedSecrets", "envFileLeak", "sqlInjection", "xssRisk", "debugModeOn", "evalUsage"},
    "harnessLearn": {"errorTracking", "editChurn", "ruleLearning", "guardLogging"},
    "commentChecker": {"obviousComments", "keywordComments", "tagComments"},
    "verifyQueue": set(),  # 세부 feature 없음 (enabled만)
}

if hook not in HOOKS:
    print(f"[Security] unknown hook '{hook}'. Valid: {sorted(HOOKS)}", file=sys.stderr)
    sys.exit(1)

if feature and feature not in FEATURES[hook]:
    valid = sorted(FEATURES[hook]) or ["(세부 feature 없음 — target은 'verifyQueue'만 사용)"]
    print(f"[Security] unknown feature '{hook}.{feature}'. Valid {hook} features: {valid}", file=sys.stderr)
    sys.exit(1)

try:
    data = json.loads(manifest_path.read_text())
except Exception as exc:
    print(f"[Security] manifest parse 실패: {exc}", file=sys.stderr)
    sys.exit(1)

security = data.get("security")
if not isinstance(security, dict):
    security = {}
# 세부 feature 토글은 mode=custom을 의미 — preset과 충돌 방지.
security["mode"] = "custom"

features_block = security.get("features")
if not isinstance(features_block, dict):
    features_block = {}

hook_block = features_block.get(hook)
if not isinstance(hook_block, dict):
    hook_block = {}

if feature:
    hook_block[feature] = value
    # feature를 켰는데 enabled가 false면 사용자 의도와 충돌 — 자동 true로 맞춤.
    if value and not hook_block.get("enabled", True):
        hook_block["enabled"] = True
else:
    # hook-level 토글
    hook_block["enabled"] = value

# 다른 hook의 기본값 보존.
for other_hook in HOOKS:
    if other_hook not in features_block:
        features_block[other_hook] = {"enabled": True}

features_block[hook] = hook_block
security["features"] = features_block
# sessionSummaryLevel 유지.
security.setdefault("sessionSummaryLevel", "auto")
data["security"] = security

# Atomic write via tempfile + rename.
import os
import tempfile
tmp = tempfile.NamedTemporaryFile(
    mode="w", delete=False,
    dir=str(manifest_path.parent),
    prefix=".manifest.",
    suffix=".tmp",
)
try:
    tmp.write(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
    tmp.flush()
    os.fsync(tmp.fileno())
    tmp.close()
    os.replace(tmp.name, str(manifest_path))
except Exception:
    try:
        os.unlink(tmp.name)
    except Exception:
        pass
    raise

if feature:
    print(f"[Security] {hook}.{feature} = {bool_str}")
else:
    print(f"[Security] {hook}.enabled = {bool_str}")
PY

# Cache 무효화 → 다음 hook fire 시 재빌드.
rm -f "$CACHE_FILE" 2>/dev/null || true

echo ""
show_matrix
