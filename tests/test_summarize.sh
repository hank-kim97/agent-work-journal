#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
. "$HERE/helpers.sh"

tx="$(mktemp)"; printf '{"role":"user"}\n{"role":"assistant"}\n' >"$tx"

# SUMMARIZER_CMD override: prompt이 stdin으로 들어오고 우리가 준 텍스트가 그대로 나옴
mock="$(mktemp -d)/sum"
cat >"$mock" <<'EOF'
#!/usr/bin/env bash
prompt="$(cat)"
case "$prompt" in *"작업 디렉토리"*) echo "### mock 요약";; *) echo "BADPROMPT";; esac
EOF
chmod +x "$mock"

out=$( SUMMARIZER_CMD="bash $mock" bash "$ROOT/scripts/lib/summarize.sh" "$tx" /tmp/x mac 2026-06-29 10:00 )
assert_eq "$out" "### mock 요약" "SUMMARIZER_CMD override used, prompt well-formed"

finish
