#!/usr/bin/env bash
# Installer: wire the work-journal adapters into Claude Code and/or Codex.
# Usage: bash install.sh [--agent claude|codex|both] [--journal-dir <path>]
set -euo pipefail

TOOL_DIR="$(cd "$(dirname "$0")" && pwd)"
AGENT=""; JDIR=""
while [ $# -gt 0 ]; do
  case "$1" in
    --agent) AGENT="$2"; shift 2 ;;
    --journal-dir) JDIR="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [ -z "$AGENT" ]; then
  echo "연결할 에이전트? [1] Claude Code  [2] Codex  [3] 둘 다"
  read -r a
  case "$a" in 1) AGENT=claude;; 2) AGENT=codex;; *) AGENT=both;; esac
fi

# config.json 보장
if [ ! -f "$TOOL_DIR/config.json" ]; then
  cp "$TOOL_DIR/config.example.json" "$TOOL_DIR/config.json"
  echo "config.json 생성됨 — 디렉토리 매핑을 편집하세요: $TOOL_DIR/config.json"
fi
if [ -n "$JDIR" ]; then
  python3 - "$TOOL_DIR/config.json" "$JDIR" <<'PY'
import json,sys
p,jd=sys.argv[1],sys.argv[2]
d=json.load(open(p)); d["journal_dir"]=jd
json.dump(d,open(p,"w"),indent=2,ensure_ascii=False)
PY
fi

wire_claude() {
  local settings="$HOME/.claude/settings.json"
  local cmd="bash $TOOL_DIR/scripts/adapters/claude-code.sh"
  mkdir -p "$HOME/.claude"
  python3 - "$settings" "$cmd" <<'PY'
import json,os,sys
sp,cmd=sys.argv[1],sys.argv[2]
d=json.load(open(sp)) if os.path.exists(sp) else {}
stop=d.setdefault("hooks",{}).setdefault("Stop",[])
if not any(any(h.get("command")==cmd for h in e.get("hooks",[])) for e in stop):
    stop.append({"matcher":"","hooks":[{"type":"command","command":cmd}]})
    json.dump(d,open(sp,"w"),indent=2,ensure_ascii=False); print("claude hook added")
else: print("claude hook already present")
PY
}

wire_codex() {
  local toml="$HOME/.codex/config.toml"
  local line="notify = [\"bash\", \"$TOOL_DIR/scripts/adapters/codex.sh\"]"
  mkdir -p "$HOME/.codex"; touch "$toml"
  if grep -qF "adapters/codex.sh" "$toml"; then
    echo "codex notify already present"
  else
    # 기존 notify 라인 제거 후 우리 것 추가
    grep -v '^notify *=' "$toml" > "$toml.tmp" 2>/dev/null || true
    mv "$toml.tmp" "$toml"
    printf '%s\n' "$line" >> "$toml"
    echo "codex notify added"
  fi
}

case "$AGENT" in
  claude) wire_claude ;;
  codex)  wire_codex ;;
  both)   wire_claude; wire_codex ;;
  *) echo "invalid --agent: $AGENT" >&2; exit 2 ;;
esac

echo "==> 완료. 다음 세션부터 일지가 기록됩니다."
echo "    로그: ~/.claude/journal-hook.log"
