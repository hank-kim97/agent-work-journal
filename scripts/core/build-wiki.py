#!/usr/bin/env python3
"""Generate per-project README.md and repo-level INDEX.md from session journals.

For each journals/<project>/ directory:
  1. Collect all YYYY-MM-DD.md session files (skip README, _daily, _legacy).
  2. Skip rebuild if README.md is newer than every session file (use --force to override).
  3. Send sessions to `claude -p`; write the response to journals/<project>/README.md.

Then build journals/INDEX.md by feeding the per-project READMEs + last-activity
dates back to `claude -p`.

Usage:
    python3 scripts/build-wiki.py                   # all projects, incremental
    python3 scripts/build-wiki.py --project skt     # single project
    python3 scripts/build-wiki.py --force           # rebuild even if up-to-date
    python3 scripts/build-wiki.py --no-index        # skip INDEX.md rebuild
"""
from __future__ import annotations
import argparse
import os
import re
import subprocess
import sys
from datetime import datetime, timedelta
from pathlib import Path

ROOT = Path(os.environ.get("JOURNAL_DIR", os.getcwd())).resolve()
JOURNALS = ROOT / "journals"
CLAUDE_BIN = os.environ.get("CLAUDE_BIN") or str(Path.home() / ".local/bin/claude")
SESSION_FILENAME_RE = re.compile(r"^\d{4}-\d{2}-\d{2}\.md$")

PROJECT_PROMPT = """다음은 "{project}" 프로젝트의 Claude Code 작업일지 세션들입니다.
이 자료를 바탕으로 프로젝트 위키(README)를 한국어로 작성해주세요.

규칙:
- 첫 줄: # {project}
- 두 번째 줄: > 자동 생성 위키 — {today} 갱신, 세션 {count}개 기반
- 빈 줄 후 ## 개요 — 프로젝트 목적·범위·현재 상태를 2~3문장으로 압축. 자료에 없으면 "(자료 부족)" 한 줄.
- 빈 줄 후 ## 주요 결정·레퍼런스 — bullet 형식으로 다음 두 유형을 통합:
  - 결정 사항: "~로 결정", "~ 전환", "~ 폐기", "~ 채택" 류 항목. 각 bullet 끝에 `(YYYY-MM-DD)` 표기.
  - 핵심 레퍼런스: 자료에 등장한 file path · MR/PR 번호 · commit hash · 도메인 식별자. 백틱으로 묶기.
  - 중복은 통합하고 가장 최근 상태 반영. 사소한 작업 로그는 생략.
- 코드 펜스(```)·이모지·긴 부연 금지. 모든 출력은 한국어.
- 형식만 잘 지키면 짧아도 됨 (bullet 5~15개 권장).

자료(세션은 날짜 오름차순):
{sessions}
"""

INDEX_PROMPT = """다음은 work-journal 저장소의 각 프로젝트 README와 마지막 활동일입니다.
이 자료를 정리한 인덱스 마크다운을 한국어로 출력해주세요.

규칙:
- 첫 줄: # work-journal — 프로젝트 인덱스
- 두 번째 줄: > {today} 갱신
- 빈 줄 후 ## 활성 (최근 7일) — 7일 내 세션이 있던 프로젝트(자료에 ACTIVE 표시된 것)
- 빈 줄 후 ## 비활성 — 그 외 프로젝트(INACTIVE)
- 각 섹션은 다음 형식 bullet:
  - `[<프로젝트>](<프로젝트>/README.md)` — 한 줄 요약 (마지막 활동일 `(YYYY-MM-DD)` 포함)
- 한 줄 요약은 각 README의 ## 개요 첫 문장에서 추출, 20자~80자.
- 출력은 위 마크다운 본문만. 코드 펜스(```), 이모지, 보조 설명 문장, "위 내용을 저장하세요" 같은 안내 금지.

자료:
{readmes}
"""


def session_files(project_dir: Path) -> list[Path]:
    return sorted(p for p in project_dir.iterdir()
                  if p.is_file() and SESSION_FILENAME_RE.match(p.name))


def project_dirs() -> list[Path]:
    return sorted(
        p for p in JOURNALS.iterdir()
        if p.is_dir() and not p.name.startswith("_")
    )


