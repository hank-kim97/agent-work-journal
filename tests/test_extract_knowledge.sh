#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
. "$HERE/helpers.sh"

EXTRACT="$ROOT/scripts/core/extract-knowledge.sh"
export KNOWLEDGE_ALLOW_CMD_OVERRIDE=1   # test-hook opt-in (security #6)

# isolated temp config — never touches the real config.json
export WORK_JOURNAL_CONFIG="$(mktemp -u)"
trap 'rm -f "$WORK_JOURNAL_CONFIG"' EXIT

data="$(mktemp -d)"; krepo="$(mktemp -d)/re-team-work-log"
mkdir -p "$data/journals/demo" "$krepo/cards"
( cd "$krepo" && git init -q && git config user.email t@t && git config user.name t \
  && git add -A 2>/dev/null; git -c commit.gpgsign=false commit -qm init --allow-empty )
printf '# demo — 2026-07-20\n\n### 세션\n- OCR 502 원인 규명: 1MB 크기 제한\n' > "$data/journals/demo/2026-07-20.md"

# 1) knowledge_repo 미설정 → exit 0, 무부작용
cat >"$WORK_JOURNAL_CONFIG" <<JSON
{"journal_dir": "$data", "rules": [], "default": "private"}
JSON
out=$(bash "$EXTRACT"); rc=$?
assert_eq "$rc" "0" "unconfigured repo exits 0"
[ -z "$out" ] && pass "unconfigured repo is silent" || fail "unconfigured repo is silent (got: $out)"

# 이후 테스트용 config (knowledge_repo 설정)
cat >"$WORK_JOURNAL_CONFIG" <<JSON
{"journal_dir": "$data", "knowledge_repo": "$krepo", "rules": [], "default": "private"}
JSON

# 2) 깨진 LLM 출력 → exit 1 + 커서 미생성 (재시도 보장)
mock_bad=$(mock_summarizer "API Error: Connection closed")
KNOWLEDGE_LLM_CMD="$mock_bad" bash "$EXTRACT" >/dev/null 2>&1
assert_eq "$?" "1" "garbage LLM output exits 1"
[ ! -f "$krepo/.extract-cursor" ] && pass "cursor not advanced on failure" || fail "cursor not advanced on failure"

# 3) 시크릿 유출 → layer-2 fail-closed (extract exit 1, 카드·커서 없음)
mock_secret=$(mock_summarizer '=== CARD START: secret-card ===
---
tags: [test]
sources: ["[SKT] 2026-07-20"]
---
# 시크릿 유출 카드

## 문제상황
키 sk-ant-abc123def 가 노출됨
## 시도
x
## 해결
y
## 정리
z
=== CARD END ===')
KNOWLEDGE_LLM_CMD="$mock_secret" bash "$EXTRACT" >/dev/null 2>&1
assert_eq "$?" "1" "secret aborts extract with exit 1"
[ ! -f "$krepo/cards/secret-card.md" ] && pass "secret card not written" || fail "secret card not written"
[ ! -f "$krepo/.extract-cursor" ] && pass "cursor kept on secret abort" || fail "cursor kept on secret abort"

# 4) 정상 e2e: 카드 기록 + INDEX + git commit + 커서 생성
mock_ok=$(mock_summarizer '=== CARD START: ocr-502-size ===
---
tags: [ocr, http-502]
sources: ["[SKT] 2026-07-20"]
---
# OCR 502 — 크기 제한

## 문제상황
a
## 시도
b
## 해결
c
## 정리
- d
=== CARD END ===')
KNOWLEDGE_LLM_CMD="$mock_ok" bash "$EXTRACT" >/dev/null
assert_eq "$?" "0" "happy path exits 0"
assert_file_contains "$krepo/cards/ocr-502-size.md" "크기 제한" "card written to knowledge repo"
assert_file_contains "$krepo/INDEX.md" "ocr-502-size" "INDEX regenerated"
[ -f "$krepo/.extract-cursor" ] && pass "cursor advanced on success" || fail "cursor advanced on success"
# NOTE: no `git log | grep -q` here — grep -q exits on first match and the
# still-writing git log gets SIGPIPE, which pipefail turns into failure.
case "$(git -C "$krepo" log --oneline)" in
  *"weekly extraction"*) pass "knowledge repo committed" ;;
  *) fail "knowledge repo committed" ;;
esac

