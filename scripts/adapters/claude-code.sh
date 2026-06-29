#!/usr/bin/env bash
# Claude Code Stop hook adapter.
# Reads JSON from stdin: { session_id, transcript_path, cwd, ... }
set -uo pipefail

if [ -n "${CLAUDE_JOURNAL_RUNNING:-}" ]; then exit 0; fi
INPUT=$(cat)

ADAPTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$HOME/.claude/journal-hook.log"
mkdir -p "$HOME/.claude"

(
  export CLAUDE_JOURNAL_RUNNING=1

  read_field() { printf '%s' "$INPUT" | python3 -c "import json,sys
try: print(json.load(sys.stdin).get('$1',''))
except Exception: pass" 2>/dev/null; }

  TRANSCRIPT_PATH=$(read_field transcript_path)
  SESSION_ID=$(read_field session_id)
  CWD=$(read_field cwd)
  [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ] && exit 0
  [ -z "$SESSION_ID" ] && exit 0

  USER_TURNS=$(grep -c '"role":"user"' "$TRANSCRIPT_PATH" 2>/dev/null) || USER_TURNS=0
  [ "${USER_TURNS:-0}" -lt 2 ] && exit 0

  MACHINE=$(scutil --get LocalHostName 2>/dev/null || hostname -s)
  DATE=$(date +%Y-%m-%d); TIME=$(date +%H:%M)

  SUMMARY=$(bash "$ADAPTER_DIR/../lib/summarize.sh" "$TRANSCRIPT_PATH" "$CWD" "$MACHINE" "$DATE" "$TIME" claude)
  if [ -z "$SUMMARY" ] || echo "$SUMMARY" | head -1 | grep -q "의미 있는 작업 없음" \
     || { [ "${#SUMMARY}" -lt 400 ] && echo "$SUMMARY" | head -1 | grep -qi "prompt is too long"; }; then
    exit 0
  fi

  printf '%s' "$SUMMARY" | bash "$ADAPTER_DIR/../core/write-entry.sh" \
    "$SESSION_ID" "$DATE" "$MACHINE" "$CWD" "$TIME"
) </dev/null >>"$LOG_FILE" 2>&1 &
disown
exit 0
