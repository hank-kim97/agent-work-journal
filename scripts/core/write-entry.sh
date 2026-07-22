#!/usr/bin/env bash
# Shared core: classify cwd → route → write section → (work) daily index + push.
# Reads summary body from stdin.
# Usage: write-entry.sh <session_id> <date> <machine> <cwd> <time>
set -uo pipefail

SESSION_ID="${1:?session_id}"; DATE="${2:?date}"; MACHINE="${3:?machine}"
CWD="${4:?cwd}"; TIME="${5:?time}"

CORE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$CORE_DIR/../lib/resolve-paths.sh"

SUMMARY="$(cat)"
[ -z "$SUMMARY" ] && exit 0
if printf '%s' "$SUMMARY" | head -1 | grep -q "의미 있는 작업 없음"; then exit 0; fi
# Format guard: a valid summary starts with a "### title" line. Anything else
# is CLI error output leaking through stdout (session limit, "API Error:
# Connection closed", rate limit notices, ...) — never record those.
if ! printf '%s' "$SUMMARY" | sed -n '/[^[:space:]]/{p;q;}' | grep -q '^[[:space:]]*###'; then
  exit 0
fi

CLASSIFY=$(python3 "$CORE_DIR/classify-cwd.py" "$CWD" 2>/dev/null || echo '{"category":"private","project":"misc"}')
CATEGORY=$(printf '%s' "$CLASSIFY" | python3 -c "import json,sys;print(json.load(sys.stdin).get('category','private'))")
PROJECT=$(printf '%s' "$CLASSIFY" | python3 -c "import json,sys;print(json.load(sys.stdin).get('project','misc'))")
[ -z "$PROJECT" ] && PROJECT=misc

DAILY_INDEX=""
case "$CATEGORY" in
  skip) exit 0 ;;
  work)
    DAILY_DIR="$JOURNAL_DIR/journals/$PROJECT"
    DAILY_INDEX="$JOURNAL_DIR/journals/_daily/${DATE}.md" ;;
  private|*)
    DAILY_DIR="$JOURNAL_DIR/private/$PROJECT"; CATEGORY=private ;;
esac
DAILY_FILE="$DAILY_DIR/${DATE}.md"
mkdir -p "$DAILY_DIR"

printf '%s' "$SUMMARY" | python3 "$CORE_DIR/update-section.py" \
  "$DAILY_FILE" "$SESSION_ID" "$DATE" "$MACHINE" "$CWD" "$TIME" "$PROJECT"

if [ -n "$DAILY_INDEX" ]; then
  mkdir -p "$(dirname "$DAILY_INDEX")"
  TITLE_LINE=$(printf '%s' "$SUMMARY" | head -1 | sed 's/^#* *//')
  python3 "$CORE_DIR/update-daily-index.py" \
    "$DAILY_INDEX" "$PROJECT" "$SESSION_ID" "$DATE" "$TIME" "$TITLE_LINE"
fi

if [ "$CATEGORY" = "work" ] && [ -d "$JOURNAL_DIR/.git" ]; then
  ( cd "$JOURNAL_DIR" || exit 0
    git add journals/ 2>/dev/null
    if ! git diff --cached --quiet 2>/dev/null; then
      TITLE_LINE=$(printf '%s' "$SUMMARY" | head -1 | sed 's/^#* *//')
      git -c commit.gpgsign=false commit -m "${DATE} ${TIME} ${MACHINE} [${PROJECT}]: ${TITLE_LINE}" 2>/dev/null
      # Commit every turn (local, cheap — keeps per-session history), but
      # network sync only when a remote exists and at most once per hour.
      # Per-turn pull/push round-trips were pure overhead (audit finding);
      # first push needs upstream set once: `git push -u origin <branch>`.
      if git remote get-url origin >/dev/null 2>&1; then
        SYNC_MARK=".git/.journal-last-sync"
        if [ ! -f "$SYNC_MARK" ] || [ -n "$(find "$SYNC_MARK" -mmin +60 2>/dev/null)" ]; then
          git pull --rebase --autostash 2>/dev/null || true
          git push 2>/dev/null || true
          touch "$SYNC_MARK"
        fi
      fi
    fi )
fi
exit 0
