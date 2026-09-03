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
# 경고 대상 목록의 단일 출처는 dep-skills.md 다. 표에서 소문자로 시작하는 첫 셀만 스킬 이름으로 읽는다.
MANIFEST="$REPO_DIR/dep-skills.md"
DEP_SKILLS=()
if [[ -f "$MANIFEST" ]]; then
  while IFS= read -r line || [[ -n $line ]]; do   # || 절 — 개행 없이 끝나는 마지막 행도 읽는다
    # 손편집·붙여넣기가 남기는 비ASCII 공백류는 [:space:] 분류가 로케일마다 달라 바이트 리터럴로 지운다
    line="${line//$'\xc2\xa0'/}"                  # NBSP(U+00A0) — macOS Option+Space
    line="${line//$'\xe3\x80\x80'/}"              # 전각 공백(U+3000) — CJK IME 전각 모드
    line="${line//$'\xe2\x80\x8b'/}"              # ZWSP(U+200B)
    line="${line//$'\xef\xbb\xbf'/}"              # BOM/ZWNBSP(U+FEFF) — 붙여넣기 잔여물
    line="${line#"${line%%[![:space:]]*}"}"       # 앞 공백 제거 — 들여쓴 표 행도 표 행이다
    [[ $line == \|* ]] || continue                # 표 행이 아니면 건너뜀
    IFS='|' read -r _lead cell _rest <<<"$line"
    cell="${cell//[[:space:]]/}"                  # 정렬용 공백 제거 — 스킬 이름에는 공백이 없다
    case "$cell" in
      # 소문자를 [a-z] 범위 대신 나열한다 — 범위는 로케일에 따라 대문자까지 매치한다(bash 3.2)
      [abcdefghijklmnopqrstuvwxyz]*) DEP_SKILLS+=("$cell") ;;   # 헤더(한글·영문)·구분선(-, :)은 배제
    esac
  done < "$MANIFEST"
fi
if [[ ${#DEP_SKILLS[@]} -eq 0 ]]; then
  {
    echo ""
    echo "경고: 의존 스킬 매니페스트($MANIFEST)에서 스킬 목록을 읽지 못했습니다 — 존재 확인을 건너뜁니다."
  } >&2
fi
MISSING=()
if [[ ${#DEP_SKILLS[@]} -gt 0 ]]; then
  for skill in "${DEP_SKILLS[@]}"; do
    if [[ ! -f "$TARGET_ROOT/skills/$skill/SKILL.md" && ! -f "$HOME/.claude/skills/$skill/SKILL.md" ]]; then
      MISSING+=("$skill")
    fi
  done
fi
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
