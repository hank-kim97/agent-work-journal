#!/usr/bin/env bash
# /knowledge 스킬이 기술한 조회 절차를 미러링해 검증한다.
# 스킬은 LLM 프로즈라 직접 실행할 수 없으므로, SKILL.md의 절차를 바꾸면
# 이 파일의 함수도 함께 갱신할 것.
#   ① 활동 조회 (누가 뭐 했나 / 어디까지)   ② 카드 검색   ③ 카드 0건 → 활동 폴백
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
. "$HERE/helpers.sh"

repo="$(mktemp -d)"; mkdir -p "$repo/cards" "$repo/activity/hank/doc-console" \
  "$repo/activity/hank/_daily" "$repo/activity/jiwon/skt-hermes"

# --- 카드 fixture ---
cat > "$repo/cards/ocr-upstream-image-size-limit.md" <<'MD'
---
tags: [ocr, upstage, http-502, image-size]
sources: ["hank · skt-hermes · 2026-07-14 · aaaa1111-bbbb-2222-cccc-333344445555"]
---
# 1MB 초과 이미지를 OCR 업스트림(Upstage)에 보내면 즉시 502

## 문제상황
대용량 스캔 문서 세트가 전건 502
## 검증 상태
검증됨 — 리사이즈 후 통과 확인
## 정리
- 실패 입력의 크기 프로파일부터 본다
MD
cat > "$repo/cards/flask-secret-key-mismatch.md" <<'MD'
---
tags: [flask, session, secret-key, sso]
sources: ["hank · doc-console · 2026-07-29 · d8c3e962-707b-40e4-a7ca-94f556801c36"]
---
# 세션 쿠키는 도달하는데 로그인이 안 풀린다 — 서명 키 불일치

## 검증 상태
검증됨
## 정리
- 다중 서버 세션은 서명 키 대조를 최우선으로
MD

# --- 활동 fixture ---
cat > "$repo/activity/hank/_daily/2026-08-03.md" <<'MD'
# 2026-08-03

- 10:20 · [doc-console](../doc-console/2026-08-03.md) — SSO next 파라미터 지원 추가
MD
cat > "$repo/activity/hank/doc-console/2026-08-02.md" <<'MD'
# doc-console — 2026-08-02

### 게이트웨이 로그인 원인 규명
**Done**
- 후보 8건 순차 소거로 FLASK_SECRET_KEY 불일치 확정
**Next**
- Auth Flask에 next 파라미터 지원 추가
MD
cat > "$repo/activity/hank/doc-console/2026-08-03.md" <<'MD'
# doc-console — 2026-08-03

### SSO next 파라미터 지원 추가
**Done**
- /login에서 세션 저장, 콜백에서 복귀 구현
- 열린 리다이렉트 차단 포함
**Next**
- Auth Flask 재시작 후 런타임 검증
MD
cat > "$repo/activity/jiwon/skt-hermes/2026-08-03.md" <<'MD'
# skt-hermes — 2026-08-03

### Kafka 컨슈머 랙 조사
**Done**
- 파티션 리밸런싱 주기 확인
MD

# --- 스킬 절차 미러 ---
people() { ls "$repo/activity"; }
daily()  { cat "$repo/activity/$1/_daily/$2.md" 2>/dev/null; }
history(){ ls "$repo/activity/$1/$2/" 2>/dev/null; }
cards()  { local f; f=$(ls "$repo/cards"/*.md)
  for kw in "$@"; do f=$(echo "$f"|xargs grep -lie "$kw" 2>/dev/null); [ -z "$f" ]&&break; done
  [ -z "$f" ] && { local a=(); for kw in "$@"; do a+=(-e "$kw"); done
    f=$(ls "$repo/cards"/*.md|xargs grep -li "${a[@]}" 2>/dev/null); }
  echo "$f"|xargs -n1 basename 2>/dev/null|tr '\n' ' '; }
act_fallback(){ grep -rile "$1" "$repo/activity" 2>/dev/null|xargs -n1 basename 2>/dev/null|tr '\n' ' '; }

# ① 요구사항 1 — "누가 오늘 뭐 했나"
assert_contains "$(people)" "hank" "team member list discoverable"
assert_contains "$(daily hank 2026-08-03)" "SSO next 파라미터" "today's cross-project summary readable"

# ② 요구사항 2 — "A가 어디까지 진행했나" (날짜순 이력 + 마지막 Next)
h=$(history hank doc-console)
assert_contains "$h" "2026-08-02" "project history lists earlier date"
assert_contains "$h" "2026-08-03" "project history lists latest date"
latest=$(cat "$repo/activity/hank/doc-console/2026-08-03.md")
assert_contains "$latest" "Next" "latest entry carries remaining work"
assert_contains "$latest" "재시작 후 런타임 검증" "remaining work is specific"

# ③ 요구사항 3 — 기술 질의 (직접 키워드 / 벤더명 / 패러프레이즈)
assert_contains "$(cards ocr 502)" "ocr-upstream-image-size-limit" "tech query lands"
assert_contains "$(cards upstage)" "ocr-upstream-image-size-limit" "vendor-name query lands"
assert_contains "$(cards 세션 secret_key)" "flask-secret-key-mismatch" "paraphrase query lands"
# 카드가 sources로 사람·프로젝트까지 알려준다
assert_file_contains "$repo/cards/flask-secret-key-mismatch.md" "hank · doc-console" "card attributes author/project"

# ④ 카드에 없는 주제 → 활동 폴백으로 건짐
assert_eq "$(cards kafka)" "" "no card for kafka"
assert_contains "$(act_fallback kafka)" "2026-08-03" "activity fallback finds uncarded work"

finish
