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
#        [--team "<이름>"]              # record name, e.g. "Data팀 업무 기록"
#        [--no-schedule]                # skip the weekly card-extraction job
# WORK_JOURNAL_SKIP_LAUNCHCTL=1 writes the plist but does not load it (tests).
set -euo pipefail

TOOL_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG="${WORK_JOURNAL_CONFIG:-$TOOL_DIR/config.json}"   # tests override this
WORK_PREFIX=""; JDIR="$HOME/work-journal-data"; KREMOTE=""; KDIR="$HOME/re-team-work-log"; AGENT="claude"
SCHEDULE="launchd"; TEAM=""
while [ $# -gt 0 ]; do
  case "$1" in
    --work-prefix)      WORK_PREFIX="$2"; shift 2 ;;
    --journal-dir)      JDIR="$2"; shift 2 ;;
    --knowledge-remote) KREMOTE="$2"; shift 2 ;;
    --knowledge-dir)    KDIR="$2"; shift 2 ;;
    --agent)            AGENT="$2"; shift 2 ;;
    --team)             TEAM="$2"; shift 2 ;;
    --no-schedule)      SCHEDULE="none"; shift ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done
[ -z "$WORK_PREFIX" ] && { echo "usage: bash setup-team-member.sh --work-prefix <dir> [...]" >&2; exit 2; }
expand() { case "$1" in "~"/*) printf '%s' "$HOME/${1#\~/}";; "~") printf '%s' "$HOME";; *) printf '%s' "$1";; esac; }
JDIR="$(expand "$JDIR")"; KDIR="$(expand "$KDIR")"

echo "== 1/6 config.json =="
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

echo "== 2/6 훅 배선 (install.sh) =="
bash "$TOOL_DIR/install.sh" --agent "$AGENT"

echo "== 3/6 개인 데이터 레포 =="
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
  echo "== 4/6 팀 지식 레포 clone =="
  if [ ! -d "$KDIR/.git" ]; then
    git clone "$KREMOTE" "$KDIR"
  else
    echo "exists: $KDIR"
  fi
  echo "== 5/6 지식 확장 설치 =="
  bash "$TOOL_DIR/install-knowledge.sh" --repo "$KDIR" ${TEAM:+--team "$TEAM"}

  echo "== 6/6 주간 카드 추출 스케줄 =="
  if [ "$SCHEDULE" = "none" ]; then
    echo "skipped (--no-schedule). 안 걸면 활동만 쌓이고 카드는 생기지 않습니다."
    echo "  수동 실행: bash $TOOL_DIR/scripts/core/extract-knowledge.sh"
  elif [ "$(uname -s)" != "Darwin" ]; then
    echo "macOS가 아니라 launchd를 쓸 수 없습니다. cron에 주 1회 등록하세요:"
    echo "  0 10 * * 1  bash $TOOL_DIR/scripts/core/extract-knowledge.sh >> \$HOME/.claude/knowledge-extract.log 2>&1"
  else
    # Stagger members across Mon–Fri by hashing the username. Two people
    # extracting in the same week can card the same problem under different
    # slugs; spreading the days makes one see the other's card first.
    WEEKDAY=$(( $(printf '%s' "$USER" | cksum | cut -d' ' -f1) % 5 + 1 ))
    LABEL="com.$USER.work-journal-extract"
    PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
    mkdir -p "$HOME/Library/LaunchAgents" "$HOME/.claude"
    cat > "$PLIST" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$TOOL_DIR/scripts/core/extract-knowledge.sh</string>
    </array>
    <key>WorkingDirectory</key><string>$HOME</string>
    <key>EnvironmentVariables</key>
    <dict>
        <!-- launchd starts with a bare PATH; the agent CLI is usually in ~/.local/bin -->
        <key>PATH</key><string>$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
        <key>HOME</key><string>$HOME</string>
        <key>GIT_TERMINAL_PROMPT</key><string>0</string>
    </dict>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Weekday</key><integer>$WEEKDAY</integer>
        <key>Hour</key><integer>10</integer>
        <key>Minute</key><integer>20</integer>
    </dict>
    <key>RunAtLoad</key><false/>
    <key>StandardOutPath</key><string>$HOME/.claude/knowledge-extract.log</string>
    <key>StandardErrorPath</key><string>$HOME/.claude/knowledge-extract.log</string>
</dict>
</plist>
PLIST_EOF
    DAY=$(echo '월 화 수 목 금' | cut -d' ' -f"$WEEKDAY")
    if [ -n "${WORK_JOURNAL_SKIP_LAUNCHCTL:-}" ]; then
      echo "plist written (launchctl 등록 생략): $PLIST"
    else
      launchctl bootout "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || true   # 재실행 멱등
      if launchctl bootstrap "gui/$(id -u)" "$PLIST" >/dev/null 2>&1; then
        echo "registered: $LABEL — 매주 ${DAY}요일 10:20"
        echo "  해제하려면: launchctl bootout gui/\$(id -u)/$LABEL && rm $PLIST"
      else
        echo "ERROR: launchctl 등록 실패 — 수동 등록 필요: launchctl bootstrap gui/\$(id -u) $PLIST"
      fi
    fi
  fi
else
  echo "== 4-6/6 건너뜀 (—knowledge-remote 미지정: 일지 코어만 설치) =="
fi

cat <<EOF

==> 온보딩 완료.
    ⚠ 도구 디렉토리($TOOL_DIR)를 이동하면 훅·스킬의 절대경로가 끊깁니다 — 이 스크립트를 재실행하세요.
EOF
