#!/usr/bin/env bash
# Codex notify adapter. Wired via ~/.codex/config.toml:
#   notify = ["bash", "<tool>/scripts/adapters/codex.sh"]
# Codex calls this with the notify JSON as argv[1].
set -uo pipefail

if [ -n "${CODEX_JOURNAL_RUNNING:-}" ]; then exit 0; fi
NOTIFY="${1:-}"
[ -z "$NOTIFY" ] && exit 0

ADAPTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$HOME/.claude/journal-hook.log"
mkdir -p "$HOME/.claude"

TYPE=$(printf '%s' "$NOTIFY" | python3 -c "import json,sys
try: print(json.load(sys.stdin).get('type',''))
except Exception: pass" 2>/dev/null)
[ "$TYPE" = "agent-turn-complete" ] || exit 0

(
  export CODEX_JOURNAL_RUNNING=1
  CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"

  ROLLOUT=$(ls -t "$CODEX_HOME"/sessions/*/*/*/rollout-*.jsonl 2>/dev/null | head -1)
  [ -z "$ROLLOUT" ] || [ ! -f "$ROLLOUT" ] && exit 0

  META=$(head -1 "$ROLLOUT")
  CWD=$(printf '%s' "$META" | python3 -c "import json,sys
d=json.load(sys.stdin); p=d.get('payload',d)
print(p.get('cwd') or d.get('cwd') or '')" 2>/dev/null)
  SESSION_ID=$(printf '%s' "$META" | python3 -c "import json,sys
d=json.load(sys.stdin); p=d.get('payload',d)
print(p.get('id') or d.get('id') or '')" 2>/dev/null)
  [ -z "$SESSION_ID" ] && SESSION_ID=$(basename "$ROLLOUT" .jsonl)
  [ -z "$CWD" ] && CWD="$PWD"

  MACHINE=$(scutil --get LocalHostName 2>/dev/null || hostname -s)
  DATE=$(date +%Y-%m-%d); TIME=$(date +%H:%M)

  SUMMARY=$(bash "$ADAPTER_DIR/../lib/summarize.sh" "$ROLLOUT" "$CWD" "$MACHINE" "$DATE" "$TIME" codex)
  if [ -z "$SUMMARY" ] || echo "$SUMMARY" | head -1 | grep -q "의미 있는 작업 없음"; then exit 0; fi

  printf '%s' "$SUMMARY" | bash "$ADAPTER_DIR/../core/write-entry.sh" \
    "$SESSION_ID" "$DATE" "$MACHINE" "$CWD" "$TIME"
) </dev/null >>"$LOG_FILE" 2>&1 &
disown
exit 0
