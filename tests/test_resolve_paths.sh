#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
. "$HERE/helpers.sh"

# 1) WORK_JOURNAL_DIR env wins, ~ expands
( export WORK_JOURNAL_DIR="~/somewhere"
  . "$ROOT/scripts/lib/resolve-paths.sh"
  assert_eq "$JOURNAL_DIR" "$HOME/somewhere" "env WORK_JOURNAL_DIR with ~ expansion" )

# 2) falls back to config.json journal_dir
tmp="$(mktemp -d)"
mkdir -p "$tmp/scripts/lib"
cp "$ROOT/scripts/lib/resolve-paths.sh" "$tmp/scripts/lib/"
printf '{"journal_dir": "%s/data", "rules": [], "default": "private"}\n' "$tmp" >"$tmp/config.json"
( unset WORK_JOURNAL_DIR
  . "$tmp/scripts/lib/resolve-paths.sh"
  assert_eq "$JOURNAL_DIR" "$tmp/data" "config journal_dir fallback"
  assert_eq "$CONFIG_PATH" "$tmp/config.json" "CONFIG_PATH points at tool root" )

# 3) no env, no config → TOOL_DIR
tmp2="$(mktemp -d)"
mkdir -p "$tmp2/scripts/lib"
cp "$ROOT/scripts/lib/resolve-paths.sh" "$tmp2/scripts/lib/"
( unset WORK_JOURNAL_DIR
  . "$tmp2/scripts/lib/resolve-paths.sh"
  assert_eq "$JOURNAL_DIR" "$tmp2" "no config → TOOL_DIR" )

finish
