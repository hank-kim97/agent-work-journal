#!/usr/bin/env python3
"""Maintain a flat daily index linking each session to its project file.

File location: journals/_daily/<date>.md
Format:
    # {date}

    <!-- session:{id}:{project} -->
    - {time} · [{project}](../{project}/{date}.md) — {title}
    <!-- session:{id2}:{project2} -->
    - ...

Entries are kept sorted by time. Re-running with the same (session, project)
replaces its line (idempotent).

The key is (session, project), not session alone. One session often spans
several projects — the user cd's around, or resumes elsewhere — and keying on
the session alone made each new project overwrite the previous line, so the day
index silently lost every project but the last (measured: 9 of 22 days).

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
# Legacy entries keyed on the session alone. Their project is recoverable from
# the link, so upgrade in place on the next write instead of leaving a line the
# new key can never match (which would duplicate it).
LEGACY_RE = re.compile(
    r"<!-- session:([^:>\s]+) -->\n(- \d{2}:\d{2} · \[([^\]]+)\])"
)


def upgrade_legacy(text: str) -> str:
    return LEGACY_RE.sub(r"<!-- session:\1:\3 -->\n\2", text)


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
    existing = upgrade_legacy(existing)

    marker = f"<!-- session:{session_id}:{project} -->"
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
