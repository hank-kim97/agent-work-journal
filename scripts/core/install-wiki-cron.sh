#!/usr/bin/env bash
# Install/refresh the crontab entry that rebuilds the project wiki daily.
# Idempotent — safe to re-run.

set -euo pipefail

JOURNAL_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
LOG_FILE="$HOME/.claude/wiki-build.log"
TAG="# claude-work-journal:build-wiki"
CRON_LINE="10 4 * * * cd \"$JOURNAL_DIR\" && bash scripts/core/build-wiki.sh >> \"$LOG_FILE\" 2>&1 $TAG"

# Remove any existing tagged line, then append the new one.
existing=$(crontab -l 2>/dev/null || true)
filtered=$(printf '%s\n' "$existing" | grep -v "$TAG" || true)
{
  printf '%s\n' "$filtered"
  printf '%s\n' "$CRON_LINE"
} | sed '/^$/d' | crontab -

echo "installed cron: $CRON_LINE"
echo "log: $LOG_FILE"
echo "to remove: crontab -l | grep -v '$TAG' | crontab -"
