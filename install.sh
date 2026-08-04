#!/usr/bin/env bash
# fableplan 설치 스크립트
#
# 사용법:
#   bash install.sh                # 전역 설치 (~/.claude) + 세션 모델을 fable[1m]로 설정
#   bash install.sh --project      # 현재 디렉토리의 .claude/ 에 설치
#   bash install.sh --keep-model           # 세션 모델 설정은 건드리지 않고 설치만
#   bash install.sh --model fable          # 세션 모델을 다른 값으로 설정 (기본: fable[1m])
#   bash install.sh --uninstall            # 전역 설치 제거
#   bash install.sh --project --uninstall  # 프로젝트 설치 제거
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TARGET_ROOT="$HOME/.claude"
UNINSTALL=false
SET_MODEL=true
MODEL="fable[1m]"

while [ $# -gt 0 ]; do
  case "$1" in
    --project)    TARGET_ROOT="$(pwd)/.claude" ;;
    --uninstall)  UNINSTALL=true ;;
    --keep-model) SET_MODEL=false ;;
    --model)
      shift
      if [ $# -eq 0 ]; then
        echo "--model 뒤에 값이 필요합니다 (예: --model fable[1m])" >&2
        exit 1
      fi
      MODEL="$1"
      ;;
    --model=*)    MODEL="${1#--model=}" ;;
    *)
      echo "알 수 없는 옵션: $1" >&2
      echo "사용법: bash install.sh [--project] [--keep-model] [--model <값>] [--uninstall]" >&2
      exit 1
      ;;
  esac
  shift
done

SKILL_DEST="$TARGET_ROOT/skills/fableplan"
AGENT_DEST="$TARGET_ROOT/agents/opus-builder.md"
SETTINGS="$TARGET_ROOT/settings.json"

if $UNINSTALL; then
  rm -rf "$SKILL_DEST"
  rm -f "$AGENT_DEST"
  echo "제거 완료:"
  echo "  - $SKILL_DEST"
  echo "  - $AGENT_DEST"
  echo ""
  echo "settings.json의 model 설정은 건드리지 않았습니다."
  echo "되돌리려면 $SETTINGS 의 \"model\" 값을 직접 수정하거나 /model 로 바꾸세요."
  exit 0
fi

mkdir -p "$TARGET_ROOT/skills" "$TARGET_ROOT/agents"
rm -rf "$SKILL_DEST"
cp -r "$REPO_DIR/skills/fableplan" "$SKILL_DEST"
cp "$REPO_DIR/agents/opus-builder.md" "$AGENT_DEST"

echo "설치 완료:"
echo "  - $SKILL_DEST/SKILL.md"
echo "  - $AGENT_DEST"

if ! $SET_MODEL; then
  echo ""
  echo "--keep-model 이 지정되어 세션 모델은 변경하지 않았습니다."
  echo "플랜이 Fable로 작성되려면 세션 모델이 fable이어야 합니다 (/model fable)."
elif ! command -v python3 >/dev/null 2>&1; then
  echo ""
  echo "python3가 없어 세션 모델을 자동 설정하지 못했습니다."
  echo "$SETTINGS 의 \"model\"을 \"$MODEL\"로 직접 설정하거나 /model 로 바꾸세요."
else
  echo ""
  MODEL="$MODEL" SETTINGS="$SETTINGS" python3 - <<'PY'
import json, os, shutil, sys

settings = os.environ["SETTINGS"]
model = os.environ["MODEL"]
backup = settings + ".bak"

if os.path.exists(settings):
    with open(settings, encoding="utf-8") as f:
        text = f.read()
    try:
        data = json.loads(text) if text.strip() else {}
    except json.JSONDecodeError as e:
        print(f"{settings} 를 파싱할 수 없어 model 설정을 건너뜁니다: {e}")
        print(f'직접 "model": "{model}" 을 추가하거나 /model 로 바꾸세요.')
        sys.exit(0)
    if not isinstance(data, dict):
        print(f"{settings} 의 최상위가 JSON 객체가 아니라 model 설정을 건너뜁니다.")
        sys.exit(0)
    previous = data.get("model")
    if previous == model:
        print(f'세션 모델은 이미 "{model}" 입니다. 변경하지 않았습니다.')
        sys.exit(0)
    shutil.copyfile(settings, backup)
    backed_up = True
else:
    os.makedirs(os.path.dirname(settings), exist_ok=True)
    data = {}
    previous = None
    backed_up = False

data["model"] = model
with open(settings, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write("\n")

print(f'세션 모델을 "{model}" 로 설정했습니다: {settings}')
if previous is None:
    print("  이전에는 model 설정이 없었습니다 (기본값 사용 중이었습니다).")
else:
    print(f'  이전 값: "{previous}"')
if backed_up:
    print(f"  백업: {backup}")
print("  이 설정은 플랜 단계뿐 아니라 세션 전체에 적용됩니다.")
PY
fi

echo ""
echo "새 Claude Code 세션에서 /fableplan <작업 설명> 으로 사용하세요."
