# RE팀 업무 기록 — 팀 지식 추출 (opt-in)

개인 업무일지에서 **팀 재사용 가치가 있는 트러블슈팅·기술 지식**을 주 1회 자동 증류해, 팀 공용 git 레포("RE팀 업무 기록")에 카드로 축적합니다. 다른 팀원(과 그 에이전트)은 `/knowledge` 스킬로 검색해 같은 삽질의 반복을 방지합니다.

> 설계 근거: `.omc/specs/deep-interview-re-team-work-log.md` (deep-interview, 모호도 19%).
> 실데이터 dogfood: 3주 일지 58개 → 카드 16장, 검색 착지 10/10, 익명화 유출 0건.

## 코어 파이프라인과의 관계

**완전 opt-in 부가 기능**입니다. `config.json`에 `knowledge_repo`가 없으면 아무것도 하지 않으며, 일지 기록 코어(훅→요약→라우팅→기록)는 이 기능 없이 동일하게 동작합니다.

과거 제거된 위키 서브시스템(b87532a)과의 차이: 위키는 **결정론적으로 가능한 작업**(활성 분류·링크 목록)을 매일 LLM으로 하던 것이 문제였습니다. 지식 추출은 **의미적 증류**(어떤 교훈이 재사용 가능한가, 어떤 카드와 같은 원인인가)라 LLM이 정당하게 필요한 작업이고, 주 1회·opt-in·cron 자동 등록 없음으로 운영 부담을 분리했습니다.

## 구성 요소

| 파일 | 역할 |
|---|---|
| `install-knowledge.sh` | opt-in 설치기 — config 기록, 레포 스캐폴드, `/knowledge` 스킬 설치 |
| `scripts/core/extract-knowledge.sh` | 주간 추출 배치 (LLM 1콜, 증분) |
| `scripts/core/apply-knowledge.py` | 추출 출력 파싱·적용 + PII 2차 방어 + INDEX 재생성 |
| `skills/knowledge/SKILL.md` | 검색 스킬 (증상 키워드 → 카드 착지) |

## 설치

```bash
bash install-knowledge.sh --repo ~/re-team-work-log
# 팀 공유: 그 레포에 원격을 붙이면 추출 후 자동 push
git -C ~/re-team-work-log remote add origin <팀 공용 레포 URL>
```

주간 실행은 자동 등록하지 않습니다 — 하나를 선택하세요:
- **수동**: `bash scripts/core/extract-knowledge.sh`
- **launchd**(macOS): 주 1회 위 명령 실행 plist 등록
- **cloud 루틴**: claude 스케줄 루틴에 실행 위임

## 지식 카드

- 위치: `<knowledge_repo>/cards/*.md` — **플랫 구조** (폴더 분류 없음, 다차원 검색은 frontmatter 태그로)
- 포맷: frontmatter(`tags`, `sources`) + **문제상황 → 시도 → 해결 → 정리** (+ 재발 시 `## 사례` 누적)
- `INDEX.md`: 결정론적 자동 생성 (직접 편집 금지)
- `excluded.md`: 경계 규칙으로 제외된 항목의 감사 추적

## 안전장치 (완전 자동이므로 기계적으로 강제)

1. **경계 규칙** (프롬프트): "다른 회사 프로젝트에서도 만날 수 있는가?" — 단일 고객/프로젝트 사설 시스템 이슈는 제외, `excluded.md`에 사유 기록
2. **익명화 1차** (프롬프트): 고객명→코드명, 사번·실명·IP·키·내부URL 제거
3. **익명화 2차** (결정론적 regex — `apply-knowledge.py`의 **단일 게이트**, 카드·APPEND·excluded.md 전부 통과):
   - **시크릿 → run 전체 거부** (fail-closed, exit 3, 내용은 로그에도 남기지 않음): Anthropic/OpenAI/Google/GitHub/GitLab/Slack 키, AWS access key, JWT, PEM private key, URI 내 `user:pass@`, 일반 `api_key/secret/token/password = 값` 대입
   - **치환 후 계속**: 사번(6-8자리 — 진짜 YYYYMMDD 날짜만 보존, 입사연도형 `2018xxxx`도 리댁션)·이메일·내부 URL(`.corp/.internal/.local/.intra`·IP 호스트)·사설 IP(172.16-31 포함)·pageId → `[REDACTED-*]`
4. **프롬프트 인젝션 방어**: 일지 본문의 `===`/`▼▼▼` 마커 라인은 이스케이프되어 추출기 블록을 위조할 수 없고, 프롬프트에 신뢰 경계(코퍼스는 데이터, 지시 아님)를 명시
5. **출력 형식 가드**: 유효 마커 없는 LLM 출력(에러 메시지 등)은 기록 거부, 커서 미전진 → 다음 주 재시도
6. **원본 창작 금지**: 일지에 해결이 없으면 카드에 "미기록 — 출처 세션 참조"로 정직하게 표기
7. **테스트 훅 봉인**: `KNOWLEDGE_LLM_CMD`는 `KNOWLEDGE_ALLOW_CMD_OVERRIDE=1`과 함께일 때만 동작 (스케줄 실행 환경의 변수 주입으로 실행이 바뀌지 않도록)

