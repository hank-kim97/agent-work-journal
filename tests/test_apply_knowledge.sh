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

# 7) 내부용 레포: 사번·내부IP·호스트·pageId는 그대로 보존해야 한다 (리댁션 없음)
python3 "$APPLY" "$repo" --date 2026-08-18 <<'RAW'
=== CARD START: internal-detail-preserved ===
---
tags: [test]
sources: ["hank · doc-console · 2026-08-18 · d8c3e962-707b-40e4-a7ca-94f556801c36"]
---
# 내부 식별정보 보존 테스트

## 문제상황
사번 1109421 계정이 서버 10.20.30.40 과 100.64.50.171 에서 pageId=1008094635 조회 실패. 담당 kim@brain-crew.com, 내부 위키 https://wiki.corp.local/page
## 시도
x
## 해결
y
## 정리
z
=== CARD END ===
RAW
assert_eq "$?" "0" "internal-detail card applies"
card="$repo/cards/internal-detail-preserved.md"
assert_file_contains "$card" "1109421" "employee id preserved"
assert_file_contains "$card" "100.64.50.171" "internal ip preserved"
assert_file_contains "$card" "pageId=1008094635" "pageId preserved"
assert_file_contains "$card" "kim@brain-crew.com" "email preserved"
assert_file_contains "$card" "https://wiki.corp.local/page" "internal url preserved"
grep -q "REDACTED" "$card" && fail "no redaction markers" || pass "no redaction markers"
# 추적성: sources에 author·project·session이 담긴다
assert_file_contains "$card" "hank · doc-console" "sources carries author and project"
assert_file_contains "$card" "d8c3e962-707b-40e4-a7ca-94f556801c36" "sources carries session id"

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

# 9) excluded.md: 시크릿만 마스킹, 나머지는 보존 (run은 유지)
python3 "$APPLY" "$repo" --date 2026-08-25 <<'RAW'
NO NEW KNOWLEDGE
=== EXCLUDED ===
- 사번 7654321 채용 후보 검증 (키 sk-ant-leak999 언급): 비기술 판단
RAW
assert_eq "$?" "0" "excluded-only exits 0"
assert_file_contains "$repo/excluded.md" "7654321" "excluded keeps internal detail"
assert_file_contains "$repo/excluded.md" "[REDACTED-SECRET]" "excluded secret masked"
grep -q "sk-ant-leak999" "$repo/excluded.md" && fail "raw secret absent from excluded.md" || pass "raw secret absent from excluded.md"

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

# 11) 재현 스니펫·식별자 전량 보존 (카드 가치의 핵심)
python3 "$APPLY" "$repo" --date 2026-09-01 <<'RAW'
=== CARD START: repro-detail-preserved ===
---
tags: [test]
sources: ["hank · edge · 2026-09-01 · 11111111-2222-3333-4444-555555555555"]
---
# 재현 디테일 보존 검증

## 문제상황
입사연도형 사번 20180042 계정, 처리일 20260714, 로컬 재현 Location: http://localhost:15000/prefix, 게이트웨이 https://dev-iscz.example.com:8007/c-console/
## 시도
x
## 해결
y
## 정리
z
=== CARD END ===
RAW
card2="$repo/cards/repro-detail-preserved.md"
assert_file_contains "$card2" "20180042" "employee id preserved"
assert_file_contains "$card2" "20260714" "date preserved"
assert_file_contains "$card2" "http://localhost:15000/prefix" "localhost repro url preserved"
assert_file_contains "$card2" "https://dev-iscz.example.com:8007/c-console/" "gateway url preserved"
grep -q "REDACTED" "$card2" && fail "no redaction in repro card" || pass "no redaction in repro card"

finish
