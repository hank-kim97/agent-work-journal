#!/usr/bin/env python3
"""Insert or replace a per-session section inside a project's daily journal.

File header:
    # {project} — {date}

Section format:
    <!-- session:{id} -->
    ### {title from summary}
    `{cwd basename}` · {machine} · {start_time} → {end_time}

    {rest of summary body — Done/Next sections}

    <sub>cwd: `{full cwd}`</sub>
    <!-- /session:{id} -->

When a section already exists, the start_time is preserved (parsed back from
the existing meta line) and only end_time is updated. Single-shot sessions
render as just one time (no arrow).

Usage:
    update-section.py <daily_file> <session_id> <date> <machine> <cwd> <time> <project>
    (summary body is read from stdin)
"""
from __future__ import annotations
import re
import sys
from pathlib import Path

# Meta line: `cwd` · machine · HH:MM[ → HH:MM]
META_RE = re.compile(
    r"`[^`]+`(?:\s*·\s*[^·\n]+?)?\s*·\s*(\d{2}:\d{2})(?:\s*→\s*(\d{2}:\d{2}))?"
)


def extract_start_time(block_text: str, default: str) -> str:
    m = META_RE.search(block_text)
    if m:
        return m.group(1)
    return default


def main() -> int:
    if len(sys.argv) != 8:
        print(
            "usage: update-section.py daily session_id date machine cwd time project",
            file=sys.stderr,
        )
        return 2

    daily_file, session_id, date, machine, cwd, time_str, project = sys.argv[1:8]
    body = sys.stdin.read().strip()
    if not body:
        return 0

    path = Path(daily_file)
    existing = path.read_text(encoding="utf-8") if path.exists() else ""
    if not existing:
        existing = f"# {project} — {date}\n\n"

    start_marker = f"<!-- session:{session_id} -->"
    end_marker = f"<!-- /session:{session_id} -->"

    start_time = time_str
    if start_marker in existing:
        block_pattern = re.escape(start_marker) + r"(.*?)" + re.escape(end_marker)
        m = re.search(block_pattern, existing, flags=re.DOTALL)
        if m:
            start_time = extract_start_time(m.group(1), default=time_str)

    end_time = time_str
    time_range = end_time if start_time == end_time else f"{start_time} → {end_time}"

    cwd_short = Path(cwd).name or cwd
    meta_line = f"`{cwd_short}` · {machine} · {time_range}"

    parts = body.split("\n", 1)
    title_line = parts[0]
    rest = parts[1].lstrip("\n") if len(parts) > 1 else ""

    inner_lines = [title_line, meta_line]
    if rest:
        inner_lines.append("")
        inner_lines.append(rest.rstrip())
    inner_lines.append("")
    inner_lines.append(f"<sub>cwd: `{cwd}`</sub>")
    inner = "\n".join(inner_lines)

    block = f"{start_marker}\n{inner}\n{end_marker}\n"

    if start_marker in existing:
        pattern = re.escape(start_marker) + r".*?" + re.escape(end_marker) + r"\n?"
        new = re.sub(pattern, block, existing, count=1, flags=re.DOTALL)
    else:
        new = existing.rstrip() + "\n\n" + block

    path.write_text(new, encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
