#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
. "$HERE/helpers.sh"

# data dir 준비 + config로 work/private/skip 분기 검증
data="$(mktemp -d)"
( cd "$data" && git init -q && git config user.email t@t && git config user.name t )

# Back up existing config.json if present
if [ -f "$ROOT/config.json" ]; then
  cp "$ROOT/config.json" "$ROOT/config.json.bak"
  trap 'mv "$ROOT/config.json.bak" "$ROOT/config.json"' EXIT
else
  trap 'rm -f "$ROOT/config.json"' EXIT
fi

cat >"$ROOT/config.json" <<JSON
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
cat >"$ROOT/config.json" <<JSON2
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
