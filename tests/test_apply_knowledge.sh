#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
. "$HERE/helpers.sh"

APPLY="$ROOT/scripts/core/apply-knowledge.py"
repo="$(mktemp -d)"

# 1) NEW card 생성 + INDEX 재생성
python3 "$APPLY" "$repo" --date 2026-07-28 <<'RAW'
=== CARD START: ocr-502-size-limit ===
---
tags: [ocr, http-502]
sources: ["[SKT] 2026-07-14"]
---
# OCR 502 — 이미지 크기 제한

## 문제상황
x
## 시도
y
## 해결
z
## 정리
- 입력 크기부터 본다
=== CARD END ===
=== EXCLUDED ===
- 고객 GW whitelist: 단일 고객 이슈
RAW
[ $? -eq 0 ] && pass "new card apply exits 0" || fail "new card apply exits 0"
assert_file_contains "$repo/cards/ocr-502-size-limit.md" "이미지 크기 제한" "new card written"
assert_file_contains "$repo/INDEX.md" "ocr-502-size-limit" "INDEX rebuilt with card"
assert_file_contains "$repo/excluded.md" "단일 고객 이슈" "excluded audit appended"

# 2) APPEND → sources 병합 + ## 사례 섹션 추가
python3 "$APPLY" "$repo" --date 2026-08-04 <<'RAW'
=== APPEND TO: ocr-502-size-limit ===
sources: ["[GSC] 2026-08-04"]
사례: [GSC] 배치 파서에서 동일 502 재현 — 업로드 전 리사이즈로 해결
=== APPEND END ===
RAW
assert_file_contains "$repo/cards/ocr-502-size-limit.md" '[GSC] 2026-08-04' "append merges sources"
assert_file_contains "$repo/cards/ocr-502-size-limit.md" "## 사례" "append creates case section"
assert_file_contains "$repo/cards/ocr-502-size-limit.md" "리사이즈로 해결" "append records case line"

# 3) 기존 slug에 NEW → APPEND 강등 (덮어쓰기 금지)
python3 "$APPLY" "$repo" --date 2026-08-11 <<'RAW'
=== CARD START: ocr-502-size-limit ===
---
tags: [ocr]
sources: ["[LGE-R] 2026-08-11"]
---
# 완전히 다른 제목

## 정리
- 새 교훈
=== CARD END ===
RAW
assert_file_contains "$repo/cards/ocr-502-size-limit.md" "이미지 크기 제한" "existing card not overwritten"
assert_file_contains "$repo/cards/ocr-502-size-limit.md" '[LGE-R] 2026-08-11' "demoted new merges sources"

# 4) 존재하지 않는 slug APPEND → skip (카드 날조 금지), exit 0
out=$(python3 "$APPLY" "$repo" --date 2026-08-12 <<'RAW'
=== APPEND TO: no-such-card ===
사례: 유령 사례
=== APPEND END ===
RAW
)
assert_eq "$?" "0" "missing append target still exits 0"
[ ! -f "$repo/cards/no-such-card.md" ] && pass "missing target not fabricated" || fail "missing target not fabricated"

# 5) NO NEW KNOWLEDGE → no-op
before=$(ls "$repo/cards" | wc -l | tr -d ' ')
printf 'NO NEW KNOWLEDGE\n' | python3 "$APPLY" "$repo"
assert_eq "$?" "0" "no-new-knowledge exits 0"
assert_eq "$(ls "$repo/cards" | wc -l | tr -d ' ')" "$before" "no-op leaves cards untouched"

# 6) 마커 없는 깨진 출력 → exit 2 (형식 가드)
printf 'API Error: Connection closed\n' | python3 "$APPLY" "$repo" 2>/dev/null
assert_eq "$?" "2" "garbage output rejected with exit 2"

# 7) [AC3] PII layer-2: 사번·내부IP는 REDACT, 날짜형 8자리는 보존
python3 "$APPLY" "$repo" --date 2026-08-18 <<'RAW'
=== CARD START: pii-redact-case ===
---
tags: [test]
sources: ["[SKT] 2026-08-18"]
---
# 익명화 2차 방어 테스트

## 문제상황
사번 1109421 계정이 서버 10.20.30.40 과 100.64.50.171 에서 pageId=1008094635 조회 실패. 파일명 20260502_190011.jpg
## 시도
x
## 해결
y
## 정리
z
=== CARD END ===
RAW
assert_eq "$?" "0" "pii card applies with redaction"
card="$repo/cards/pii-redact-case.md"
assert_file_contains "$card" "[REDACTED-ID]" "employee id redacted"
assert_file_contains "$card" "[REDACTED-IP]" "internal ip redacted"
assert_file_contains "$card" "[REDACTED-PAGEID]" "pageId redacted"
grep -q "1109421" "$card" && fail "raw employee id absent" || pass "raw employee id absent"
grep -q "10.20.30.40" "$card" && fail "raw ip absent" || pass "raw ip absent"
assert_file_contains "$card" "20260502_190011.jpg" "date-like digits preserved (no false redact)"

