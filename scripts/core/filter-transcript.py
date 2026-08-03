#!/usr/bin/env python3
"""Condense a Claude Code session transcript down to card-writing evidence.

A raw transcript is tens of MB; the parts that say *what was checked and why a
candidate was ruled out* are a tiny slice of it. This keeps that slice.

What is dropped (≈85% of bytes, measured on a real debugging session):
  attachments, tool_use payloads, tool_result output, thinking blocks.
What is kept: user turns and assistant text — where conclusions get written.

Selection when still over budget: score each message and keep the best until the
byte budget is spent, then restore chronological order.

  score = diagnostic keywords + 3×verdict words (원인/확정/소거…) + 5×topic terms

The topic terms matter more than they look. A long session often spans several
unrelated problems across days, so "just take the tail" grabs whatever was most
recent — measured on a real 32MB session, that returned none of the evidence for
the topic being carded. The caller (stage-1 triage) knows the topic, so pass it.

Deterministic: same input bytes → same output bytes, so a retry after a failed
run reuses the prompt cache instead of paying twice.

Usage: filter-transcript.py <transcript.jsonl> [--max-bytes N] [--topic "kw kw"]
"""
from __future__ import annotations

import json
import re
import sys

KEYWORDS = re.compile(
    r"원인|확정|소거|배제|해결|재현|검증|실패|에러|error|로그|log|"
    r"확인|규명|정상|이상|왜|때문|증상|추적|디버깅|"
    r"\b(?:40[0-9]|50[0-9])\b|timeout|exception|traceback",
    re.I,
)
VERDICT = re.compile(r"원인|확정|소거|배제|규명|결론|해결됨|정리", re.I)


def texts(path: str) -> list[tuple[int, str, str]]:
    """→ [(index, role, text)] for user turns and assistant text only."""
    out: list[tuple[int, str, str]] = []
    with open(path, encoding="utf-8", errors="replace") as f:
        for i, line in enumerate(f):
            try:
                d = json.loads(line)
            except Exception:
                continue
            if d.get("type") in ("attachment", "system", "mode", "last-prompt"):
                continue
            msg = d.get("message") or {}
            role = msg.get("role")
            if role not in ("user", "assistant"):
                continue
            content = msg.get("content")
            chunks: list[str] = []
            if isinstance(content, str):
                chunks.append(content)
            elif isinstance(content, list):
                for b in content:
                    # text blocks only — skip tool_use / tool_result / thinking
                    if isinstance(b, dict) and b.get("type") == "text":
                        chunks.append(b.get("text", ""))
            for t in chunks:
                t = t.strip()
                if t:
                    out.append((i, role, t))
    return out


def score(text: str, topic: re.Pattern | None) -> int:
    s = len(KEYWORDS.findall(text)) + 3 * len(VERDICT.findall(text))
    if topic is not None:
        s += 5 * len(topic.findall(text))
    return s


def main() -> int:
    args = sys.argv[1:]
    max_bytes = 60_000
    topic_terms = ""
    if "--max-bytes" in args:
        k = args.index("--max-bytes")
        max_bytes = int(args[k + 1])
        del args[k : k + 2]
    if "--topic" in args:
        k = args.index("--topic")
        topic_terms = args[k + 1]
        del args[k : k + 2]
    if not args:
        print("usage: filter-transcript.py <file.jsonl> [--max-bytes N] [--topic \"kw kw\"]",
              file=sys.stderr)
        return 2

    terms = [re.escape(w) for w in topic_terms.split() if len(w) > 1]
    topic = re.compile("|".join(terms), re.I) if terms else None

    scored = [(score(t, topic), i, r, t) for i, r, t in texts(args[0])]
    scored = [x for x in scored if x[0] > 0]
    if not scored:
        return 0  # nothing diagnostic in this session

    # best first; later messages win ties (debugging converges over time)
    scored.sort(key=lambda x: (-x[0], -x[1]))

    chosen: list[tuple[int, str, str]] = []
    used = 0
    for sc, i, role, t in scored:
        block = len((t + role).encode("utf-8")) + 24   # budget in BYTES, not chars
        if used + block > max_bytes:
            if used > max_bytes * 0.9:
                break                                   # budget effectively spent
            continue                                    # try a smaller message
        chosen.append((i, role, t))
        used += block

    for i, role, t in sorted(chosen, key=lambda x: x[0]):
        print(f"\n===== {role} =====\n{t}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