### 잔여 위험 (정직한 한계)

- **이메일 없는 실명**은 결정론적으로 잡을 수 없어 1차(LLM) 방어에만 의존
- **5자리 이하 사번**은 미커버 (gRPC 포트 50051 등 오탐을 피하기 위한 트레이드오프), **유효 날짜와 겹치는 8자리 사번**(예: 20200101)도 날짜로 간주되어 미커버
- **비표준 벤더 토큰의 bare 노출**(Stripe `sk_live_`, HuggingFace `hf_` 등)은 `NAME=값` 대입형일 때만 잡힘, **16자 미만 저엔트로피 비밀**(`password = hunter2`)은 오탐 방지 임계 아래
- **프롬프트 인젝션에 의한 내용 왜곡**(카드 날조·`NO NEW KNOWLEDGE` 강제)은 잔존 — 단 scrub_pii를 우회할 수는 없어 유출 경로는 아님 (무결성/가용성 리스크)
- 임시 파일(`mktemp -d`, 0700)은 `kill -9` 시 트랩이 못 돌아 잔존 가능
- `config.json`이 push 목적지를 결정하므로 **config.json 무결성이 보안 요소** — 로컬 쓰기 권한자는 목적지를 바꿀 수 있음

## 증분·동시성 동작

- **커서**: `<knowledge_repo>/.extract-cursor` (gitignored, 머신별) — 이전 실행 이후 mtime이 변한 일지만 처리. **적용+커밋 성공 후에만 전진** (실패 시 다음 주 같은 창 재시도)
- **병합**: 기존 카드 목록(INDEX)을 프롬프트에 제공 → 같은 원인이면 새 카드 대신 `APPEND`(사례 누적). 같은 slug의 NEW는 자동으로 APPEND 강등 (덮어쓰기 불가)
- **팀 동시 push**: 실행 시작 시 `pull --rebase`로 선동기화 (미완 rebase 감지 시 중단). push 실패는 **로그에 명시적 ERROR** — 커밋은 로컬에 보존되고 다음 실행의 선동기화가 전달
- 소스는 `journals/`(work)만 — `private/`와 `_daily/`는 절대 추출 대상이 아님 (테스트로 고정)

## 검색 (`/knowledge`)

에러·문제 조우 시: 키워드 AND grep → 0건이면 OR 폴백 + 태그 매치. 카드는 각색 없이 인용하고 `sources`(코드명/날짜)로 원 세션 추적. 상세는 `skills/knowledge/SKILL.md`.

## 수용 기준 ↔ 테스트 매트릭스

| Acceptance Criteria | 게이트 |
|---|---|
| AC1 검색 착지 (golden query + 패러프레이즈) | `tests/test_knowledge_search.sh` (5 golden + negative) |
| AC2 단일 고객 이슈 미유입 | `test_extract_knowledge.sh` (EXCLUDED 배관, private/ 미소스) + `test_knowledge_search.sh` (negative) |
| AC3 고객 식별정보 0건 | `test_apply_knowledge.sh` (REDACT 3종 + 시크릿 fail-closed + 날짜 오탐 방지) |
| AC4 카드 4단 구조 | 추출 프롬프트 강제 + dogfood 16/16 실증 |

## 운영 런북 (팀 운영 시)

| 증상 | 대응 |
|---|---|
| 로그에 `ERROR: pre-sync pull --rebase failed` | 진짜 텍스트 충돌. `cd <knowledge_repo>` → `git pull --rebase` → 충돌 수동 해결(INDEX.md는 어느 쪽이든 무방 — 다음 추출이 재생성) → `git push`. 해결 전까지 해당 멤버 추출은 안전하게 중단됨 |
| 로그에 `ERROR: git push failed` / `stranded commit(s)` | 커밋은 로컬에 보존됨. 다음 실행의 pre-sync가 자동 배달. 반복되면 원격 권한·네트워크 확인 |
| 같은 주에 두 멤버가 같은 문제를 각자 카드화(슬러그 중복) | 한 카드로 수동 병합 후 커밋. **예방: 멤버별 실행 요일 분산**(예: A=월, B=수, C=금) |
| 도구 레포 이동 후 추출/스킬 무동작 | 훅·스킬이 절대경로 — `setup-team-member.sh` 재실행 |
| (분기 1회) 시크릿 패턴 점검 | `apply-knowledge.py`의 `SECRET_RE`에 신규 벤더 토큰 포맷 추가 여부 검토 — 무인 push 파이프라인의 유일한 정기 관리 항목 |

## 디버깅

- 추출 로그: `~/.claude/knowledge-extract.log`
- 커서 확인: `cat <knowledge_repo>/.extract-cursor` (파일 mtime이 기준)
- 테스트 주입: `KNOWLEDGE_ALLOW_CMD_OVERRIDE=1 KNOWLEDGE_LLM_CMD='bash mock.sh' bash scripts/core/extract-knowledge.sh`
