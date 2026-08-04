#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
. "$HERE/helpers.sh"

EXTRACT="$ROOT/scripts/core/extract-knowledge.sh"
export KNOWLEDGE_ALLOW_CMD_OVERRIDE=1   # test-hook opt-in (security #6)
export WORK_JOURNAL_CONFIG="$(mktemp -u)"
trap 'rm -f "$WORK_JOURNAL_CONFIG"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

SID=aaaaaaaa-1111-2222-3333-444444444444
data="$(mktemp -d)"; krepo="$(mktemp -d)/re-team-work-log"
mkdir -p "$data/journals/demo" "$krepo/cards"
( cd "$krepo" && git init -q -b main && touch cards/.gitkeep && git add -A \
  && git -c commit.gpgsign=false commit -qm init )
cat > "$data/journals/demo/2026-07-20.md" <<MD
# demo — 2026-07-20

<!-- session:$SID -->
### OCR 502 원인 규명
- 1MB 초과 이미지에서 502, 크기 프로파일로 확인
<!-- /session:$SID -->
MD

# 2단계 mock: 프롬프트를 보고 triage/card 단계를 구분해 응답한다
mkdir -p "$(dirname "$WORK_JOURNAL_CONFIG")"
MOCKD="$(mktemp -d)"
make_mock() {  # make_mock <path> <triage-response-file> <card-response-file>
  cat > "$1" <<EOF
#!/usr/bin/env bash
p=\$(cat)
case "\$p" in
  *"지식 추출 **분류자**"*) cat "$2" ;;
  *) cat "$3" ;;
esac
EOF
  chmod +x "$1"
}
cat > "$MOCKD/triage.ok" <<EOF
=== SESSION: $SID ===
project: demo
date: 2026-07-20
topics: OCR 업스트림 크기 제한
keywords: OCR 502 크기 이미지
deep: yes
=== END SESSION ===
EOF
cat > "$MOCKD/card.ok" <<'EOF'
=== CARD START: ocr-502-size ===
---
tags: [ocr, upstage, http-502]
sources: ["hank · demo · 2026-07-20 · aaaaaaaa-1111-2222-3333-444444444444"]
---
# OCR 502 — 크기 제한

## 문제상황
서버 100.64.50.171 경유 요청이 502
## 시도
크기 프로파일 확인
## 해결
1MB 초과 리사이즈
## 검증 상태
검증됨
## 정리
- 입력 크기부터 본다
=== CARD END ===
EOF
make_mock "$MOCKD/ok" "$MOCKD/triage.ok" "$MOCKD/card.ok"

# 1) knowledge_repo 미설정 → exit 0, 무부작용
cat >"$WORK_JOURNAL_CONFIG" <<JSON
{"journal_dir": "$data", "rules": [], "default": "private"}
JSON
out=$(bash "$EXTRACT"); rc=$?
assert_eq "$rc" "0" "unconfigured repo exits 0"
[ -z "$out" ] && pass "unconfigured repo is silent" || fail "unconfigured repo is silent"

cat >"$WORK_JOURNAL_CONFIG" <<JSON
{"journal_dir": "$data", "knowledge_repo": "$krepo", "author": "hank", "rules": [], "default": "private"}
JSON

# 2) triage 출력이 깨지면 exit 1 + 커서 미생성
bad=$(mock_summarizer "API Error: Connection closed")
KNOWLEDGE_LLM_CMD="$bad" bash "$EXTRACT" >/dev/null 2>&1
assert_eq "$?" "1" "garbage triage output exits 1"
[ ! -f "$krepo/.extract-cursor" ] && pass "cursor not advanced on failure" || fail "cursor not advanced on failure"

# 3) 정상 2단계 e2e — 카드 기록·INDEX·커밋·커서
KNOWLEDGE_LLM_CMD="$MOCKD/ok" bash "$EXTRACT" >/dev/null
assert_eq "$?" "0" "two-stage happy path exits 0"
assert_file_contains "$krepo/cards/ocr-502-size.md" "크기 제한" "card written"
assert_file_contains "$krepo/INDEX.md" "ocr-502-size" "INDEX regenerated"
[ -f "$krepo/.extract-cursor" ] && pass "cursor advanced" || fail "cursor advanced"
case "$(git -C "$krepo" log --oneline)" in
  *"knowledge: extraction"*) pass "knowledge repo committed" ;;
  *) fail "knowledge repo committed" ;;
esac

# 4) 내부용 레포: 내부 IP·식별정보는 리댁션 없이 보존
assert_file_contains "$krepo/cards/ocr-502-size.md" "100.64.50.171" "internal ip preserved"
grep -q "REDACTED" "$krepo/cards/ocr-502-size.md" && fail "no redaction markers" || pass "no redaction markers"
# sources에 작성자·세션ID가 남아 추적 가능
assert_file_contains "$krepo/cards/ocr-502-size.md" "hank · demo" "sources carries author/project"
assert_file_contains "$krepo/cards/ocr-502-size.md" "$SID" "sources carries session id"

# 5) 변경 없음 → LLM 미호출
sentinel="$MOCKD/called"
printf '#!/usr/bin/env bash\ntouch %s\ncat >/dev/null\necho "NO NEW KNOWLEDGE"\n' "$sentinel" > "$MOCKD/sent"
chmod +x "$MOCKD/sent"
KNOWLEDGE_LLM_CMD="$MOCKD/sent" bash "$EXTRACT" >/dev/null
assert_eq "$?" "0" "no-change run exits 0"
[ ! -f "$sentinel" ] && pass "LLM not called when nothing changed" || fail "LLM not called when nothing changed"

