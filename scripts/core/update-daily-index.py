#!/usr/bin/env python3
"""Maintain a flat daily index linking each session to its project file.

File location: journals/_daily/<date>.md
Format:
    # {date}

    <!-- session:{id} -->
    - {time} · [{project}](../{project}/{date}.md) — {title}
    <!-- session:{id2} -->
    - ...

Entries are kept sorted by time. Re-running with the same session_id replaces
its line (idempotent).

Usage:
    update-daily-index.py <daily_index_file> <project> <session_id> <date> <time> <title>
"""
from __future__ import annotations
import re
import sys
from pathlib import Path

ENTRY_RE = re.compile(
    r"(<!-- session:[^>]+ -->\n- (\d{2}:\d{2})[^\n]*\n)"
)


def main() -> int:
    if len(sys.argv) != 7:
        print(
            "usage: update-daily-index.py file project session_id date time title",
            file=sys.stderr,
        )
        return 2

    daily_file, project, session_id, date, time_str, title = sys.argv[1:7]
    if not title:
        title = "(untitled)"

    path = Path(daily_file)
    existing = path.read_text(encoding="utf-8") if path.exists() else ""
    if not existing.strip():
        existing = f"# {date}\n\n"

    marker = f"<!-- session:{session_id} -->"
    new_entry = (
        f"{marker}\n"
        f"- {time_str} · [{project}](../{project}/{date}.md) — {title}\n"
    )

    if marker in existing:
        pattern = re.escape(marker) + r"\n-[^\n]*\n"
        existing = re.sub(pattern, new_entry, existing, count=1)
    else:
        existing = existing.rstrip() + "\n\n" + new_entry

    # Split header from body, sort entries by time, rebuild.
    header_match = re.match(r"(#[^\n]*\n+)", existing)
    header = header_match.group(1) if header_match else f"# {date}\n\n"
    body = existing[len(header):]

    entries = ENTRY_RE.findall(body)
    entries.sort(key=lambda pair: pair[1])
    rebuilt = header.rstrip() + "\n\n" + "".join(e[0] for e in entries)
    if not rebuilt.endswith("\n"):
        rebuilt += "\n"

    path.write_text(rebuilt, encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
