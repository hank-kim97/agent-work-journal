#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
. "$HERE/helpers.sh"

# data dir 준비 + config로 work/private/skip 분기 검증
data="$(mktemp -d)"
( cd "$data" && git init -q && git config user.email t@t && git config user.name t )

# Use an isolated temp config so a crash can never damage the real config.json
export WORK_JOURNAL_CONFIG="$(mktemp -u)"
trap 'rm -f "$WORK_JOURNAL_CONFIG"' EXIT

cat >"$WORK_JOURNAL_CONFIG" <<JSON
{"journal_dir": "$data",
 "rules": [
   {"prefix": "/tmp/wj-work", "category": "work", "project": "demo"},
   {"prefix": "/tmp/wj-skip", "category": "skip"}],
 "default": "private"}
JSON

SUMMARY=$'### 테스트 작업\n\n**Done**\n- 무언가 함'

# work → journals/demo/<date>.md 작성 + commit
echo "$SUMMARY" | bash "$ROOT/scripts/core/write-entry.sh" sess-1 2026-06-29 mac /tmp/wj-work/x 10:00
assert_file_contains "$data/journals/demo/2026-06-29.md" "테스트 작업" "work entry written"
assert_file_contains "$data/journals/_daily/2026-06-29.md" "demo" "daily index updated"
( cd "$data" && git log --oneline | grep -q demo ) && pass "work committed" || fail "work committed"

# 한 세션이 프로젝트를 넘나들어도 _daily는 둘 다 유지한다.
# (세션 ID만으로 키를 잡던 시절엔 뒤 항목이 앞 항목을 덮어써서, 실측 22일 중 9일의
#  기록이 조용히 사라졌다. 키는 (세션, 프로젝트)여야 한다.)
python3 - "$WORK_JOURNAL_CONFIG" <<'PY'
import json, sys
p = sys.argv[1]; c = json.load(open(p))
c["rules"].append({"prefix": "/tmp/wj-work2", "category": "work", "project": "other-proj"})
json.dump(c, open(p, "w"))
PY
echo "$SUMMARY" | bash "$ROOT/scripts/core/write-entry.sh" sess-1 2026-06-29 mac /tmp/wj-work2/x 10:30
daily="$data/journals/_daily/2026-06-29.md"
assert_file_contains "$daily" "other-proj" "same session, second project recorded"
assert_file_contains "$daily" "](../demo/" "same session, first project NOT overwritten"
assert_eq "$(grep -c '^- ' "$daily")" "2" "one line per (session, project)"
# 같은 (세션, 프로젝트) 재실행은 여전히 멱등
echo "$SUMMARY" | bash "$ROOT/scripts/core/write-entry.sh" sess-1 2026-06-29 mac /tmp/wj-work2/x 10:35
assert_eq "$(grep -c '^- ' "$daily")" "2" "re-running the same pair stays idempotent"

# 구 포맷(세션만 키) 항목은 다음 쓰기 때 자동 승격된다 — 중복 라인이 생기면 안 된다
legacy="$data/journals/_daily/2026-06-28.md"
mkdir -p "$(dirname "$legacy")"
printf '# 2026-06-28\n\n<!-- session:sess-9 -->\n- 09:00 · [demo](../demo/2026-06-28.md) — 옛 항목\n' > "$legacy"
echo "$SUMMARY" | bash "$ROOT/scripts/core/write-entry.sh" sess-9 2026-06-28 mac /tmp/wj-work/x 09:30
assert_eq "$(grep -c '^- ' "$legacy")" "1" "legacy marker upgraded in place, not duplicated"
assert_file_contains "$legacy" "session:sess-9:demo" "legacy marker now carries the project"

# private → private/<project>/, no daily index
echo "$SUMMARY" | bash "$ROOT/scripts/core/write-entry.sh" sess-2 2026-06-29 mac /tmp/other/y 11:00
ls "$data"/private/*/2026-06-29.md >/dev/null 2>&1 && pass "private entry written" || fail "private entry written"

# skip → nothing
echo "$SUMMARY" | bash "$ROOT/scripts/core/write-entry.sh" sess-3 2026-06-29 mac /tmp/wj-skip/z 12:00
[ ! -e "$data/journals/wj-skip" ] && pass "skip writes nothing" || fail "skip writes nothing"

# format guard: CLI error output leaking through stdout must not be recorded
echo "API Error: Connection closed mid-response. The response above may be incomplete." \
  | bash "$ROOT/scripts/core/write-entry.sh" sess-err1 2026-06-29 mac /tmp/wj-work/x 13:00
grep -q "API Error" "$data/journals/demo/2026-06-29.md" 2>/dev/null \
  && fail "error output filtered (API Error)" || pass "error output filtered (API Error)"

echo "You've hit your session limit · resets 8:30pm (Asia/Seoul)" \
  | bash "$ROOT/scripts/core/write-entry.sh" sess-err2 2026-06-29 mac /tmp/wj-work/x 13:01
grep -q "session limit" "$data/journals/demo/2026-06-29.md" 2>/dev/null \
  && fail "error output filtered (session limit)" || pass "error output filtered (session limit)"

# push 스로틀: 원격 연결 시 첫 sync는 push, 1시간 내 재push는 스킵(커밋은 계속)
bare="$(mktemp -d)/origin.git"; git init -q --bare "$bare"
( cd "$data" && git remote add origin "$bare" && git push -qu origin HEAD 2>/dev/null )
echo "$SUMMARY" | bash "$ROOT/scripts/core/write-entry.sh" sess-4 2026-06-29 mac /tmp/wj-work/x 13:00
c1=$(git -C "$bare" rev-list --count --all)
[ "$c1" -ge 2 ] && pass "remote synced on first window" || fail "remote synced on first window (got $c1)"
echo "$SUMMARY" | bash "$ROOT/scripts/core/write-entry.sh" sess-5 2026-06-29 mac /tmp/wj-work/x 13:05
c2=$(git -C "$bare" rev-list --count --all)
assert_eq "$c2" "$c1" "push throttled within the hour"
lc=$(git -C "$data" rev-list --count HEAD)
[ "$lc" -gt "$c2" ] && pass "local commits continue while throttled" || fail "local commits continue while throttled"

# ~ prefix regression: config rule with tilde prefix must match expanded absolute path
tilde_sub="wj-tilde-test-$$"
cat >"$WORK_JOURNAL_CONFIG" <<JSON2
{"journal_dir": "$data",
 "rules": [
   {"prefix": "~/$tilde_sub", "category": "work", "project": "tilde-demo"}],
 "default": "private"}
JSON2
tilde_result=$(python3 "$ROOT/scripts/core/classify-cwd.py" "$HOME/$tilde_sub/x")
case "$tilde_result" in *'"category": "work"'*|*'"category":"work"'*)
  pass "~ prefix in config rule matches expanded cwd" ;;
*)
  fail "~ prefix in config rule matches expanded cwd (got: $tilde_result)" ;;
esac

finish
