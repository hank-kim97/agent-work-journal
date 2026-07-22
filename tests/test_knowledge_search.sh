#!/usr/bin/env bash
# [AC1] 검색 착지: /knowledge 스킬의 검색 절차(키워드 AND grep → OR 폴백)가
# fixture 카드 코퍼스에서 golden query로 착지하는지 검증.
# [AC2-negative] 단일 고객 이슈 키워드는 어떤 카드에도 착지하지 않아야 한다.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
. "$HERE/helpers.sh"

repo="$(mktemp -d)"; mkdir -p "$repo/cards"

cat > "$repo/cards/ocr-502-size-limit.md" <<'MD'
---
tags: [ocr, http-502, image-size]
sources: ["[SKT] 2026-07-14"]
---
# OCR 502 — 이미지 크기 제한과 배치 부하

## 문제상황
1MB 초과 이미지 업로드 시 OCR 업스트림이 즉시 502 반환
## 정리
- 실패 입력의 크기/동시성 프로파일부터 본다
MD
cat > "$repo/cards/fastapi-sync-blocking.md" <<'MD'
---
tags: [fastapi, asyncio, blocking]
sources: ["[DISC] 2026-07-16"]
---
# async 핸들러 안의 sync 코드가 전체 API를 세움

## 문제상황
느린 엔드포인트 하나로 다른 요청까지 밀리는 head-of-line blocking
## 정리
- 워커 수가 아니라 아키텍처(큐/분리)로 푼다
MD
cat > "$repo/cards/cloud-egress-allowlist.md" <<'MD'
---
tags: [cloud, egress, http-403, allowlist]
sources: ["[WIKI] 2026-07-17"]
---
# 클라우드 루틴의 외부 도메인 403 — egress allowlist 미포함

## 문제상황
클라우드 환경에서 arxiv 다운로드가 403으로 차단
## 정리
- Network access를 Custom으로 바꾸고 도메인 허용
MD

# SKILL.md의 검색 절차를 "미러링"(재현)한다 — 스킬은 LLM 프로즈라 직접 실행
# 불가하므로, SKILL.md의 AND→OR 전략을 수정하면 이 함수도 함께 갱신할 것.
search() { # search <kw1> [kw2...] → 매치 파일명 출력
  local files; files=$(ls "$repo/cards"/*.md)
  local kw
  for kw in "$@"; do
    files=$(echo "$files" | xargs grep -lie "$kw" 2>/dev/null)
    [ -z "$files" ] && break
  done
  if [ -z "$files" ]; then # OR 폴백
    local args=(); for kw in "$@"; do args+=(-e "$kw"); done
    files=$(ls "$repo/cards"/*.md | xargs grep -li "${args[@]}" 2>/dev/null)
  fi
  echo "$files"
}

# golden query 1: 직접 키워드
r=$(search "ocr" "502")
assert_contains "$r" "ocr-502-size-limit" "golden: 'OCR 502' lands"
# golden query 2: 패러프레이즈 (증상 말투)
r=$(search "이미지" "502")
assert_contains "$r" "ocr-502-size-limit" "golden: '이미지 502' paraphrase lands"
# golden query 3: 동시성 증상
r=$(search "밀리" "blocking")
assert_contains "$r" "fastapi-sync-blocking" "golden: 'FastAPI 밀림' lands"
# golden query 4: egress 미언급 패러프레이즈
r=$(search "클라우드" "차단")
assert_contains "$r" "cloud-egress-allowlist" "golden: '클라우드 차단' paraphrase lands"
# golden query 5: 태그 경유
r=$(search "allowlist")
assert_contains "$r" "cloud-egress-allowlist" "golden: tag keyword lands"

# [AC2] negative: 단일 고객 이슈 키워드 — 카드 코퍼스에 존재하지 않아야 함
r=$(search "복지온")
[ -z "$r" ] && pass "negative: client-specific keyword lands nowhere" \
             || fail "negative: client-specific keyword lands nowhere (got: $r)"

finish
