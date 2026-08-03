#!/usr/bin/env python3
"""Rebuild journals/_daily/<date>.md from the per-project journals.

Needed because the daily index used to be keyed on the session alone. A session
that spans several projects (the user cd's around, or resumes elsewhere) then
overwrote its own line each time, so the index kept only the last project and
silently dropped the rest — measured at 9 of 22 days on a real journal.

update-daily-index.py now keys on (session, project) and upgrades legacy
markers in place, so new writes are correct. This recovers the days already
lost: the per-project files still hold every session, so the index can be
regenerated from them.

Idempotent — safe to re-run. Usage: rebuild-daily-index.py <journal_dir>
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

SESSION_RE = re.compile(r"<!-- session:([0-9a-zA-Z-]+) -->\n### ([^\n]*)\n([^\n]*)")
TIME_RE = re.compile(r"\b(\d{2}:\d{2})\b")


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: rebuild-daily-index.py <journal_dir>", file=sys.stderr)
        return 2
    journals = Path(sys.argv[1]) / "journals"
    if not journals.is_dir():
        print(f"no journals dir: {journals}", file=sys.stderr)
        return 1

    # date -> list of (time, project, session, title)
    days: dict[str, list[tuple[str, str, str, str]]] = {}
    for f in sorted(journals.glob("*/[0-9]*-*.md")):
        project = f.parent.name
        if project == "_daily":
            continue
        date = f.stem
        text = f.read_text(encoding="utf-8", errors="replace")
        for sid, title, meta in SESSION_RE.findall(text):
            # meta is "`proj` · machine · HH:MM → HH:MM"; take the LAST time so
            # a rebuilt line sorts where the live writer would have put it (the
            # live path stamps the current turn's time, i.e. the end).
            times = TIME_RE.findall(meta)
            days.setdefault(date, []).append(
                (times[-1] if times else "00:00", project, sid, title.strip())
            )

    out_dir = journals / "_daily"
    out_dir.mkdir(parents=True, exist_ok=True)
    changed = 0
    for date, entries in sorted(days.items()):
        entries.sort(key=lambda e: (e[0], e[1]))
        body = "".join(
            f"<!-- session:{sid}:{project} -->\n"
            f"- {time} · [{project}](../{project}/{date}.md) — {title}\n"
            for time, project, sid, title in entries
        )
        target = out_dir / f"{date}.md"
        new = f"# {date}\n\n{body}"
        if not target.exists() or target.read_text(encoding="utf-8") != new:
            target.write_text(new, encoding="utf-8")
            changed += 1
    print(f"rebuilt {changed}/{len(days)} daily index files")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
