# Claude Code 연동 상세

## 개요

Claude Code의 **Stop 훅**을 통해 세션 종료 시 자동으로 일지를 기록합니다.  
어댑터 스크립트: `scripts/adapters/claude-code.sh`

## 설치

```bash
bash install.sh --agent claude
```

또는 수동으로 두 플랫폼을 함께 설치:

```bash
bash install.sh --agent both
```

## 내부 동작

`install.sh --agent claude`는 `~/.claude/settings.json`의 `hooks.Stop` 배열에 다음 항목을 추가합니다:

```json
{
  "matcher": "",
  "hooks": [
    {
      "type": "command",
      "command": "bash <TOOL_DIR>/scripts/adapters/claude-code.sh"
    }
  ]
}
```

`<TOOL_DIR>`은 이 레포를 clone한 실제 경로로 대체됩니다.

## 수동 배선 예시

`~/.claude/settings.json`을 직접 편집하는 경우:

```json
{
  "hooks": {
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/tools/claude-work-journal/scripts/adapters/claude-code.sh"
          }
        ]
      }
    ]
  }
}
```

`hooks.Stop`이 이미 다른 항목을 포함하고 있다면 배열에 객체를 추가하면 됩니다. `install.sh`는 중복을 자동으로 방지합니다.

## Stop 훅 입력 스키마

Claude Code는 Stop 훅을 실행할 때 stdin으로 JSON을 전달합니다:

```json
{
  "session_id": "abc123",
  "transcript_path": "/path/to/transcript.jsonl",
  "cwd": "/Users/.../projects/my-project"
}
```

| 필드 | 설명 |
|------|------|
| `session_id` | 세션 식별자. 같은 세션의 섹션을 덮어쓸 때 사용 |
| `transcript_path` | 전체 대화 기록 파일 경로 (JSONL) |
| `cwd` | 세션 시작 시 작업 디렉토리. 라우팅 분류 기준 |

어댑터는 이 JSON을 stdin에서 읽어 각 필드를 추출합니다.

## 사소한 세션 건너뛰기

아래 조건 중 하나라도 해당하면 일지를 기록하지 않고 즉시 종료합니다:

1. `transcript_path`가 없거나 파일이 존재하지 않는 경우
2. `session_id`가 비어 있는 경우
3. transcript에서 `"role":"user"` 줄이 **2개 미만**인 경우 (사용자 발화가 거의 없는 세션)

## 재귀 가드

어댑터 자체가 Claude Code 세션에서 실행될 경우 무한 루프가 발생할 수 있습니다.  
이를 방지하기 위해 환경 변수 `CLAUDE_JOURNAL_RUNNING`을 사용합니다:

```bash
if [ -n "${CLAUDE_JOURNAL_RUNNING:-}" ]; then exit 0; fi
```

어댑터는 서브셸 내에서 `export CLAUDE_JOURNAL_RUNNING=1`을 설정한 뒤 요약과 기록 작업을 수행합니다. 이미 이 변수가 설정된 환경에서 훅이 재발화되면 즉시 종료됩니다.

## 비동기 실행

어댑터는 Claude Code의 응답 지연을 막기 위해 서브셸을 **백그라운드**(`&`)로 실행하고 `disown`합니다. 훅 자체는 거의 즉시 exit 0을 반환합니다.

## 디버깅

모든 실행 로그(stdout + stderr)는 `~/.claude/journal-hook.log`에 기록됩니다.

```bash
tail -f ~/.claude/journal-hook.log
```

로그에 오류가 없고 일지 파일도 생성되지 않는다면:
- 세션에서 사용자 발화가 2회 미만일 가능성이 높습니다 (사소한 세션 건너뛰기).
- `config.json`의 `rules`에서 해당 CWD가 `skip`으로 분류되고 있는지 확인하세요.
