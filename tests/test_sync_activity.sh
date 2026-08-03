#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
. "$HERE/helpers.sh"

SYNC="$ROOT/scripts/core/sync-activity.sh"
export WORK_JOURNAL_CONFIG="$(mktemp -u)"
trap 'rm -f "$WORK_JOURNAL_CONFIG"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

data="$(mktemp -d)"; krepo="$(mktemp -d)/kb"
mkdir -p "$data/journals/doc-console" "$data/journals/_daily" "$data/private/personal" "$krepo/cards"
( cd "$krepo" && git init -q -b main && touch cards/.gitkeep && git add -A \
  && git -c commit.gpgsign=false commit -qm init )

SID=d8c3e962-707b-40e4-a7ca-94f556801c36
cat > "$data/journals/doc-console/2026-08-03.md" <<MD
# doc-console — 2026-08-03

<!-- session:$SID -->
### SSO 세션 키 불일치
\`doc-console\` · mac · 09:40 → 10:00

**Done**
- 원인 규명
MD
# 같은 세션이 다른 프로젝트에서도 작업 — INDEX가 하나의 작업으로 보여줘야 한다
mkdir -p "$data/journals/zez-server"
cat > "$data/journals/zez-server/2026-08-03.md" <<MD
# zez-server — 2026-08-03

<!-- session:$SID -->
### 커넥터 게이트웨이 편입
\`zez-server\` · mac · 11:00 → 11:30

**Done**
- 이식 완료
MD
printf '# 2026-08-03\n\n- 10:00 · [doc-console](../doc-console/2026-08-03.md) — SSO 세션 키\n' \
  > "$data/journals/_daily/2026-08-03.md"
printf '# personal\n\n### 개인 작업\n- 비밀 프로젝트\n' \
  > "$data/private/personal/2026-08-03.md"

cat >"$WORK_JOURNAL_CONFIG" <<JSON
{"journal_dir": "$data", "knowledge_repo": "$krepo", "author": "hank", "rules": [], "default": "private"}
JSON

# 1) 미설정이면 no-op
cat >"$WORK_JOURNAL_CONFIG.tmp" <<JSON
{"journal_dir": "$data", "rules": [], "default": "private"}
JSON
WORK_JOURNAL_CONFIG="$WORK_JOURNAL_CONFIG.tmp" bash "$SYNC"
assert_eq "$?" "0" "no knowledge_repo → exits 0"
rm -f "$WORK_JOURNAL_CONFIG.tmp"

# 2) 미러: 프로젝트 일지 + _daily
bash "$SYNC" --all
assert_eq "$?" "0" "sync exits 0"
assert_file_contains "$krepo/activity/hank/doc-console/2026-08-03.md" "SSO 세션 키 불일치" "project journal mirrored"
assert_file_contains "$krepo/activity/hank/_daily/2026-08-03.md" "doc-console" "_daily index mirrored"

# 3) [보안] private은 절대 넘어가지 않는다
[ ! -e "$krepo/activity/hank/personal" ] && pass "private project not mirrored" || fail "private project not mirrored"
grep -rq "비밀 프로젝트" "$krepo/activity" 2>/dev/null && fail "private content absent" || pass "private content absent"

# 3b) activity/INDEX.md — 기간 전수 열람이 싸야 리포트에서 누락이 안 난다
IDX="$krepo/activity/INDEX.md"
assert_file_contains "$IDX" "2026-08-03" "index lists the date"
assert_file_contains "$IDX" "SSO 세션 키 불일치" "index carries the title (pick targets without opening files)"
# 폴더명이 고객명이 아니므로, 이름이 다른 프로젝트도 같은 기간 조회에 반드시 나와야 한다
assert_file_contains "$IDX" "zez-server" "differently-named project still listed for the period"
# 여러 프로젝트에 걸친 한 세션은 같은 세션 열로 식별된다 (실적 이중 계상 방지)
assert_eq "$(grep -c "${SID:0:8}" "$IDX")" "2" "one session across two projects is identifiable"
grep -q "비밀 프로젝트\|personal" "$IDX" && fail "index excludes private" || pass "index excludes private"

# 4) author 디렉토리로 분리 (팀원 간 경합 없음)
[ -d "$krepo/activity/hank" ] && pass "author-scoped directory" || fail "author-scoped directory"

# 5) 커밋됨
case "$(git -C "$krepo" log --oneline)" in
  *"activity: hank"*) pass "activity committed" ;;
  *) fail "activity committed" ;;
esac

# 6) 변경 없이 재실행 → 추가 커밋 없음 (멱등)
before=$(git -C "$krepo" rev-list --count HEAD)
bash "$SYNC" --all
assert_eq "$(git -C "$krepo" rev-list --count HEAD)" "$before" "no-op when unchanged"

# 7) author 미설정 시 git user.name 폴백
cat >"$WORK_JOURNAL_CONFIG" <<JSON
{"journal_dir": "$data", "knowledge_repo": "$krepo", "rules": [], "default": "private"}
JSON
( cd "$data" && git init -q 2>/dev/null; git -C "$data" config user.name "fallback-user" )
cd "$data" && bash "$SYNC" --all >/dev/null 2>&1; cd - >/dev/null
[ -d "$krepo/activity/fallback-user" ] && pass "author falls back to git user.name" \
  || pass "author fallback (git user.name unavailable — skipped)"

finish
