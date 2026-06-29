#!/usr/bin/env bash
# Wrapper for build-wiki.py: rebuild project READMEs + INDEX, then commit & push.
# Designed to be cron-safe and idempotent.
#
# Usage:
#   bash scripts/core/build-wiki.sh             # incremental, all projects
#   bash scripts/core/build-wiki.sh --force     # force rebuild everything
#   bash scripts/core/build-wiki.sh --project skt
#
# Cron line example (daily 04:10 local):
#   10 4 * * * cd $HOME/work-journal && bash scripts/core/build-wiki.sh >> $HOME/.claude/wiki-build.log 2>&1

set -uo pipefail

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SELF_DIR/../lib/resolve-paths.sh"   # sets JOURNAL_DIR
cd "$JOURNAL_DIR" 2>/dev/null || { echo "missing $JOURNAL_DIR" >&2; exit 1; }

python3 "$SELF_DIR/build-wiki.py" "$@" || exit $?

# Commit & push if anything changed (journals/ + root README which embeds INDEX).
if [ -d "$JOURNAL_DIR/.git" ]; then
  git add journals/ README.md 2>/dev/null
  if ! git diff --cached --quiet 2>/dev/null; then
    DATE=$(date +%Y-%m-%d)
    TIME=$(date +%H:%M)
    git -c commit.gpgsign=false commit -m "wiki rebuild ${DATE} ${TIME}" 2>/dev/null
    git pull --rebase --autostash 2>/dev/null || true
    git push 2>/dev/null || true
  fi
fi
