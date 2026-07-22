#!/usr/bin/env bash
# Opt-in installer for the RE팀 업무 기록 (team knowledge) extension.
# Core journaling (install.sh) is untouched — this wires three things:
#   1. config.json knowledge_repo   ← where distilled cards live
#   2. that repo's scaffold         ← cards/ + git init (if missing)
#   3. ~/.claude/skills/knowledge   ← /knowledge search skill
# Scheduling is intentionally NOT auto-registered (no cron reintroduction);
# options are printed at the end.
#
# Usage: bash install-knowledge.sh --repo <path>   (e.g. ~/re-team-work-log)
set -euo pipefail

TOOL_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done
[ -z "$REPO" ] && { echo "usage: bash install-knowledge.sh --repo <path>" >&2; exit 2; }

# ~ expansion
case "$REPO" in "~"/*) REPO="$HOME/${REPO#\~/}";; "~") REPO="$HOME";; esac

# 1) config.json에 knowledge_repo 기록
[ -f "$TOOL_DIR/config.json" ] || cp "$TOOL_DIR/config.example.json" "$TOOL_DIR/config.json"
python3 - "$TOOL_DIR/config.json" "$REPO" <<'PY'
import json, sys
p, repo = sys.argv[1], sys.argv[2]
d = json.load(open(p))
d["knowledge_repo"] = repo
json.dump(d, open(p, "w"), indent=2, ensure_ascii=False)
print(f"config.json: knowledge_repo = {repo}")
PY

# 2) 지식 레포 스캐폴드
if [ ! -d "$REPO/.git" ]; then
  mkdir -p "$REPO/cards"
  touch "$REPO/cards/.gitkeep"   # git tracks no empty dirs — without this, clones lose cards/
  ( cd "$REPO" && git init -q -b main )
  printf '.extract-cursor\n' > "$REPO/.gitignore"   # per-machine cursor stays local
  [ -f "$REPO/README.md" ] || cat > "$REPO/README.md" <<'MD'
# RE팀 업무 기록

팀원들의 agent-work-journal 일지에서 주간 자동 증류되는 트러블슈팅 지식 카드.

- `cards/` — 카드 (문제상황→시도→해결→정리, frontmatter: tags/sources)
- `INDEX.md` — 자동 생성 목록 (직접 편집 금지)
- `excluded.md` — 경계 규칙(단일 고객/프로젝트 이슈 제외) 감사 추적
- 검색: `/knowledge` 스킬
MD
  ( cd "$REPO" && git add -A && git -c commit.gpgsign=false commit -qm "chore: scaffold RE-team knowledge repo" )
  echo "knowledge repo scaffolded: $REPO"
else
  # member-#2 path: repo was cloned from the team remote — heal a missing
  # cards/ (e.g. scaffolded before .gitkeep existed, or empty default branch)
  if [ ! -d "$REPO/cards" ]; then
    mkdir -p "$REPO/cards"; touch "$REPO/cards/.gitkeep"
    echo "knowledge repo exists: $REPO (cards/ was missing — created)"
  else
    echo "knowledge repo exists: $REPO"
  fi
fi

# 3) /knowledge 스킬 설치 (<TOOL_DIR> 치환)
SKILL_DST="$HOME/.claude/skills/knowledge"
mkdir -p "$SKILL_DST"
sed "s|<TOOL_DIR>|$TOOL_DIR|g" "$TOOL_DIR/skills/knowledge/SKILL.md" > "$SKILL_DST/SKILL.md"
echo "skill installed: $SKILL_DST/SKILL.md"

cat <<EOF

==> 완료. 주간 추출은 자동 등록하지 않습니다 — 원하는 방식 하나를 선택하세요:
    [수동]    bash $TOOL_DIR/scripts/core/extract-knowledge.sh
    [launchd] 주 1회 위 명령을 실행하는 plist 등록 (macOS)
    [cloud]   claude 스케줄 루틴에 위 명령 실행을 위임
    로그: ~/.claude/knowledge-extract.log
    팀 공유: $REPO 에 원격(remote)을 붙이면 추출 후 자동 push됩니다.
EOF
