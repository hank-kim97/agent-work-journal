# claude-work-journal

Claude Code / Codex 세션을 자동으로 요약·기록하는 업무일지 도구.  
에이전트 세션이 끝날 때마다 훅이 발화해 LLM으로 내용을 요약하고, 프로젝트별 마크다운 파일로 축적합니다.

## 특징

- **Claude Code Stop 훅** — 세션 종료 시 자동 실행
- **Codex notify** — `agent-turn-complete` 이벤트마다 자동 실행
- **프로젝트별 라우팅** — CWD prefix 매핑으로 work / private / skip 분류
- **도구·데이터 분리** — 이 레포는 스크립트만 담고, 일지는 별도 데이터 레포에 기록
- **위키 자동 생성** — 선택 cron으로 프로젝트별 README + 인덱스 빌드

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
    build-wiki.py                        LLM 위키 빌더 (project README + INDEX)
    build-wiki.sh                        빌더 + commit/push 래퍼 (cron 진입점)
    install-wiki-cron.sh                 daily cron 등록 스크립트
  adapters/
    claude-code.sh                       Claude Code Stop 훅 어댑터
    codex.sh                             Codex notify 어댑터
```

## 지원 플랫폼

| 플랫폼 | 트리거 | 상세 |
|--------|--------|------|
| Claude Code | Stop 훅 (`~/.claude/settings.json`) | [docs/claude-code.md](docs/claude-code.md) |
| Codex        | notify (`~/.codex/config.toml`)     | [docs/codex.md](docs/codex.md) |

## 위키 자동 생성 (선택)

누적 세션을 LLM으로 압축해 프로젝트별 README와 전체 인덱스를 자동 생성합니다.

```bash
bash scripts/core/install-wiki-cron.sh   # 매일 04:10 cron 등록
```

수동 실행:
```bash
bash scripts/core/build-wiki.sh             # incremental
bash scripts/core/build-wiki.sh --force     # 전체 재빌드
bash scripts/core/build-wiki.sh --project foo
```

## 디버깅

- 훅 실행 로그: `~/.claude/journal-hook.log`
- 위키 빌드 로그: `~/.claude/wiki-build.log`

로그를 실시간으로 보려면:
```bash
tail -f ~/.claude/journal-hook.log
```

## 라이선스

[MIT](LICENSE)