def last_activity_date(project_dir: Path) -> str | None:
    files = session_files(project_dir)
    return files[-1].stem if files else None


def needs_rebuild(project_dir: Path) -> bool:
    readme = project_dir / "README.md"
    files = session_files(project_dir)
    if not files:
        return False
    if not readme.exists():
        return True
    return readme.stat().st_mtime < max(f.stat().st_mtime for f in files)


def run_claude(prompt: str, timeout: int = 180) -> str:
    env = dict(os.environ)
    # Avoid the Stop hook recursing when we invoke claude -p.
    env["CLAUDE_JOURNAL_RUNNING"] = "1"
    try:
        result = subprocess.run(
            # --tools "" disables all built-in tools so claude returns the
            # markdown directly instead of going agentic on phrases like
            # "INDEX.md를 작성해주세요".
            [CLAUDE_BIN, "-p", "--tools", "", "--output-format=text"],
            input=prompt,
            capture_output=True,
            text=True,
            timeout=timeout,
            env=env,
        )
    except subprocess.TimeoutExpired:
        return ""
    out = result.stdout.strip()
    if os.environ.get("WIKI_DEBUG"):
        sys.stderr.write(
            f"[debug run_claude] rc={result.returncode} stdout_len={len(out)} "
            f"stderr_len={len(result.stderr)}\n"
        )
    # Guard against prompt-too-long errors. The error message is short and
    # appears at the very start. Don't false-positive on body text that merely
    # mentions the phrase.
    if len(out) < 400 and "prompt is too long" in out[:200].lower():
        return ""
    return unwrap_markdown(out)


def unwrap_markdown(text: str) -> str:
    """Strip leading/trailing code fences and chatty epilogue claude sometimes adds.

    Patterns handled:
      ```markdown\\n<body>\\n```\\nepilogue        → <body>
      <body>\\n```\\nepilogue                       → <body>  (rare)
      <body>                                        → <body>
    """
    t = text.strip()
    fence_open = re.match(r"^```[a-zA-Z]*\n", t)
    if fence_open:
        t = t[fence_open.end():]
        # Find closing fence
        m = re.search(r"\n```(?:\s|$)", t)
        if m:
            t = t[:m.start()]
    # Trim epilogue that appears after the last meaningful markdown content.
    # If there's a chatty paragraph after a final closing fence we missed,
    # drop everything after the last bullet/heading line followed by prose.
    return t.strip()


def build_project(project_dir: Path, force: bool = False) -> bool:
    project = project_dir.name
    if not force and not needs_rebuild(project_dir):
        print(f"  {project}: up-to-date")
        return False

    files = session_files(project_dir)
    if not files:
        print(f"  {project}: no sessions, skip")
        return False

    chunks = []
    for f in files:
        chunks.append(f"--- {f.stem} ---\n{f.read_text(encoding='utf-8')}")
    sessions = "\n\n".join(chunks)

    prompt = PROJECT_PROMPT.format(
        project=project,
        today=datetime.now().strftime("%Y-%m-%d"),
        count=len(files),
        sessions=sessions,
    )

    print(f"  {project}: rebuilding ({len(files)} sessions, {len(sessions)//1024}KB)…")
    content = run_claude(prompt)
    if not content or not content.startswith("# "):
        print(f"  {project}: bad/empty response, skip write")
        return False

    (project_dir / "README.md").write_text(content + "\n", encoding="utf-8")
    return True


