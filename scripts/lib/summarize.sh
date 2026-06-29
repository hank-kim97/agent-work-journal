#!/usr/bin/env bash
# Summarize a transcript into a Korean work-journal entry via the resolved CLI.
# Usage: summarize.sh <transcript> <cwd> <machine> <date> <time> [preferred]
# Resolution: $SUMMARIZER_CMD > preferred(claude|codex) > autodetect.
set -uo pipefail

TRANSCRIPT="${1:?transcript}"; CWD="${2:-}"; MACHINE="${3:-}"; DATE="${4:-}"; TIME="${5:-}"; PREFERRED="${6:-}"
[ -f "$TRANSCRIPT" ] || exit 0

resolve_cmd() {
  if [ -n "${SUMMARIZER_CMD:-}" ]; then printf '%s' "$SUMMARIZER_CMD"; return; fi
  case "$PREFERRED" in
    claude) command -v claude >/dev/null && { printf 'claude -p --output-format=text'; return; } ;;
    codex)  command -v codex  >/dev/null && { printf 'codex exec -'; return; } ;;
  esac
  if command -v claude >/dev/null; then printf 'claude -p --output-format=text'
  elif command -v codex >/dev/null; then printf 'codex exec -'
  else printf ''; fi
}

CMD="$(resolve_cmd)"
[ -z "$CMD" ] && exit 0

PROMPT=$(cat <<PROMPT
다음 에이전트 세션 transcript을 한국어 업무일지 형식으로 요약해주세요.

규칙:
- 첫 줄: ### 한 줄짜리 제목 (50자 이내)
- 빈 줄 후 **Done** 섹션 — 한 일을 짧은 bullet 3-5개, 각 bullet 80자 이내, 한 줄짜리 사실
- 필요 시 빈 줄 후 **Next** 섹션 — 다음 할 일 bullet (없으면 통째로 생략)
- 파일 경로·commit hash·식별자는 백틱(\`)으로 감싸기
- 코드 펜스·이모지·긴 부연·tool 결과 인용 금지. 핵심만 압축.
- transcript에 의미 있는 작업이 없으면 "### (의미 있는 작업 없음)" 한 줄만 출력

작업 디렉토리: $CWD
머신: $MACHINE
시각: $DATE $TIME

Transcript (최근 200KB만):
$(tail -c 200000 "$TRANSCRIPT")
PROMPT
)

printf '%s' "$PROMPT" | eval "$CMD"
