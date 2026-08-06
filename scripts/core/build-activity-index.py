#!/usr/bin/env python3
"""Regenerate activity/<person>/INDEX.md — a row per (date, project, session).

Why this file exists: **a directory name is the cwd repo, not the client.** On a
real month, SKT work lived in `zez-server` (11 sessions) and `agent-runtime` (4)
as much as in `skt-*` (17) — so filtering activity by directory silently drops
half the material and the gap is invisible in the result. Measured on a report
dry-run: the directory filter found 17 of 35 relevant files.

The fix is not a smarter filter, it is making *complete enumeration cheap*. One
grep on a date prefix lists every session in the period with its title, so the
reader picks targets from titles instead of guessing from folder names, and
opens only the files that matter:

    grep '| 2026-07-' activity/*/INDEX.md

Why one index per person rather than one for the team: the file is rewritten
whole on every sync, so a single shared index would put every member's writes on
the same lines and make the team repo conflict constantly. Sharding by author
means each member only ever touches their own file, and a rebase never has two
versions to reconcile. The reader pays nothing — the glob above is one grep.

For that guarantee to hold this must write ONLY the calling member's shard; it
must never regenerate a shard from a possibly stale local copy of someone else's
files.

Deterministic and fully regenerated each run.
Usage: build-activity-index.py <repo> <author>
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

SESSION_RE = re.compile(r"<!-- session:([0-9a-zA-Z-]+) -->\n([^\n]*)\n([^\n]*)")
TIME_RE = re.compile(r"\b(\d{2}:\d{2})\b")
DATE_NAME = re.compile(r"^\d{4}-\d{2}-\d{2}$")
CWD_RE = re.compile(r"<sub>cwd: `([^`]+)`</sub>")
BROKEN = "(제목 없음 — 기록 손상)"


def workspace_of(cwd: str, project: str) -> str:
    """The directory containing the project checkout, e.g. skt-agent-proj.

    This is the closest thing to a client axis the data already carries, and it
    beats both the folder name and the title: on a real month `skt-agent-proj`
    held zez-server, doc-console, agent-runtime, secure_ui and brain-parser —
    exactly the sessions a `skt-*` filter dropped. A hint, not an authority:
    when the cwd sits below the repo root the guess degrades to the parent dir.
    """
    parts = [p for p in cwd.strip("/").split("/") if p]
    for i in range(len(parts) - 1, 0, -1):
        if parts[i] == project:
            return parts[i - 1]
    return parts[-2] if len(parts) > 1 else ""


def parse_entry(line1: str, line2: str) -> tuple[str, str]:
    """→ (title, meta). Entries written before the summary format whitelist can
    have CLI error text where the title belongs. Label those instead of skipping
    them: a row a reader can see and dismiss beats one that silently vanishes."""
    if line1.startswith("### "):
        return line1[4:].strip(), line2
    return BROKEN, f"{line1} {line2}"


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: build-activity-index.py <knowledge_repo> <author>", file=sys.stderr)
        return 2
    root = Path(sys.argv[1]) / "activity"
    person = sys.argv[2]
    mine = root / person
    if not mine.is_dir():
        return 0

    rows: list[tuple[str, str, str, str, str, str, str]] = []
    for f in mine.glob("*/[0-9]*-*.md"):          # this member's shard only
        project = f.parent.name
        if project == "_daily" or not DATE_NAME.match(f.stem):
            continue
        text = f.read_text(encoding="utf-8", errors="replace")
        cwd_m = CWD_RE.search(text)
        ws = workspace_of(cwd_m.group(1), project) if cwd_m else ""
        for sid, line1, line2 in SESSION_RE.findall(text):
            title, meta = parse_entry(line1, line2)
            times = TIME_RE.findall(meta)
            rows.append(
                (f.stem, times[-1] if times else "00:00", person, ws, project,
                 sid[:8], title.replace("|", "\\|"))
            )

    # newest first — reports and "what happened lately" both read from the top
    rows.sort(key=lambda r: (r[0], r[1]), reverse=True)

    out = [
        f"# 활동 인덱스 — {person}",
        "",
        "`sync-activity.sh`가 자동 생성한다 — 직접 편집하지 말 것.",
        "이 파일은 이 사람의 활동만 담는다. **팀 전체를 볼 때는 사람별 인덱스를 함께 grep한다:**",
        "`grep '| 2026-07-' activity/*/INDEX.md`",
        "",
        "**프로젝트 이름은 작업 당시 cwd의 레포명이지 고객명이 아니다.** 고객 축에 가장 가까운 것은",
        "**워크스페이스** 열(프로젝트 체크아웃을 담은 상위 디렉토리)이다 — 실측에서 `skt-*` 폴더",
        "필터는 18건만 잡았지만 `skt-agent-proj` 워크스페이스는 29건을 잡았다.",
        "다만 워크스페이스도 힌트일 뿐이다: 반대로 그 안에 무관한 작업이 섞이기도 하므로",
        "최종 판단은 제목으로 하고, 확실히 해야 하면 본문을 연다.",
        "마지막 열은 Claude Code 세션 ID다. **같은 세션 = 같은 작업이 아니다** — 세션은 resume으로",
        "몇 주씩 이어지므로 한 ID가 수십 행에 걸친다. **같은 날 + 같은 주제**일 때만 한 건으로 묶어",
        "이중 계상을 피하고, 그 밖에는 제목으로 판단한다.",
        "",
        "| 날짜 | 시각 | 사람 | 워크스페이스 | 프로젝트 | 제목 | 세션 |",
        "|---|---|---|---|---|---|---|",
    ]
    for date, time, who, ws, project, sid, title in rows:
        out.append(
            f"| {date} | {time} | {who} | {ws} | "
            f"[{project}](./{project}/{date}.md) | {title} | `{sid}` |"
        )
    out.append("")
    (mine / "INDEX.md").write_text("\n".join(out), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
