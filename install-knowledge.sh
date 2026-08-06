#!/usr/bin/env bash
# Opt-in installer for the team-knowledge extension. --team names the record
# (default "팀 업무 기록"); each team keeps its own repo, so nothing here is
# specific to one team.
# Core journaling (install.sh) is untouched — this wires three things:
#   1. config.json knowledge_repo   ← where distilled cards live
#   2. that repo's scaffold         ← cards/ + git init (if missing)
#   3. ~/.claude/skills/bc-knowledge ← /bc-knowledge search skill
# Scheduling is intentionally NOT auto-registered (no cron reintroduction);
# options are printed at the end.
#
# Usage: bash install-knowledge.sh --repo <path> [--team "<이름>"]
set -euo pipefail

TOOL_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG="${WORK_JOURNAL_CONFIG:-$TOOL_DIR/config.json}"   # tests override this
REPO=""; TEAM=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --team) TEAM="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done
[ -z "$REPO" ] && { echo "usage: bash install-knowledge.sh --repo <path> [--team '<이름>']" >&2; exit 2; }

# ~ expansion
case "$REPO" in "~"/*) REPO="$HOME/${REPO#\~/}";; "~") REPO="$HOME";; esac

# 1) config.json에 knowledge_repo 기록
[ -f "$CONFIG" ] || cp "$TOOL_DIR/config.example.json" "$CONFIG"
python3 - "$CONFIG" "$REPO" "$TEAM" <<'PY'
import json, sys
p, repo, team = sys.argv[1], sys.argv[2], sys.argv[3]
d = json.load(open(p))
d["knowledge_repo"] = repo
# --team wins; otherwise keep what is already configured, else a neutral default
d["team_name"] = team or d.get("team_name") or "팀 업무 기록"
json.dump(d, open(p, "w"), indent=2, ensure_ascii=False)
print(f"config.json: knowledge_repo = {repo}")
PY

TEAM="$(python3 -c "import json;print(json.load(open('$CONFIG'))['team_name'])")"

# 2) 지식 레포 스캐폴드
if [ ! -d "$REPO/.git" ]; then
  mkdir -p "$REPO/cards"
  touch "$REPO/cards/.gitkeep"   # git tracks no empty dirs — without this, clones lose cards/
  ( cd "$REPO" && git init -q -b main )
  printf '.extract-cursor\n' > "$REPO/.gitignore"   # per-machine cursor stays local
  [ -f "$REPO/README.md" ] || cat > "$REPO/README.md" <<MD
# $TEAM

팀원들의 Claude Code 세션에서 자동으로 모이는 업무 기록과 기술 지식.

- \`activity/<사람>/\` — 일지 원문 (누가·언제·무엇을) + 사람별 \`INDEX.md\`
- \`cards/\` — 증류된 트러블슈팅 지식 (문제상황→시도→해결→검증 상태→정리)
- \`INDEX.md\` — 카드 목록 (자동 생성, 직접 편집 금지)
- \`excluded.md\` — 경계 규칙으로 제외된 항목의 감사 추적
- 조회: \`/bc-knowledge\` 스킬

**⚠️ 사내 전용 — 익명화하지 않습니다.** 고객명·서버 주소·사번·담당자 실명이 그대로 들어갑니다.
접근 권한이 유일한 경계이며, 고객 제출 문서에 이 내용을 그대로 붙이지 마세요.
MD
  ( cd "$REPO" && git add -A && git -c commit.gpgsign=false commit -qm "chore: scaffold team knowledge repo" )
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
SKILL_DST="$HOME/.claude/skills/bc-knowledge"
mkdir -p "$SKILL_DST"
sed -e "s|<TOOL_DIR>|$TOOL_DIR|g" -e "s|<TEAM_NAME>|$TEAM|g" \
  "$TOOL_DIR/skills/bc-knowledge/SKILL.md" > "$SKILL_DST/SKILL.md"
echo "skill installed: $SKILL_DST/SKILL.md"

cat <<EOF

==> 완료. 주간 추출은 자동 등록하지 않습니다 — 원하는 방식 하나를 선택하세요:
    [수동]    bash $TOOL_DIR/scripts/core/extract-knowledge.sh
    [launchd] 주 1회 위 명령을 실행하는 plist 등록 (macOS)
    [cloud]   claude 스케줄 루틴에 위 명령 실행을 위임
    로그: ~/.claude/knowledge-extract.log
    팀 공유: $REPO 에 원격(remote)을 붙이면 추출 후 자동 push됩니다.
EOF
