#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
. "$HERE/helpers.sh"

# isolated temp config — new-member scenario means it starts absent
export WORK_JOURNAL_CONFIG="$(mktemp -u)"
trap 'rm -f "$WORK_JOURNAL_CONFIG"' EXIT

sandbox="$(mktemp -d)"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

# 팀 지식 원격 준비 (기존 팀 레포 — .gitkeep 포함)
seed="$sandbox/seed"; mkdir -p "$seed/cards"
( cd "$seed" && git init -q -b main && touch cards/.gitkeep && printf '.extract-cursor\n' > .gitignore \
  && git add -A && git -c commit.gpgsign=false commit -qm scaffold )
git clone -q --bare "$seed" "$sandbox/team-kb.git"

HOME="$sandbox/home" bash "$ROOT/setup-team-member.sh" \
  --work-prefix "$sandbox/projects" \
  --journal-dir "$sandbox/home/work-journal-data" \
  --knowledge-remote "$sandbox/team-kb.git" \
  --knowledge-dir "$sandbox/home/re-team-work-log" >/dev/null 2>&1
assert_eq "$?" "0" "wizard exits 0"

# 1) config: journal_dir + work rule
got=$(python3 -c "import json;d=json.load(open('$WORK_JOURNAL_CONFIG'));print(d['journal_dir'], d['rules'][0]['prefix'], d['rules'][0]['category'])")
assert_eq "$got" "$sandbox/home/work-journal-data $sandbox/projects work" "config wired"

# 2) 훅
grep -q "adapters/claude-code.sh" "$sandbox/home/.claude/settings.json" && pass "hook wired" || fail "hook wired"

# 3) 데이터 레포 init + private gitignore
[ -d "$sandbox/home/work-journal-data/.git" ] && pass "data repo initialized" || fail "data repo initialized"
assert_file_contains "$sandbox/home/work-journal-data/.gitignore" "private/" "private gitignored"

# 4) 지식 레포 clone (cards/ 유지) + 스킬 설치
[ -d "$sandbox/home/re-team-work-log/cards" ] && pass "knowledge repo cloned with cards/" || fail "knowledge repo cloned with cards/"
[ -f "$sandbox/home/.claude/skills/knowledge/SKILL.md" ] && pass "knowledge skill installed" || fail "knowledge skill installed"
kr=$(python3 -c "import json;print(json.load(open('$WORK_JOURNAL_CONFIG')).get('knowledge_repo',''))")
assert_eq "$kr" "$sandbox/home/re-team-work-log" "knowledge_repo configured"

# 5) 멱등 재실행 (rule 중복 없음)
HOME="$sandbox/home" bash "$ROOT/setup-team-member.sh" \
  --work-prefix "$sandbox/projects" \
  --journal-dir "$sandbox/home/work-journal-data" \
  --knowledge-remote "$sandbox/team-kb.git" \
  --knowledge-dir "$sandbox/home/re-team-work-log" >/dev/null 2>&1
assert_eq "$?" "0" "re-run idempotent"
n=$(python3 -c "import json;print(len(json.load(open('$WORK_JOURNAL_CONFIG'))['rules']))")
assert_eq "$n" "1" "no duplicate rules on re-run"

finish
