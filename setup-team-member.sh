#!/usr/bin/env bash
# One-command onboarding for a team member (audit item: 6 manual steps → 1).
# Wraps: config.json wiring → install.sh → personal data repo init →
#        team knowledge repo clone → install-knowledge.sh.
# Idempotent — safe to re-run (also the fix path after moving the tool dir,
# since hooks/skills are wired with absolute paths).
#
# Usage:
#   bash setup-team-member.sh --work-prefix <dir> \
#        [--journal-dir <dir>]          # default ~/work-journal-data
#        [--knowledge-remote <git-url>] # team repo to clone (member #2+)
#        [--knowledge-dir <dir>]        # default ~/re-team-work-log
#        [--agent claude|codex|both]    # default claude
set -euo pipefail

TOOL_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG="${WORK_JOURNAL_CONFIG:-$TOOL_DIR/config.json}"   # tests override this
WORK_PREFIX=""; JDIR="$HOME/work-journal-data"; KREMOTE=""; KDIR="$HOME/re-team-work-log"; AGENT="claude"
while [ $# -gt 0 ]; do
  case "$1" in
    --work-prefix)      WORK_PREFIX="$2"; shift 2 ;;
    --journal-dir)      JDIR="$2"; shift 2 ;;
    --knowledge-remote) KREMOTE="$2"; shift 2 ;;
    --knowledge-dir)    KDIR="$2"; shift 2 ;;
    --agent)            AGENT="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done
[ -z "$WORK_PREFIX" ] && { echo "usage: bash setup-team-member.sh --work-prefix <dir> [...]" >&2; exit 2; }
expand() { case "$1" in "~"/*) printf '%s' "$HOME/${1#\~/}";; "~") printf '%s' "$HOME";; *) printf '%s' "$1";; esac; }
JDIR="$(expand "$JDIR")"; KDIR="$(expand "$KDIR")"

echo "== 1/5 config.json =="
python3 - "$CONFIG" "$JDIR" "$WORK_PREFIX" <<'PY'
import json, os, sys
path, jdir, prefix = sys.argv[1], sys.argv[2], sys.argv[3]
d = json.load(open(path)) if os.path.exists(path) else {}
d.setdefault("rules", []); d.setdefault("default", "private")
d["journal_dir"] = d.get("journal_dir") or jdir
if not any(r.get("prefix") == prefix for r in d["rules"]):
    d["rules"].append({"prefix": prefix, "category": "work"})
json.dump(d, open(path, "w"), indent=2, ensure_ascii=False)
print(f"journal_dir={d['journal_dir']}, work rule: {prefix}")
PY

echo "== 2/5 훅 배선 (install.sh) =="
bash "$TOOL_DIR/install.sh" --agent "$AGENT"

echo "== 3/5 개인 데이터 레포 =="
JDIR_REAL="$(python3 -c "import json;print(json.load(open('$CONFIG'))['journal_dir'])")"
JDIR_REAL="$(expand "$JDIR_REAL")"
if [ ! -d "$JDIR_REAL/.git" ]; then
  mkdir -p "$JDIR_REAL"
  ( cd "$JDIR_REAL" && git init -q -b main )
  printf 'private/\n' > "$JDIR_REAL/.gitignore"
  ( cd "$JDIR_REAL" && git add -A && git -c commit.gpgsign=false commit -qm "chore: init work-journal data repo" )
  echo "initialized: $JDIR_REAL (원격은 개인 소유로 선택 연결 — 최초 1회 git push -u 필요)"
else
  echo "exists: $JDIR_REAL"
fi

if [ -n "$KREMOTE" ]; then
  echo "== 4/5 팀 지식 레포 clone =="
  if [ ! -d "$KDIR/.git" ]; then
    git clone "$KREMOTE" "$KDIR"
  else
    echo "exists: $KDIR"
  fi
  echo "== 5/5 지식 확장 설치 =="
  bash "$TOOL_DIR/install-knowledge.sh" --repo "$KDIR"
else
  echo "== 4-5/5 건너뜀 (—knowledge-remote 미지정: 일지 코어만 설치) =="
fi

cat <<EOF

==> 온보딩 완료.
    ⚠ 도구 디렉토리($TOOL_DIR)를 이동하면 훅·스킬의 절대경로가 끊깁니다 — 이 스크립트를 재실행하세요.
EOF