def embed_index_in_readme() -> bool:
    """Sync journals/INDEX.md into root README.md between INDEX:START/END markers.

    Rewrites links from "<project>/README.md" (relative to journals/) to
    "journals/<project>/README.md" (relative to repo root).
    """
    readme = ROOT / "README.md"
    index = JOURNALS / "INDEX.md"
    if not readme.exists() or not index.exists():
        return False

    readme_text = readme.read_text(encoding="utf-8")
    if "<!-- INDEX:START -->" not in readme_text or "<!-- INDEX:END -->" not in readme_text:
        print("  README: missing INDEX markers, skip embed")
        return False

    index_text = index.read_text(encoding="utf-8").strip()
    lines = index_text.split("\n")
    # Drop the original H1 ("# work-journal — 프로젝트 인덱스") since we wrap with
    # our own "## 프로젝트 인덱스" header. Demote internal H2 ("## 활성") to H3.
    if lines and lines[0].startswith("# "):
        lines = lines[1:]
    demoted = []
    for ln in lines:
        if ln.startswith("## "):
            demoted.append("### " + ln[3:])
        else:
            demoted.append(ln)
    inner = "\n".join(demoted).strip()
    body = f"## 프로젝트 인덱스\n\n{inner}"
    # Rewrite links: [proj](proj/README.md) → [proj](journals/proj/README.md)
    body = re.sub(
        r'\]\((?!journals/)([^/)]+)/README\.md\)',
        r'](journals/\1/README.md)',
        body,
    )

    new_readme = re.sub(
        r"<!-- INDEX:START -->.*?<!-- INDEX:END -->",
        f"<!-- INDEX:START -->\n{body}\n<!-- INDEX:END -->",
        readme_text,
        flags=re.DOTALL,
    )
    if new_readme == readme_text:
        return False
    readme.write_text(new_readme, encoding="utf-8")
    print("  README: INDEX section embedded")
    return True


def build_index() -> bool:
    dirs = project_dirs()
    if not dirs:
        return False

    today = datetime.now().date()
    week_ago = today - timedelta(days=7)
    entries = []
    for d in dirs:
        readme = d / "README.md"
        if not readme.exists():
            continue
        last = last_activity_date(d) or "(unknown)"
        is_active = last != "(unknown)" and last >= week_ago.strftime("%Y-%m-%d")
        entries.append({
            "project": d.name,
            "last": last,
            "active": is_active,
            "readme": readme.read_text(encoding="utf-8"),
        })

    if not entries:
        return False

    chunks = []
    for e in entries:
        flag = "ACTIVE" if e["active"] else "INACTIVE"
        chunks.append(
            f"### {e['project']} (마지막 활동 {e['last']}, {flag})\n{e['readme']}"
        )
    prompt = INDEX_PROMPT.format(
        today=today.strftime("%Y-%m-%d"),
        readmes="\n\n".join(chunks),
    )
    print(f"  INDEX: rebuilding ({len(entries)} projects)…")
    content = run_claude(prompt)
    if not content or not content.startswith("# "):
        print("  INDEX: bad/empty response, skip write")
        return False
    (JOURNALS / "INDEX.md").write_text(content + "\n", encoding="utf-8")
    return True


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", help="single project name (else all)")
    parser.add_argument("--force", action="store_true",
                        help="rebuild even if README is up-to-date")
    parser.add_argument("--no-index", action="store_true",
                        help="skip INDEX.md rebuild")
    args = parser.parse_args()

    print(f"=== build-wiki.py @ {datetime.now():%Y-%m-%d %H:%M} ===")

    rebuilt_any = False
    if args.project:
        d = JOURNALS / args.project
        if not d.is_dir():
            print(f"no such project: {args.project}", file=sys.stderr)
            return 1
        rebuilt_any = build_project(d, force=args.force)
    else:
        for d in project_dirs():
            if build_project(d, force=args.force):
                rebuilt_any = True

    # Always rebuild INDEX if any project changed, or if explicitly forced.
    index_rebuilt = False
    if not args.no_index and (rebuilt_any or args.force or not (JOURNALS / "INDEX.md").exists()):
        index_rebuilt = build_index()

    # Embed INDEX into root README so the repo home page on GitHub shows it.
    if index_rebuilt or args.force or not _readme_has_index(ROOT / "README.md"):
        embed_index_in_readme()

    return 0


def _readme_has_index(readme: Path) -> bool:
    if not readme.exists():
        return False
    text = readme.read_text(encoding="utf-8")
    if "<!-- INDEX:START -->" not in text:
        return False
    # Has markers but they wrap only the placeholder line?
    placeholder_pattern = re.compile(
        r"<!-- INDEX:START -->\s*##\s*프로젝트 인덱스\s*\n\s*\(빌드 대기 중",
        re.DOTALL,
    )
    return placeholder_pattern.search(text) is None


if __name__ == "__main__":
    raise SystemExit(main())
