#!/usr/bin/env python3
"""Print JSON {"category": ..., "project": ...} for a given CWD.

Reads rules from ~/work-journal/config.json. Each rule has a prefix and
category, optionally a project name. First matching prefix wins. Project
falls back to git toplevel basename, then CWD basename.
"""
from __future__ import annotations
import json
import subprocess
import sys
from pathlib import Path


def classify(cwd: str, config: dict) -> dict:
    cwd_norm = cwd.rstrip("/") + "/"
    matched = None
    for rule in config.get("rules", []):
        prefix = rule.get("prefix", "").rstrip("/") + "/"
        if cwd_norm.startswith(prefix):
            matched = rule
            break

    if matched is not None:
        category = matched.get("category", config.get("default", "private"))
        project = matched.get("project") or derive_project(cwd)
    else:
        category = config.get("default", "private")
        project = derive_project(cwd)
    return {"category": category, "project": sanitize(project)}


def derive_project(cwd: str) -> str:
    try:
        result = subprocess.run(
            ["git", "-C", cwd, "rev-parse", "--show-toplevel"],
            capture_output=True, text=True, timeout=2,
        )
        if result.returncode == 0:
            top = result.stdout.strip()
            if top:
                return Path(top).name
    except Exception:
        pass
    return Path(cwd).name or "misc"


def sanitize(name: str) -> str:
    # Keep filesystem-safe: replace path separators and whitespace
    cleaned = name.strip().replace("/", "_").replace(" ", "_")
    return cleaned or "misc"


def main() -> int:
    fallback = {"category": "private", "project": "misc"}
    if len(sys.argv) != 2:
        print(json.dumps(fallback))
        return 0
    cwd = sys.argv[1]
    config_path = Path(__file__).resolve().parents[2] / "config.json"
    try:
        with config_path.open() as f:
            config = json.load(f)
    except Exception:
        print(json.dumps(fallback))
        return 0
    print(json.dumps(classify(cwd, config), ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
