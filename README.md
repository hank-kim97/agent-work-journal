# claude-work-journal

Claude Code / Codex 세션을 자동으로 요약·기록하는 업무일지 도구.  
에이전트가 응답 턴을 마칠 때마다 훅이 발화해 LLM으로 transcript를 요약하고, 프로젝트별 마크다운 파일로 축적합니다.

같은 세션의 기록은 `session_id` 기준으로 **덮어쓰기**되므로, 턴이 진행될수록 해당 세션의 일지 항목이 최신 상태로 갱신됩니다. 세션을 언제 닫아도(또는 강제 종료돼도) 마지막 턴까지의 기록이 이미 남아 있습니다.

## 특징

- **Claude Code Stop 훅** — 응답 턴 종료 시마다 자동 실행
- **Codex notify** — `agent-turn-complete` 이벤트마다 자동 실행
- **세션 단위 덮어쓰기** — 매 턴 재요약해 같은 세션 항목을 최신화 (중복 누적 없음)
- **프롬프트 캐시 친화** — recap식 append-only 프롬프트 구조로 매 턴 요약 비용 절감 ([상세](docs/claude-code.md#프롬프트-캐시-활용-recap식))
- **프로젝트별 라우팅** — CWD prefix 매핑으로 work / private / skip 분류
- **도구·데이터 분리** — 이 레포는 스크립트만 담고, 일지는 별도 데이터 레포에 기록

## 빠른 시작

```bash
git clone https://github.com/your-username/claude-work-journal <TOOL_DIR>
cd <TOOL_DIR>
cp config.example.json config.json
# config.json에서 디렉토리 매핑과 journal_dir를 편집 (아래 참조)
bash install.sh
```

`install.sh`는 연결할 에이전트(Claude Code / Codex / 둘 다)를 묻습니다.  
`--agent claude|codex|both` 플래그로 비대화식으로 실행할 수 있습니다.

## 팀원 온보딩 (5분, 1명령)

팀에 합류하는 멤버는 위 단계 대신 래퍼 하나로 끝낼 수 있습니다:

```bash
git clone <도구 레포 URL> ~/tools/agent-work-journal
cd ~/tools/agent-work-journal
bash setup-team-member.sh \
  --work-prefix ~/Documents/braincrew \
  --knowledge-remote git@github.com:<org>/re-team-work-log.git
```

config 배선 → 훅 설치 → 개인 데이터 레포 init → 팀 지식 레포 clone → `/knowledge` 스킬 설치까지 한 번에 처리하며, 재실행해도 안전합니다(멱등). 주간 추출 스케줄만 출력 안내에서 선택하면 됩니다.

> ⚠️ **도구 디렉토리를 이동/이름변경하면** 훅과 스킬이 절대경로라 조용히 끊깁니다 — `setup-team-member.sh`를 재실행하세요.

## 도구·데이터 분리

이 레포는 **스크립트만** 담습니다. 실제 일지(markdown 파일)는 별도 데이터 레포에 기록됩니다.

데이터 레포 경로를 지정하는 방법 (우선순위 순):

1. 환경 변수: `export WORK_JOURNAL_DIR=~/work-journal-data`
2. `config.json`의 `journal_dir` 키:
   ```json
   { "journal_dir": "~/work-journal-data" }
   ```

데이터 레포가 없으면 스크립트 디렉토리 자체에 `journals/`와 `private/`가 생성됩니다.

## config.json 구조

```json
{
  "journal_dir": "~/work-journal-data",
  "rules": [
    {"prefix": "~/projects/my-work-project", "category": "work"},
    {"prefix": "~/personal",                 "category": "private"}
  ],
  "default": "private"
}
```

`rules`는 위에서 아래로 평가되어 **첫 매치**를 사용합니다. 매치 없으면 `default` 값(기본 `private`)을 사용합니다.

## 카테고리 라우팅

| category  | 저장 위치                      | git push |
|-----------|-------------------------------|----------|
| `work`    | `journals/<project>/<date>.md` | ✅       |
| `private` | `private/<project>/<date>.md`  | ❌ (gitignored) |
| `skip`    | (저장 안 함)                   | ❌       |

project 이름은 CWD의 git toplevel basename에서 자동 추출됩니다.  
rule에 `"project": "이름"`을 명시하면 override할 수 있습니다.

## 파일 구조

```
install.sh                               에이전트 훅 설치 스크립트
config.example.json                      설정 파일 템플릿
scripts/
  lib/
    resolve-paths.sh                     TOOL_DIR / JOURNAL_DIR / CONFIG_PATH 결정
    summarize.sh                         LLM 요약 호출 래퍼
  core/
    classify-cwd.py                      CWD → {category, project} 분류
    update-section.py                    세션 단위 섹션 갱신
    update-daily-index.py                날짜별 크로스 프로젝트 인덱스 갱신
    write-entry.sh                       요약 → 일지 파일 기록 + commit/push
  adapters/
    claude-code.sh                       Claude Code Stop 훅 어댑터
    codex.sh                             Codex notify 어댑터
```

## 지원 플랫폼

| 플랫폼 | 트리거 | 상세 |
|--------|--------|------|
| Claude Code | Stop 훅 (`~/.claude/settings.json`) | [docs/claude-code.md](docs/claude-code.md) |
| Codex        | notify (`~/.codex/config.toml`)     | [docs/codex.md](docs/codex.md) |

## 팀 지식 추출 — RE팀 업무 기록 (선택)

개인 일지에서 팀 재사용 지식(트러블슈팅 카드)을 주 1회 자동 증류해 팀 공용 레포에 축적하고, `/knowledge` 스킬로 검색합니다. 완전 opt-in — 미설정 시 코어에 영향 없음.

```bash
bash install-knowledge.sh --repo ~/re-team-work-log
```

상세: [docs/knowledge.md](docs/knowledge.md)

## 디버깅

- 훅 실행 로그: `~/.claude/journal-hook.log`
- 지식 추출 로그: `~/.claude/knowledge-extract.log`

로그를 실시간으로 보려면:
```bash
tail -f ~/.claude/journal-hook.log
```

## 라이선스

[MIT](LICENSE)
