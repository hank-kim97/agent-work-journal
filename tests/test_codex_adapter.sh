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

# --- Test 1: agent-turn-complete writes a journal entry from rollout cwd -----
data="$(mktemp -d)"
( cd "$data" && git init -q && git config user.email t@t && git config user.name t )

cat >"$ROOT/config.json" <<JSON
{"journal_dir": "$data", "rules": [{"prefix": "/tmp/wj-work", "category": "work", "project": "demo"}], "default": "private"}
JSON

# Fake CODEX_HOME with rollout fixture
ch="$(mktemp -d)"
sd="$ch/sessions/2026/06/29"
mkdir -p "$sd"
cp "$HERE/fixtures/rollout-sample.jsonl" "$sd/rollout-2026-06-29T10-00-00-codex-sess-1.jsonl"

sum="$(mock_summarizer $'### codex 요약\n\n**Done**\n- 처리됨')"
notify='{"type":"agent-turn-complete","turn-id":"t1","last-assistant-message":"완료"}'

CODEX_HOME="$ch" SUMMARIZER_CMD="bash $sum" bash "$ROOT/scripts/adapters/codex.sh" "$notify"

# Poll with bounded deadline for the journal file to appear
_deadline=$(( $(date +%s) + 5 ))
while [ "$(date +%s)" -lt "$_deadline" ]; do
  ls "$data"/journals/demo/*.md >/dev/null 2>&1 && break
  sleep 0.2
done

# Assert content (not just file existence)
WRITTEN_FILE="$(ls "$data"/journals/demo/*.md 2>/dev/null | head -1)"
if [ -n "$WRITTEN_FILE" ]; then
  assert_file_contains "$WRITTEN_FILE" "codex 요약" "codex adapter wrote journal from rollout cwd"
else
  fail "codex adapter wrote journal from rollout cwd (no file found)"
fi

# --- Test 2: non-turn-complete type → nothing written -----------------------
data2="$(mktemp -d)"
cat >"$ROOT/config.json" <<JSON
{"journal_dir": "$data2", "rules": [{"prefix": "/tmp/wj-work", "category": "work", "project": "demo"}], "default": "private"}
JSON

CODEX_HOME="$ch" SUMMARIZER_CMD="bash $sum" bash "$ROOT/scripts/adapters/codex.sh" '{"type":"other"}'

# Poll briefly then assert nothing was written
_deadline2=$(( $(date +%s) + 2 ))
while [ "$(date +%s)" -lt "$_deadline2" ]; do
  [ -d "$data2/journals" ] && break
  sleep 0.2
done
[ ! -d "$data2/journals" ] && pass "non-turn-complete ignored" || fail "non-turn-complete ignored"

finish