# 8) [AC3] 시크릿 패턴 → fail-closed (exit 3, 카드 미기록)
python3 "$APPLY" "$repo" --date 2026-08-18 2>/dev/null <<'RAW'
=== CARD START: secret-leak-case ===
---
tags: [test]
sources: ["[SKT] 2026-08-18"]
---
# 시크릿

## 문제상황
키 sk-ant-abc123def 노출
## 시도
x
## 해결
y
## 정리
z
=== CARD END ===
RAW
assert_eq "$?" "3" "secret pattern fails closed with exit 3"
[ ! -f "$repo/cards/secret-leak-case.md" ] && pass "secret card not written" || fail "secret card not written"

# 9) [AC3] excluded.md도 스크럽 (감사 텍스트의 사번·시크릿은 REDACT — run은 유지)
python3 "$APPLY" "$repo" --date 2026-08-25 <<'RAW'
NO NEW KNOWLEDGE
=== EXCLUDED ===
- 사번 7654321 계정의 고객 GW 이슈 (키 sk-ant-leak999): 단일 고객
RAW
assert_eq "$?" "0" "excluded-only with pii still exits 0"
assert_file_contains "$repo/excluded.md" "[REDACTED-ID]" "excluded employee id redacted"
assert_file_contains "$repo/excluded.md" "[REDACTED-SECRET]" "excluded secret redacted"
grep -q "7654321\|sk-ant-leak999" "$repo/excluded.md" && fail "raw pii absent from excluded.md" || pass "raw pii absent from excluded.md"

# 10) [AC3] security 리뷰 확인 우회 문자열 → 전부 fail-closed (회귀 고정)
for secret in \
  "sk-proj-abcdefghijklmnopqrstuv" \
  "glpat-abcdefghijklmnop" \
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IksifQ.SflKxwRJSMeKKF2QT4fwpMeJf36P" \
  "postgres://admin:hunter2secret99@db-host:5432/prod" \
  "password: SuperSecretPass123"
do
  python3 "$APPLY" "$repo" --date 2026-09-01 2>/dev/null <<RAW
=== CARD START: bypass-probe ===
---
tags: [test]
sources: ["[X] 2026-09-01"]
---
# probe

## 문제상황
값 $secret 사용
## 시도
x
## 해결
y
## 정리
z
=== CARD END ===
RAW
  assert_eq "$?" "3" "bypass fixture rejected: ${secret%%[:-]*}..."
done
[ ! -f "$repo/cards/bypass-probe.md" ] && pass "no bypass card written" || fail "no bypass card written"

# 10.5) [R1 회귀] sk- 포함 일상 식별자는 시크릿 오탐 금지 (fail-closed 스톨 방지)
python3 "$APPLY" "$repo" --date 2026-09-01 <<'RAW'
=== CARD START: sk-substring-fp ===
---
tags: [test]
sources: ["[X] 2026-09-01"]
---
# sk- 부분문자열 오탐 회귀

## 문제상황
task-management-service-deployment-v2 와 risk-assessment-framework-module 점검, disk-usage-monitoring-dashboard-panel 및 desk-reservation-system-backend-api, brisk-performance-tuning-guideline-doc, task-runner-worker-nodepool 구성
## 시도
x
## 해결
y
## 정리
z
=== CARD END ===
RAW
assert_eq "$?" "0" "common sk- substrings do not fail closed (R1)"
assert_file_contains "$repo/cards/sk-substring-fp.md" "task-management-service-deployment-v2" "identifiers preserved intact"

# 11) [AC3] 연도형 사번 리댁션 + 이메일·내부URL + 진짜 날짜 보존
python3 "$APPLY" "$repo" --date 2026-09-01 <<'RAW'
=== CARD START: pii-round2 ===
---
tags: [test]
sources: ["[X] 2026-09-01"]
---
# 2차 리댁션 검증

## 문제상황
입사연도형 사번 20180042 계정, 담당자 kim@brain-crew.com, 내부 위키 https://wiki.corp.local/page 참조. 처리일 20260714, 공개 문서 https://github.com/org/repo 참고
## 시도
x
## 해결
y
## 정리
z
=== CARD END ===
RAW
card2="$repo/cards/pii-round2.md"
grep -q "20180042" "$card2" && fail "join-year employee id redacted" || pass "join-year employee id redacted"
assert_file_contains "$card2" "[REDACTED-EMAIL]" "email redacted"
assert_file_contains "$card2" "[REDACTED-URL]" "internal url redacted"
assert_file_contains "$card2" "20260714" "genuine YYYYMMDD date preserved"
assert_file_contains "$card2" "https://github.com/org/repo" "public url preserved"

finish
