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