# 4.5) 내부 IP 등 PII → redact-and-continue (스톨 방지, security #7)
sleep 1; printf -- '- 서버 100.64.50.171 진단 내용 추가\n' >> "$data/journals/demo/2026-07-20.md"
mock_ip=$(mock_summarizer '=== CARD START: ip-redact-card ===
---
tags: [network]
sources: ["[SKT] 2026-07-20"]
---
# IP 리댁션 카드

## 문제상황
서버 100.64.50.171 에서 발생
## 시도
x
## 해결
y
## 정리
z
=== CARD END ===')
KNOWLEDGE_LLM_CMD="$mock_ip" bash "$EXTRACT" >/dev/null
assert_eq "$?" "0" "pii redact-and-continue exits 0"
assert_file_contains "$krepo/cards/ip-redact-card.md" "[REDACTED-IP]" "internal ip redacted in card"
grep -q "100.64.50.171" "$krepo/cards/ip-redact-card.md" && fail "raw ip absent" || pass "raw ip absent"

# 5) 변경 없음 → LLM 미호출 (센티널로 확인), exit 0
sentinel="$(mktemp -d)/called"
mock_dir="$(mktemp -d)"; mock_sentinel="$mock_dir/mock"
printf '#!/usr/bin/env bash\ntouch %s\ncat >/dev/null\necho "NO NEW KNOWLEDGE"\n' "$sentinel" > "$mock_sentinel"
chmod +x "$mock_sentinel"
KNOWLEDGE_LLM_CMD="$mock_sentinel" bash "$EXTRACT" >/dev/null
assert_eq "$?" "0" "no-change run exits 0"
[ ! -f "$sentinel" ] && pass "LLM not called when nothing changed" || fail "LLM not called when nothing changed"

# 5.5) [AC2] private/ 일지는 추출 소스가 아님 (변경돼도 LLM 미호출)
mkdir -p "$data/private/personal"
printf '# personal\n\n### 개인 세션\n- 개인 작업\n' > "$data/private/personal/2026-07-21.md"
sentinel2="$(mktemp -d)/called2"
mock_priv="$mock_dir/mock-priv"
printf '#!/usr/bin/env bash\ntouch %s\ncat >/dev/null\necho "NO NEW KNOWLEDGE"\n' "$sentinel2" > "$mock_priv"
chmod +x "$mock_priv"
KNOWLEDGE_LLM_CMD="$mock_priv" bash "$EXTRACT" >/dev/null
[ ! -f "$sentinel2" ] && pass "private/ journals never reach extractor" || fail "private/ journals never reach extractor"

# 5.6) [AC2] 경계 규칙 배관: EXCLUDED-only 출력 → 카드 0, excluded.md 감사 기록
sleep 1; printf -- '- 고객사 GW 403 진단\n' >> "$data/journals/demo/2026-07-20.md"
mock_excl=$(mock_summarizer '=== EXCLUDED ===
- 고객사 API 게이트웨이 whitelist 정책: 단일 고객 이슈 — 경계 규칙 제외')
cards_before=$(ls "$krepo/cards" | wc -l | tr -d ' ')
KNOWLEDGE_LLM_CMD="$mock_excl" bash "$EXTRACT" >/dev/null 2>&1
cards_n=$(ls "$krepo/cards" | wc -l | tr -d ' ')
assert_eq "$cards_n" "$cards_before" "excluded-only run creates no cards"
assert_file_contains "$krepo/excluded.md" "단일 고객 이슈" "boundary exclusion audited"

# 5.7) fresh clone에 cards/ 없음(빈 디렉토리 미추적) → 자동 생성 후 정상 동작
kb2="$(mktemp -d)/kb2"
git clone -q "$krepo" "$kb2" 2>/dev/null
rm -rf "$kb2/cards"   # 빈 디렉토리가 clone에서 사라진 상황 재현
data2="$(mktemp -d)"; mkdir -p "$data2/journals/p2"
printf '# p2\n\n### s\n- 원인 규명\n' > "$data2/journals/p2/2026-07-21.md"
cat >"$WORK_JOURNAL_CONFIG" <<JSON
{"journal_dir": "$data2", "knowledge_repo": "$kb2", "rules": [], "default": "private"}
JSON
KNOWLEDGE_LLM_CMD="$mock_ok" bash "$EXTRACT" >/dev/null 2>&1
assert_eq "$?" "0" "clone without cards/ self-heals"
[ -f "$kb2/cards/ocr-502-size.md" ] && pass "card written after self-heal" || fail "card written after self-heal"

# 5.8) 미배달 커밋(과거 push 실패분)이 NO-NEW 주간의 pre-sync에서 배달됨
origin_bare="$(mktemp -d)/origin.git"
git init -q --bare "$origin_bare"
# clone은 이미 origin(원본 krepo)을 가짐 → 팀 공용 bare로 교체
( cd "$kb2" && git remote set-url origin "$origin_bare" \
  && git push -q origin "HEAD:main" 2>/dev/null \
  && git branch -q --set-upstream-to=origin/main 2>/dev/null )
( cd "$kb2" && printf 'stranded\n' > cards/stranded.md && git add cards/ \
  && git -c commit.gpgsign=false commit -qm "knowledge: stranded" )
( cd "$origin_bare" && git update-ref -d refs/heads/nonexistent 2>/dev/null )  # no-op: origin은 뒤처진 상태
sleep 1; printf -- '- 추가\n' >> "$data2/journals/p2/2026-07-21.md"
mock_noop2="$mock_dir/mock-noop2"
printf '#!/usr/bin/env bash\ncat >/dev/null\necho "NO NEW KNOWLEDGE"\n' > "$mock_noop2"; chmod +x "$mock_noop2"
KNOWLEDGE_LLM_CMD="$mock_noop2" bash "$EXTRACT" >/dev/null 2>&1
check=$(mktemp -d); git clone -q "$origin_bare" "$check/c" 2>/dev/null
[ -f "$check/c/cards/stranded.md" ] && pass "stranded commit delivered on no-new week" \
  || fail "stranded commit delivered on no-new week"

# config 복원 (이후 테스트는 원래 krepo 사용)
cat >"$WORK_JOURNAL_CONFIG" <<JSON
{"journal_dir": "$data", "knowledge_repo": "$krepo", "rules": [], "default": "private"}
JSON

# 6) NO NEW KNOWLEDGE → 커서만 전진, 커밋 없음
sleep 1; printf -- '- 사소한 추가\n' >> "$data/journals/demo/2026-07-20.md"
before_commits=$(cd "$krepo" && git rev-list --count HEAD)
KNOWLEDGE_LLM_CMD="$mock_sentinel" bash "$EXTRACT" >/dev/null
assert_eq "$?" "0" "no-new-knowledge exits 0"
[ -f "$sentinel" ] && pass "LLM called for changed file" || fail "LLM called for changed file"
after_commits=$(cd "$krepo" && git rev-list --count HEAD)
assert_eq "$after_commits" "$before_commits" "no commit on no-new-knowledge"

finish
