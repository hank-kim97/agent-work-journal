#!/usr/bin/env bash
# Summarize a transcript into a Korean work-journal entry via the resolved CLI.
# Usage: summarize.sh <transcript> <cwd> <machine> <date> <time> [preferred]
# Resolution: $SUMMARIZER_CMD > preferred(claude|codex) > autodetect.
#
# Prompt layout is prompt-cache friendly (recap-style):
#   stable instructions -> append-only transcript window -> volatile time last.
# Prompt caching is a byte-exact prefix match, so anything that changes every
# call (the clock) must come AFTER the transcript, and the transcript window
# must not shift on every call. The window start is quantized to WINDOW_STEP:
# consecutive turns share an identical prefix (KV cache read at ~0.1x price)
# and the window only jumps once per WINDOW_STEP bytes of transcript growth.
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

# Transcript window: whole file while small (append-only prefix = cache hit),
# otherwise start at a WINDOW_STEP-aligned byte offset so the prefix stays
# byte-identical across calls within the same growth band.
WINDOW_MAX="${SUMMARIZE_WINDOW_MAX:-800000}"    # bytes (~200K tokens)
WINDOW_STEP="${SUMMARIZE_WINDOW_STEP:-200000}"  # offset quantization step
SIZE=$(wc -c < "$TRANSCRIPT")
OFFSET=0
if [ "$SIZE" -gt "$WINDOW_MAX" ]; then
  OFFSET=$(( (SIZE - WINDOW_MAX + WINDOW_STEP - 1) / WINDOW_STEP * WINDOW_STEP ))
fi

PROMPT=$(cat <<PROMPT
다음 에이전트 세션 transcript을 한국어 업무일지 형식으로 요약해주세요.

규칙:
- 첫 줄: ### 한 줄짜리 제목 (50자 이내)
- 빈 줄 후 **Done** 섹션 — 한 일을 짧은 bullet 3-5개, 각 bullet 80자 이내, 한 줄짜리 사실
- 필요 시 빈 줄 후 **Next** 섹션 — 다음 할 일 bullet (없으면 통째로 생략)
- 파일 경로·commit hash·식별자는 백틱(\`)으로 감싸기
- 코드 펜스·이모지·긴 부연·tool 결과 인용 금지. 핵심만 압축.
- 문제를 해결한 세션은 문제→원인→해결이 한 세트로 드러나게 bullet을 구성 (원인·해결이 확인된 경우 생략 금지)
- 원인을 확정한 bullet에는 **근거를 하나 남긴다** — 판정 로그 문구·확인 명령·수치 중 하나. 이 bullet만은 80자를 넘겨도 된다
- transcript에 의미 있는 작업이 없으면 "### (의미 있는 작업 없음)" 한 줄만 출력

작업 디렉토리: $CWD
머신: $MACHINE

Transcript:
$(tail -c +$((OFFSET + 1)) "$TRANSCRIPT")

---
시각: $DATE $TIME
위 transcript를 규칙에 따라 요약해주세요.
PROMPT
)

printf '%s' "$PROMPT" | eval "$CMD"
