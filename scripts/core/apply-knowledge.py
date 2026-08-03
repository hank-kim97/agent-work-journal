#!/usr/bin/env python3
"""Apply LLM knowledge-extraction output to the team knowledge repo.

Parses the extractor's raw output and applies it to <repo>/cards/:

    === CARD START: <slug> ===        new card (full markdown with frontmatter)
    ...
    === CARD END ===

    === APPEND TO: <slug> ===         merge into an existing card
    sources: ["[CODE] YYYY-MM-DD"]      (optional; merged into frontmatter)
    사례: <one-line case description>    (one or more lines)
    === APPEND END ===

    === EXCLUDED ===                  boundary-rule audit trail
    - <item>: <reason>

    NO NEW KNOWLEDGE                  no-op marker (nothing to record)

Safety rules:
  - A NEW card whose slug already exists is demoted to an append (LLM mistake
    guard) — its body is summarized into a 사례 line instead of overwriting.
  - An APPEND whose slug does not exist is reported and skipped (never
    fabricate a card from an append fragment).
  - INDEX.md is regenerated deterministically from card frontmatter.

Usage:
    apply-knowledge.py <knowledge_repo> [raw_file] [--date YYYY-MM-DD]
    (reads stdin when raw_file is omitted or "-")

Exit codes: 0 ok (including no-op), 2 unparseable output,
            3 secret pattern detected (fail-closed, nothing written).
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

# --- credential gate -----------------------------------------------------------
# This repo is an INTERNAL team log: client names, hostnames, IPs, employee ids
# and author attribution are deliberately kept — they are what makes a card
# actionable for the next person on that system. So there is no PII redaction.
#
# Credentials are different: an API key committed to git history cannot be
# recalled, internal repo or not. Secrets fail the run closed (exit 3).
SECRET_RE = re.compile(
    r"""(?x)(
        (?<![A-Za-z0-9])sk-ant-[A-Za-z0-9_-]{6,}          # Anthropic
      | (?<![A-Za-z0-9])sk-proj-[A-Za-z0-9_-]{20,}        # OpenAI project key
      | (?<![A-Za-z0-9])sk-[A-Za-z0-9]{40,}               # OpenAI classic (48c, no '-':
                                                          #  ta·sk-/ri·sk-/di·sk-* 오탐 방지, R1)
      | AIza[0-9A-Za-z_-]{35}                             # Google API
      | gh[posur]_[A-Za-z0-9]{20,}                        # GitHub ghp/gho/ghs/ghu/ghr
      | github_pat_[A-Za-z0-9_]{20,}
      | glpat-[A-Za-z0-9_-]{16,}                          # GitLab PAT
      | xox[baprs]-[A-Za-z0-9-]{10,}                      # Slack (xoxa/xoxr incl.)
      | AKIA[0-9A-Z]{16}                                  # AWS access key id
      | eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{5,}   # JWT
      | -----BEGIN[\ A-Z]*PRIVATE\ KEY-----               # PEM
      | [a-z][a-z0-9+.-]*://[^\s/@]+:[^\s/@]+@            # user:pass@ in URI
      | (?i:api[_-]?key|secret|token|password|passwd|aws_secret_access_key)
            \s*[:=]\s*['\"]?[A-Za-z0-9/_+=-]{16,}         # generic assignment
    )"""
)


def has_secret(text: str) -> bool:
    """True when a credential-shaped token is present. Caller fails closed so a
    leaked key never lands in git history."""
    return SECRET_RE.search(text) is not None


CARD_RE = re.compile(
    r"=== CARD START: ([a-z0-9][a-z0-9-]*) ===\n(.*?)\n=== CARD END ===", re.S
)
APPEND_RE = re.compile(
    r"=== APPEND TO: ([a-z0-9][a-z0-9-]*) ===\n(.*?)\n=== APPEND END ===", re.S
)
EXCLUDED_RE = re.compile(r"=== EXCLUDED ===\n(.*?)(?:\n=== |\Z)", re.S)
# NOTE: greedy (.*) up to the LAST ] on the line — entries like "[SKT] 2026-07-14"
# contain inner brackets, so [^\]]* would cut the match short.
SOURCES_RE = re.compile(r"^sources:\s*\[(.*)\]\s*$", re.M)
TAGS_RE = re.compile(r"^tags:\s*\[(.*)\]\s*$", re.M)
TITLE_RE = re.compile(r"^# (.+)$", re.M)


def parse_list(inner: str) -> list[str]:
    return [t.strip().strip('"').strip("'") for t in inner.split(",") if t.strip()]


def merge_sources(card_text: str, new_sources: list[str]) -> str:
    m = SOURCES_RE.search(card_text)
    if not m:
        return card_text
    merged = parse_list(m.group(1))
    for s in new_sources:
        if s not in merged:
            merged.append(s)
    rendered = "sources: [" + ", ".join(f'"{s}"' for s in merged) + "]"
    return card_text[: m.start()] + rendered + card_text[m.end():]


def append_case(card_text: str, case_lines: list[str], date: str) -> str:
    block = "\n".join(f"- {date} {line}" for line in case_lines)
    if re.search(r"^## 사례\s*$", card_text, re.M):
        return card_text.rstrip() + "\n" + block + "\n"
    return card_text.rstrip() + "\n\n## 사례\n" + block + "\n"


def summarize_body_for_case(body: str) -> str:
    """Demoted NEW card → one 사례 line from its title (+ 정리 first bullet)."""
    title = TITLE_RE.search(body)
    line = title.group(1).strip() if title else "(제목 없음)"
    m = re.search(r"^## 정리\n(.+?)$", body, re.M)
    if m:
        line += f" — {m.group(1).strip().lstrip('- ')}"
    return line


def rebuild_index(repo: Path) -> int:
    rows = []
    for p in sorted((repo / "cards").glob("*.md")):
        text = p.read_text(encoding="utf-8")
        title_m = TITLE_RE.search(text)
        tags_m = TAGS_RE.search(text)
        src_m = SOURCES_RE.search(text)
        rows.append(
            (
                title_m.group(1).strip() if title_m else p.stem,
                p.stem,
                tags_m.group(1).strip() if tags_m else "",
                src_m.group(1).strip() if src_m else "",
            )
        )
    lines = [
        "# RE팀 업무 기록 — INDEX",
        "",
        f"> 카드 {len(rows)}장 (apply-knowledge.py 자동 생성 — 직접 편집 금지)",
        "",
        "| 카드 | 태그 | 출처 |",
        "|---|---|---|",
    ]
    for title, slug, tags, srcs in sorted(rows):
        lines.append(f"| [{title}](cards/{slug}.md) | {tags} | {srcs} |")
    (repo / "INDEX.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    return len(rows)


def main() -> int:
    args = list(sys.argv[1:])
    date = "unknown-date"
    if "--date" in args:
        i = args.index("--date")
        date = args[i + 1]
        del args[i : i + 2]
    if not args:
        print("usage: apply-knowledge.py <knowledge_repo> [raw_file] [--date D]", file=sys.stderr)
        return 2
    repo = Path(args[0])
    raw = (
        sys.stdin.read()
        if len(args) < 2 or args[1] == "-"
        else Path(args[1]).read_text(encoding="utf-8")
    )

    cards_dir = repo / "cards"
    cards_dir.mkdir(parents=True, exist_ok=True)

    new_cards = CARD_RE.findall(raw)
    # strip card spans first so an APPEND fragment nested inside a card body
    # can't be double-processed (code review INFO)
    appends = APPEND_RE.findall(CARD_RE.sub("", raw))
    excluded_m = EXCLUDED_RE.search(raw)
    noop = "NO NEW KNOWLEDGE" in raw

    if not new_cards and not appends and not excluded_m and not noop:
        print("apply-knowledge: unrecognized extractor output (no markers)", file=sys.stderr)
        return 2

    # credential gate: fail closed, never log the offending content
    for slug, body in new_cards:
        if has_secret(body):
            print(f"apply-knowledge: SECRET pattern in card '{slug}' — run rejected", file=sys.stderr)
            return 3
    for slug, block in appends:
        if has_secret(block):
            print(f"apply-knowledge: SECRET pattern in append '{slug}' — run rejected", file=sys.stderr)
            return 3

    created, merged, skipped = [], [], []

    for slug, body in new_cards:
        body = body.strip() + "\n"
        target = cards_dir / f"{slug}.md"
        if target.exists():  # LLM mistake guard: demote to append
            text = target.read_text(encoding="utf-8")
            src_m = SOURCES_RE.search(body)
            if src_m:
                text = merge_sources(text, parse_list(src_m.group(1)))
            text = append_case(text, [summarize_body_for_case(body)], date)
            target.write_text(text, encoding="utf-8")
            merged.append(slug + " (demoted new)")
        else:
            target.write_text(body, encoding="utf-8")
            created.append(slug)

    for slug, block in appends:
        target = cards_dir / f"{slug}.md"
        if not target.exists():
            skipped.append(slug + " (append target missing)")
            continue
        text = target.read_text(encoding="utf-8")
        src_m = SOURCES_RE.search(block)
        if src_m:
            text = merge_sources(text, parse_list(src_m.group(1)))
        cases = [
            ln.split(":", 1)[1].strip() if ln.startswith("사례:") else ln.lstrip("- ").strip()
            for ln in block.splitlines()
            if ln.startswith("사례:") or (ln.startswith("- ") and "사례" not in ln[:4])
        ]
        cases = [c for c in cases if c]
        if cases:
            text = append_case(text, cases, date)
        target.write_text(text, encoding="utf-8")
        merged.append(slug)

    if excluded_m and excluded_m.group(1).strip():
        # excluded.md is committed too — scrub it like cards (architect rec #1).
        # Audit text differs from cards: a secret here shouldn't kill the run
        # (cards already passed), so redact instead of fail-closed.
        # audit text: a stray secret here shouldn't kill a run whose cards
        # already passed — mask just the secret and keep the entry.
        ex_text = SECRET_RE.sub("[REDACTED-SECRET]", excluded_m.group(1).strip())
        ex = repo / "excluded.md"
        header = "# 추출 제외 목록 (경계 규칙 감사 추적)\n" if not ex.exists() else ex.read_text(encoding="utf-8")
        ex.write_text(header.rstrip() + f"\n\n## {date}\n{ex_text}\n", encoding="utf-8")

    total = rebuild_index(repo) if (created or merged) else len(list(cards_dir.glob("*.md")))

    print(f"apply-knowledge: +{len(created)} new, ~{len(merged)} merged, "
          f"!{len(skipped)} skipped, {total} total cards")
    for s in created:
        print(f"  + {s}")
    for s in merged:
        print(f"  ~ {s}")
    for s in skipped:
        print(f"  ! {s}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
