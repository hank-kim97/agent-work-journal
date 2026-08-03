#!/usr/bin/env bash
# Sourced helper. Exports TOOL_DIR, CONFIG_PATH, JOURNAL_DIR, KNOWLEDGE_REPO, AUTHOR.
# Resolution for JOURNAL_DIR: $WORK_JOURNAL_DIR > config.json journal_dir > TOOL_DIR.
# AUTHOR (who the team repo attributes entries to): config author > git user.name > $USER.

TOOL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# WORK_JOURNAL_CONFIG overrides the config path (tests point this at a temp
# file so they never touch the real config.json — see #config-safety).
CONFIG_PATH="${WORK_JOURNAL_CONFIG:-$TOOL_DIR/config.json}"

_expand_tilde() { case "$1" in "~"/*) printf '%s' "${HOME}/${1#\~/}";; "~") printf '%s' "$HOME";; *) printf '%s' "$1";; esac; }

if [ -n "${WORK_JOURNAL_DIR:-}" ]; then
  JOURNAL_DIR="$(_expand_tilde "$WORK_JOURNAL_DIR")"
elif [ -f "$CONFIG_PATH" ] && _jd=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1])).get('journal_dir',''))" "$CONFIG_PATH" 2>/dev/null) && [ -n "$_jd" ]; then
  JOURNAL_DIR="$(_expand_tilde "$_jd")"
else
  JOURNAL_DIR="$TOOL_DIR"
fi

_cfg_get() {  # _cfg_get <key> → value or empty
  [ -f "$CONFIG_PATH" ] || return 0
  python3 -c "import json,sys
try: print(json.load(open(sys.argv[1])).get(sys.argv[2],'') or '')
except Exception: pass" "$CONFIG_PATH" "$1" 2>/dev/null
}

_kr="$(_cfg_get knowledge_repo)"
KNOWLEDGE_REPO="${_kr:+$(_expand_tilde "$_kr")}"

AUTHOR="$(_cfg_get author)"
[ -z "$AUTHOR" ] && AUTHOR="$(git config user.name 2>/dev/null || true)"
[ -z "$AUTHOR" ] && AUTHOR="${USER:-unknown}"
# filesystem-safe (used as a directory name in the team repo)
AUTHOR="$(printf '%s' "$AUTHOR" | tr ' /' '__')"

export TOOL_DIR CONFIG_PATH JOURNAL_DIR KNOWLEDGE_REPO AUTHOR
