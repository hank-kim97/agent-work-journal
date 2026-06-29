#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
. "$HERE/helpers.sh"

# Back up real config.json so --journal-dir rewrite doesn't clobber it
if [ -f "$ROOT/config.json" ]; then
  cp "$ROOT/config.json" "$ROOT/config.json.bak"
  trap 'mv "$ROOT/config.json.bak" "$ROOT/config.json"' EXIT
else
  trap 'rm -f "$ROOT/config.json"' EXIT
fi

fakehome="$(mktemp -d)"
HOME="$fakehome" bash "$ROOT/install.sh" --agent both --journal-dir "$fakehome/data"

cc="$fakehome/.claude/settings.json"
assert_file_contains "$cc" "adapters/claude-code.sh" "claude Stop hook wired"
tom="$fakehome/.codex/config.toml"
assert_file_contains "$tom" "adapters/codex.sh" "codex notify wired"

# 멱등성: 두 번째 실행해도 중복 없음
HOME="$fakehome" bash "$ROOT/install.sh" --agent both --journal-dir "$fakehome/data"
cnt=$(grep -c "adapters/claude-code.sh" "$cc")
assert_eq "$cnt" "1" "claude hook not duplicated"
cntx=$(grep -c "adapters/codex.sh" "$tom")
assert_eq "$cntx" "1" "codex notify not duplicated"

finish
