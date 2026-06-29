#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
. "$HERE/helpers.sh"

# --- Back up existing config.json (real personal config lives here) ----------
if [ -f "$ROOT/config.json" ]; then
  cp "$ROOT/config.json" "$ROOT/config.json.bak"
  trap 'mv "$ROOT/config.json.bak" "$ROOT/config.json"' EXIT
else
  trap 'rm -f "$ROOT/config.json"' EXIT
fi

# --- Test 1: normal session writes a journal entry ---------------------------
data="$(mktemp -d)"
( cd "$data" && git init -q && git config user.email t@t && git config user.name t )
tx="$(mktemp)"
printf '{"role":"user"}\n{"role":"user"}\n{"role":"assistant"}\n' >"$tx"

cat >"$ROOT/config.json" <<JSON
{"journal_dir": "$data", "rules": [{"prefix": "/tmp/wj-work", "category": "work", "project": "demo"}], "default": "private"}
JSON

MOCK_TITLE="어댑터 요약"
sum="$(mock_summarizer $"### ${MOCK_TITLE}\n\n**Done**\n- 처리됨")"
input=$(printf '{"transcript_path":"%s","session_id":"cc-1","cwd":"/tmp/wj-work/p"}' "$tx")

# env var set only on the adapter invocation (pipe right-hand side)
printf '%s' "$input" | SUMMARIZER_CMD="bash $sum" bash "$ROOT/scripts/adapters/claude-code.sh"

# Background detach → poll with timeout
for _ in 1 2 3 4 5 6 7 8 9 10; do
  ls "$data"/journals/demo/*.md >/dev/null 2>&1 && break
  sleep 0.3
done
ls "$data"/journals/demo/*.md >/dev/null 2>&1 && pass "claude adapter wrote journal" || fail "claude adapter wrote journal"

# Assert mock summary content landed in the written journal file
WRITTEN_FILE="$(ls "$data"/journals/demo/*.md 2>/dev/null | head -1)"
if [ -n "$WRITTEN_FILE" ]; then
  assert_file_contains "$WRITTEN_FILE" "$MOCK_TITLE" "summary content written to journal"
else
  fail "summary content written to journal (no file found)"
fi

# --- Test 2: trivial session (1 user turn) → nothing written -----------------
tx2="$(mktemp)"
printf '{"role":"user"}\n' >"$tx2"
data2="$(mktemp -d)"
cat >"$ROOT/config.json" <<JSON
{"journal_dir": "$data2", "rules": [{"prefix": "/tmp/wj-work", "category": "work", "project": "demo"}], "default": "private"}
JSON

printf '{"transcript_path":"%s","session_id":"cc-2","cwd":"/tmp/wj-work/p"}' "$tx2" \
  | SUMMARIZER_CMD="bash $sum" bash "$ROOT/scripts/adapters/claude-code.sh"

# Poll up to ~3s then assert absence (guards against false pass on slow machine)
_deadline=$(( $(date +%s) + 3 ))
while [ "$(date +%s)" -lt "$_deadline" ]; do
  [ -d "$data2/journals" ] && break
  sleep 0.2
done
[ ! -d "$data2/journals" ] && pass "trivial session skipped" || fail "trivial session skipped"

# --- Test 3: zero user-turn session → nothing written (regression for USER_TURNS double-output bug) ---
tx3="$(mktemp)"
printf '{"role":"assistant"}\n' >"$tx3"
data3="$(mktemp -d)"
cat >"$ROOT/config.json" <<JSON
{"journal_dir": "$data3", "rules": [{"prefix": "/tmp/wj-work", "category": "work", "project": "demo"}], "default": "private"}
JSON

printf '{"transcript_path":"%s","session_id":"cc-3","cwd":"/tmp/wj-work/p"}' "$tx3" \
  | SUMMARIZER_CMD="bash $sum" bash "$ROOT/scripts/adapters/claude-code.sh"

# Poll up to ~3s then assert absence
_deadline=$(( $(date +%s) + 3 ))
while [ "$(date +%s)" -lt "$_deadline" ]; do
  [ -d "$data3/journals" ] && break
  sleep 0.2
done
[ ! -d "$data3/journals" ] && pass "zero-turn session skipped" || fail "zero-turn session skipped"

finish