# 6) private/ 은 추출 소스가 아니다
mkdir -p "$data/private/personal"
printf '# personal\n\n### 개인\n- 개인 작업\n' > "$data/private/personal/2026-07-21.md"
KNOWLEDGE_LLM_CMD="$MOCKD/sent" bash "$EXTRACT" >/dev/null
[ ! -f "$sentinel" ] && pass "private/ never reaches extractor" || fail "private/ never reaches extractor"

# 7) triage가 NO NEW KNOWLEDGE → 카드 없음, 커서만 전진
sleep 1; printf -- '- 사소한 추가\n' >> "$data/journals/demo/2026-07-20.md"
before=$(ls "$krepo/cards" | wc -l | tr -d ' ')
KNOWLEDGE_LLM_CMD="$MOCKD/sent" bash "$EXTRACT" >/dev/null
assert_eq "$?" "0" "no-new-knowledge exits 0"
assert_eq "$(ls "$krepo/cards" | wc -l | tr -d ' ')" "$before" "no cards added"

# 8) EXCLUDED 배관 (경계 규칙 감사)
sleep 1; printf -- '- 채용 후보 검토\n' >> "$data/journals/demo/2026-07-20.md"
cat > "$MOCKD/triage.excl" <<'EOF'
NO NEW KNOWLEDGE
=== EXCLUDED ===
- 채용 후보 검토: 비기술 판단
EOF
make_mock "$MOCKD/excl" "$MOCKD/triage.excl" "$MOCKD/card.ok"
KNOWLEDGE_LLM_CMD="$MOCKD/excl" bash "$EXTRACT" >/dev/null 2>&1
assert_file_contains "$krepo/excluded.md" "비기술 판단" "boundary exclusion audited"

# 9) 시크릿 → fail closed (카드 미기록, 커서 유지)
sleep 1; printf -- '- 키 관련 작업\n' >> "$data/journals/demo/2026-07-20.md"
cursor_before=$(stat -f %m "$krepo/.extract-cursor" 2>/dev/null || echo 0)
cat > "$MOCKD/card.secret" <<'EOF'
=== CARD START: secret-card ===
---
tags: [test]
sources: ["hank · demo · 2026-07-20 · x"]
---
# 시크릿

## 문제상황
키 sk-ant-abc123def456 노출
## 시도
x
## 해결
y
## 검증 상태
검증됨
## 정리
z
=== CARD END ===
EOF
make_mock "$MOCKD/secret" "$MOCKD/triage.ok" "$MOCKD/card.secret"
KNOWLEDGE_LLM_CMD="$MOCKD/secret" bash "$EXTRACT" >/dev/null 2>&1
assert_eq "$?" "1" "secret aborts with exit 1"
[ ! -f "$krepo/cards/secret-card.md" ] && pass "secret card not written" || fail "secret card not written"
cursor_after=$(stat -f %m "$krepo/.extract-cursor" 2>/dev/null || echo 0)
assert_eq "$cursor_after" "$cursor_before" "cursor kept on secret abort"

# 10) 트랜스크립트 없는 세션 → 일지 폴백으로 graceful (deep=yes여도)
sleep 1; printf -- '- 또 다른 이슈\n' >> "$data/journals/demo/2026-07-20.md"
cat > "$MOCKD/card2" <<'EOF'
=== CARD START: fallback-card ===
---
tags: [test]
sources: ["hank · demo · 2026-07-20 · x"]
---
# 폴백 카드

## 문제상황
a
## 시도
b
## 해결
c
## 검증 상태
진단만(해결 미도출)
## 정리
d
=== CARD END ===
EOF
make_mock "$MOCKD/fallback" "$MOCKD/triage.ok" "$MOCKD/card2"
KNOWLEDGE_LLM_CMD="$MOCKD/fallback" bash "$EXTRACT" >/dev/null 2>&1
assert_eq "$?" "0" "missing transcript degrades gracefully"
assert_file_contains "$krepo/cards/fallback-card.md" "폴백 카드" "card still produced from journal"

# 11) 같은 실행 안에서 앞선 세션이 만든 카드가 다음 세션 프롬프트에 보여야 한다
#     (안 보이면 같은 원인이 세션마다 새 슬러그로 중복 생성된다 — 실측 45장 중 16장)
sleep 1; printf -- '- 중복 방지 검증\n' >> "$data/journals/demo/2026-07-20.md"
SID2=bbbbbbbb-1111-2222-3333-444444444444
cat > "$MOCKD/triage.two" <<EOF
=== SESSION: $SID ===
project: demo
date: 2026-07-20
topics: 첫 세션 주제
keywords: OCR 502
deep: no
=== END SESSION ===
=== SESSION: $SID2 ===
project: demo
date: 2026-07-20
topics: 둘째 세션 주제
keywords: OCR 502
deep: no
=== END SESSION ===
EOF
cat > "$MOCKD/two" <<EOF
#!/usr/bin/env bash
p=\$(cat)
case "\$p" in
  *"지식 추출 **분류자**"*) cat "$MOCKD/triage.two" ;;
  *"$SID2"*) printf '%s\n' "\$p" > "$MOCKD/second-prompt.txt"; echo "NO NEW KNOWLEDGE" ;;
  *) cat "$MOCKD/card.ok" ;;
esac
EOF
chmod +x "$MOCKD/two"
rm -f "$MOCKD/second-prompt.txt"
KNOWLEDGE_LLM_CMD="$MOCKD/two" bash "$EXTRACT" >/dev/null 2>&1
assert_file_contains "$MOCKD/second-prompt.txt" "이번 실행에서 방금 작성된 카드" "in-run card list reaches the next session"
assert_file_contains "$MOCKD/second-prompt.txt" "ocr-502-size" "the earlier session's slug is visible for APPEND"

finish
