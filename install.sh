#!/usr/bin/env bash
# fableplan 설치 스크립트
#
# 사용법:
#   bash install.sh                # 전역 설치 (~/.claude) — 모든 프로젝트에서 /fableplan 사용 가능
#   bash install.sh --project      # 현재 디렉토리의 .claude/ 에 설치
#   bash install.sh --uninstall            # 전역 설치 제거
#   bash install.sh --project --uninstall  # 프로젝트 설치 제거
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TARGET_ROOT="$HOME/.claude"
UNINSTALL=false

for arg in "$@"; do
  case "$arg" in
    --project)   TARGET_ROOT="$(pwd)/.claude" ;;
    --uninstall) UNINSTALL=true ;;
    *)
      echo "알 수 없는 옵션: $arg" >&2
      echo "사용법: bash install.sh [--project] [--uninstall]" >&2
      exit 1
      ;;
  esac
done

SKILL_DEST="$TARGET_ROOT/skills/fableplan"
AGENT_DEST="$TARGET_ROOT/agents/opus-builder.md"

if $UNINSTALL; then
  rm -rf "$SKILL_DEST"
  rm -f "$AGENT_DEST"
  echo "제거 완료:"
  echo "  - $SKILL_DEST"
  echo "  - $AGENT_DEST"
  exit 0
fi

mkdir -p "$TARGET_ROOT/skills" "$TARGET_ROOT/agents"
rm -rf "$SKILL_DEST"
cp -r "$REPO_DIR/skills/fableplan" "$SKILL_DEST"
cp "$REPO_DIR/agents/opus-builder.md" "$AGENT_DEST"

echo "설치 완료:"
echo "  - $SKILL_DEST/SKILL.md"
echo "  - $AGENT_DEST"
echo ""
echo "새 Claude Code 세션에서 /fableplan <작업 설명> 으로 사용하세요."
echo "플랜이 Fable로 작성되려면 세션 모델이 fable이어야 합니다 (/model fable)."
