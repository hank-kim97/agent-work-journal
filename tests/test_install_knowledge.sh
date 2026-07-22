#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
. "$HERE/helpers.sh"

# config.json 백업/복원
if [ -f "$ROOT/config.json" ]; then
  cp "$ROOT/config.json" "$ROOT/config.json.bak"
  trap 'mv "$ROOT/config.json.bak" "$ROOT/config.json"' EXIT
else
  trap 'rm -f "$ROOT/config.json"' EXIT
fi

sandbox_home="$(mktemp -d)"          # ~/.claude 오염 방지
repo_parent="$(mktemp -d)"

# git 신원 없는 환경 대비
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

HOME="$sandbox_home" bash "$ROOT/install-knowledge.sh" --repo "$repo_parent/kb" >/dev/null
assert_eq "$?" "0" "installer exits 0"

# 1) config에 knowledge_repo 기록
got=$(python3 -c "import json;print(json.load(open('$ROOT/config.json')).get('knowledge_repo',''))")
assert_eq "$got" "$repo_parent/kb" "config.json knowledge_repo written"

# 2) 레포 스캐폴드: cards/ + .gitignore(.extract-cursor) + 초기 커밋
[ -d "$repo_parent/kb/cards" ] && pass "cards/ scaffolded" || fail "cards/ scaffolded"
# git은 빈 디렉토리를 추적하지 않음 — .gitkeep이 없으면 clone한 팀원의 cards/가 사라짐
git -C "$repo_parent/kb" ls-files | grep -q "cards/.gitkeep" \
  && pass "cards/.gitkeep tracked (clone keeps cards/)" || fail "cards/.gitkeep tracked (clone keeps cards/)"
assert_file_contains "$repo_parent/kb/.gitignore" ".extract-cursor" "cursor gitignored"
( cd "$repo_parent/kb" && git log --oneline | grep -q scaffold ) \
  && pass "scaffold committed" || fail "scaffold committed"

# 3) 스킬 설치 + <TOOL_DIR> 치환
skill="$sandbox_home/.claude/skills/knowledge/SKILL.md"
[ -f "$skill" ] && pass "skill installed under sandbox HOME" || fail "skill installed under sandbox HOME"
assert_file_contains "$skill" "$ROOT/config.json" "TOOL_DIR placeholder substituted"
grep -q '<TOOL_DIR>' "$skill" && fail "no raw placeholder remains" || pass "no raw placeholder remains"

# 4) 멱등: 재실행해도 성공
HOME="$sandbox_home" bash "$ROOT/install-knowledge.sh" --repo "$repo_parent/kb" >/dev/null
assert_eq "$?" "0" "re-run is idempotent"

finish
