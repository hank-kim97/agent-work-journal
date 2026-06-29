#!/usr/bin/env bash
# Minimal assertion + mock helpers for the work-journal test suite.
set -uo pipefail

FAIL_LOG="$(mktemp)"
export FAIL_LOG

pass() { printf '  ok   - %s\n' "$1"; }
fail() { printf '  FAIL - %s\n' "$1"; printf '%s\n' "$1" >>"$FAIL_LOG"; }

assert_eq() {
  if [ "$1" = "$2" ]; then pass "$3"; else fail "$3 (got '$1', want '$2')"; fi
}
assert_contains() {
  case "$1" in *"$2"*) pass "$3";; *) fail "$3 (missing '$2')";; esac
}
assert_file_contains() {
  if [ -f "$1" ] && grep -qF "$2" "$1"; then pass "$3"
  else fail "$3 (file '$1' missing '$2')"; fi
}

# mock_summarizer "canned text" → prints path to an executable that ignores
# stdin/args and echoes the canned text. Used via SUMMARIZER_CMD.
mock_summarizer() {
  local dir; dir="$(mktemp -d)"
  local exe="$dir/mock-sum"
  printf '%s\n' '#!/usr/bin/env bash' >"$exe"
  printf '%s\n' 'cat >/dev/null 2>&1' >>"$exe"
  printf '%s\n' "cat <<'__EOT__'" >>"$exe"
  printf '%s\n' "$1" >>"$exe"
  printf '%s\n' '__EOT__' >>"$exe"
  chmod +x "$exe"
  printf '%s' "$exe"
}

finish() {
  local n
  n=$(( $(wc -l < "$FAIL_LOG") ))
  rm -f "$FAIL_LOG"
  if [ "$n" -gt 0 ]; then printf 'FAILED (%d)\n' "$n"; exit 1; fi
  printf 'OK\n'
}
