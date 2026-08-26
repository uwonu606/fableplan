#!/usr/bin/env bash
# fableplan 설치 스크립트
#
# 사용법:
#   bash install.sh                # 전역 설치 (~/.claude) — 모든 프로젝트에서 /fableplan 사용 가능
#   bash install.sh --project      # 현재 디렉토리의 .claude/ 에 설치
#   bash install.sh --uninstall            # 전역 설치 제거
#   bash install.sh --project --uninstall  # 프로젝트 설치 제거
#   bash install.sh --help|-h              # 이 도움말 출력
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'EOF'
사용법:
  bash install.sh                # 전역 설치 (~/.claude) — 모든 프로젝트에서 /fableplan 사용 가능
  bash install.sh --project      # 현재 디렉토리의 .claude/ 에 설치
  bash install.sh --uninstall            # 전역 설치 제거
  bash install.sh --project --uninstall  # 프로젝트 설치 제거
  bash install.sh --help|-h              # 이 도움말 출력
EOF
}

TARGET_ROOT="$HOME/.claude"
UNINSTALL=false

for arg in "$@"; do
  case "$arg" in
    --help|-h)   usage; exit 0 ;;
    --project)   TARGET_ROOT="$(pwd)/.claude" ;;
    --uninstall) UNINSTALL=true ;;
    *)
      echo "알 수 없는 옵션: $arg" >&2
      usage >&2
      exit 1
      ;;
  esac
done

SKILL_DEST="$TARGET_ROOT/skills/fableplan"
PLANNER_DEST="$TARGET_ROOT/agents/fable-planner.md"
BUILDER_DEST="$TARGET_ROOT/agents/opus-builder.md"

if $UNINSTALL; then
  rm -rf "$SKILL_DEST"
  rm -f "$PLANNER_DEST" "$BUILDER_DEST"
  echo "제거 완료:"
  echo "  - $SKILL_DEST"
  echo "  - $PLANNER_DEST"
  echo "  - $BUILDER_DEST"
  exit 0
fi

mkdir -p "$TARGET_ROOT/skills" "$TARGET_ROOT/agents"
rm -rf "$SKILL_DEST"
cp -r "$REPO_DIR/skills/fableplan" "$SKILL_DEST"
cp "$REPO_DIR/agents/fable-planner.md" "$PLANNER_DEST"
cp "$REPO_DIR/agents/opus-builder.md" "$BUILDER_DEST"

echo "설치 완료:"
echo "  - $SKILL_DEST/SKILL.md"
echo "  - $PLANNER_DEST"
echo "  - $BUILDER_DEST"
echo ""
echo "새 Claude Code 세션에서 /fableplan <작업 설명> 으로 사용하세요."
echo "세션 모델과 무관하게 플랜은 Fable, 구현은 Opus subagent가 수행합니다."

# 의존 스킬 존재 확인 — 없어도 설치는 계속한다 (해당 단계는 실행 시 건너뜀)
DEP_SKILLS=(grilling explore-model tdd code-review scoped-commits)
MISSING=()
for skill in "${DEP_SKILLS[@]}"; do
  if [[ ! -f "$TARGET_ROOT/skills/$skill/SKILL.md" && ! -f "$HOME/.claude/skills/$skill/SKILL.md" ]]; then
    MISSING+=("$skill")
  fi
done
if [[ ${#MISSING[@]} -gt 0 ]]; then
  {
    echo ""
    echo "경고: 워크플로가 참조하는 스킬이 설치돼 있지 않습니다:"
    for skill in "${MISSING[@]}"; do
      echo "  - $skill"
    done
    echo "없어도 동작합니다 — 해당 스킬을 쓰는 단계는 실행 시 건너뜁니다."
    echo "플러그인 등 다른 경로로 설치돼 있다면 이 경고는 무시하세요."
  } >&2
fi
