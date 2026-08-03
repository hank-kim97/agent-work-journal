#!/usr/bin/env python3
"""Regenerate activity/INDEX.md — one row per (date, person, project, session).

Why this file exists: **a directory name is the cwd repo, not the client.** On a
real month, SKT work lived in `zez-server` (11 sessions) and `agent-runtime` (4)
as much as in `skt-*` (17) — so filtering activity by directory silently drops
half the material and the gap is invisible in the result. Measured on a report
dry-run: the directory filter found 17 of 35 relevant files.

The fix is not a smarter filter, it is making *complete enumeration cheap*. One
grep on a date prefix here lists every session in the period with its title, so
the reader picks targets from titles instead of guessing from folder names, and
opens only the files that matter.

The session id is included so the same session appearing under several projects
is recognisable as one piece of work rather than counted several times.

Deterministic and fully regenerated each run. Usage: build-activity-index.py <repo>
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

SESSION_RE = re.compile(r"<!-- session:([0-9a-zA-Z-]+) -->\n### ([^\n]*)\n([^\n]*)")
TIME_RE = re.compile(r"\b(\d{2}:\d{2})\b")
DATE_NAME = re.compile(r"^\d{4}-\d{2}-\d{2}$")


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: build-activity-index.py <knowledge_repo>", file=sys.stderr)
        return 2
    root = Path(sys.argv[1]) / "activity"
    if not root.is_dir():
        return 0

    rows: list[tuple[str, str, str, str, str, str]] = []
    for f in root.glob("*/*/[0-9]*-*.md"):
        project = f.parent.name
        if project == "_daily" or not DATE_NAME.match(f.stem):
            continue
        person = f.parent.parent.name
        text = f.read_text(encoding="utf-8", errors="replace")
        for sid, title, meta in SESSION_RE.findall(text):
            times = TIME_RE.findall(meta)
            rows.append(
                (f.stem, times[-1] if times else "00:00", person, project,
                 sid[:8], title.strip().replace("|", "\\|"))
            )

    # newest first — reports and "what happened lately" both read from the top
    rows.sort(key=lambda r: (r[0], r[1]), reverse=True)

    out = [
        "# 활동 인덱스",
        "",
        "`sync-activity.sh`가 자동 생성한다 — 직접 편집하지 말 것.",
        "",
        "기간으로 좁힐 때는 날짜 접두로 grep한다: `grep '| 2026-07-' INDEX.md`.",
        "**디렉토리 이름은 작업 당시 cwd의 레포명이지 고객명이 아니다** — 고객·주제 단위로 모을 때는",
        "폴더로 거르지 말고 이 표에서 제목을 훑어 대상을 고른 뒤 해당 파일만 연다.",
        "세션이 같으면(마지막 열) 여러 프로젝트에 걸친 **하나의 작업**이다. 실적을 이중 계상하지 말 것.",
        "",
        "| 날짜 | 시각 | 사람 | 프로젝트 | 제목 | 세션 |",
        "|---|---|---|---|---|---|",
    ]
    for date, time, person, project, sid, title in rows:
        out.append(
            f"| {date} | {time} | {person} | "
            f"[{project}](./{person}/{project}/{date}.md) | {title} | `{sid}` |"
        )
    out.append("")
    (root / "INDEX.md").write_text("\n".join(out), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
