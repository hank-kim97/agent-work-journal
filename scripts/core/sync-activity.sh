#!/usr/bin/env bash
# Mirror this member's work journals into the team repo's activity/ surface.
#
#   <journal_dir>/journals/<project>/<date>.md  →  activity/<author>/<project>/<date>.md
#   <journal_dir>/journals/_daily/<date>.md     →  activity/<author>/_daily/<date>.md
#
# Answers "what did X do today / how far along is X" (requirements 1,2,4) with
# no LLM in the loop — it is a file copy plus git.
#
# SAFETY: only journals/ is ever read. private/ must never reach the team repo.
# Throttle: commits every run (cheap, local) but pushes at most once an hour,
# same rationale as write-entry.sh — per-turn pushes would spam the team repo.
#
# Usage: sync-activity.sh            (called from write-entry.sh for work entries)
#        sync-activity.sh --all      (backfill every existing work journal)
set -uo pipefail

CORE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$CORE_DIR/../lib/resolve-paths.sh"

[ -z "$KNOWLEDGE_REPO" ] && exit 0                 # opt-in: team repo not configured
[ -d "$KNOWLEDGE_REPO/.git" ] || exit 0
JOURNALS="$JOURNAL_DIR/journals"
[ -d "$JOURNALS" ] || exit 0

DEST="$KNOWLEDGE_REPO/activity/$AUTHOR"
mkdir -p "$DEST"

copy_one() {  # copy_one <journal file> — mirrors preserving <project>/<date>.md
  local src="$1" rel
  rel="${src#"$JOURNALS"/}"
  case "$rel" in
    ../*|/*) return 0 ;;                            # never escape journals/
  esac
  mkdir -p "$DEST/$(dirname "$rel")"
  cp "$src" "$DEST/$rel"
}

if [ "${1:-}" = "--all" ]; then
  while IFS= read -r f; do copy_one "$f"; done < <(
    find "$JOURNALS" -type f -name '[0-9]*-*.md'
  )
else
  # incremental: only journals touched in the last hour (write-entry just wrote one)
  while IFS= read -r f; do copy_one "$f"; done < <(
    find "$JOURNALS" -type f -name '[0-9]*-*.md' -mmin -60
  )
fi

python3 "$CORE_DIR/build-activity-index.py" "$KNOWLEDGE_REPO" 2>/dev/null

cd "$KNOWLEDGE_REPO" || exit 0
git add activity/ 2>/dev/null
git diff --cached --quiet 2>/dev/null && exit 0     # nothing changed

DATE=$(date +%Y-%m-%d); TIME=$(date +%H:%M)
git -c commit.gpgsign=false commit -qm "activity: $AUTHOR $DATE $TIME" 2>/dev/null

if git remote get-url origin >/dev/null 2>&1; then
  SYNC_MARK=".git/.activity-last-push"
  if [ ! -f "$SYNC_MARK" ] || [ -n "$(find "$SYNC_MARK" -mmin +60 2>/dev/null)" ]; then
    git pull --rebase --autostash >/dev/null 2>&1 || true
    git push >/dev/null 2>&1 \
      || echo "[sync-activity] ERROR: push failed — committed locally, will retry"
    touch "$SYNC_MARK"
  fi
fi
exit 0
