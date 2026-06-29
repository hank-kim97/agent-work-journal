#!/usr/bin/env bash
# Sourced helper. Exports TOOL_DIR, CONFIG_PATH, JOURNAL_DIR.
# Resolution for JOURNAL_DIR: $WORK_JOURNAL_DIR > config.json journal_dir > TOOL_DIR.

TOOL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONFIG_PATH="$TOOL_DIR/config.json"

_expand_tilde() { case "$1" in "~"/*) printf '%s' "${HOME}/${1#\~/}";; "~") printf '%s' "$HOME";; *) printf '%s' "$1";; esac; }

if [ -n "${WORK_JOURNAL_DIR:-}" ]; then
  JOURNAL_DIR="$(_expand_tilde "$WORK_JOURNAL_DIR")"
elif [ -f "$CONFIG_PATH" ] && _jd=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1])).get('journal_dir',''))" "$CONFIG_PATH" 2>/dev/null) && [ -n "$_jd" ]; then
  JOURNAL_DIR="$(_expand_tilde "$_jd")"
else
  JOURNAL_DIR="$TOOL_DIR"
fi

export TOOL_DIR CONFIG_PATH JOURNAL_DIR
