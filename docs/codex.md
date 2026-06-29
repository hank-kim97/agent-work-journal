# Codex 연동 상세

> codex-cli 0.134.0 기준으로 검증된 내용입니다.

## 개요

Codex의 **notify** 콜백을 통해 에이전트 턴 완료 시 자동으로 일지를 기록합니다.  
어댑터 스크립트: `scripts/adapters/codex.sh`

## 설치

```bash
bash install.sh --agent codex
```

또는 수동으로 두 플랫폼을 함께 설치:

```bash
bash install.sh --agent both
```

## 내부 동작

`install.sh --agent codex`는 `~/.codex/config.toml`에 다음 줄을 추가합니다:

```toml
notify = ["bash", "<TOOL_DIR>/scripts/adapters/codex.sh"]
```

`<TOOL_DIR>`은 이 레포를 clone한 실제 경로로 대체됩니다.

## 수동 배선 예시

`~/.codex/config.toml`을 직접 편집하는 경우:

```toml
notify = ["bash", "/home/yourname/tools/claude-work-journal/scripts/adapters/codex.sh"]
```

기존에 다른 `notify` 라인이 있다면 `install.sh`가 교체합니다. 단일 notify 커맨드만 지원됩니다.

## notify 페이로드 스키마

Codex는 어댑터를 실행할 때 JSON 페이로드를 **argv[1]**으로 전달합니다:

```json
{
  "type": "agent-turn-complete",
  "thread-id": "...",
  "turn-id": "...",
  "cwd": "/Users/.../projects/my-project",
  "client": "...",
  "input-messages": [...],
  "last-assistant-message": "..."
}
```

| 필드 | 설명 |
|------|------|
| `type` | 이벤트 종류. 어댑터는 `agent-turn-complete`만 처리 |
| `cwd` | 세션 작업 디렉토리 (폴백으로 사용) |
| `thread-id` | 세션 식별자 힌트 (rollout 파일이 우선) |

## 이벤트 게이팅

어댑터는 `type` 필드를 먼저 확인하고 `agent-turn-complete`가 아니면 즉시 종료합니다:

```bash
TYPE=$(printf '%s' "$NOTIFY" | python3 -c "import json,sys
try: print(json.load(sys.stdin).get('type',''))
except Exception: pass" 2>/dev/null)
[ "$TYPE" = "agent-turn-complete" ] || exit 0
```

## rollout 파일에서 cwd / session-id 추출

notify 페이로드의 `cwd`는 폴백으로만 사용하고, 기본적으로는 **rollout 파일의 session_meta 라인**에서 더 신뢰할 수 있는 값을 읽습니다.

### 파일 위치

```
$CODEX_HOME/sessions/YYYY/MM/DD/rollout-<ts>-<uuid>.jsonl
```

`CODEX_HOME`의 기본값은 `~/.codex`입니다. 환경 변수로 override할 수 있습니다:

```bash
export CODEX_HOME=/custom/path/.codex
```

가장 최근 rollout 파일은 `ls -t`로 탐색합니다:

```bash
ROLLOUT=$(ls -t "$CODEX_HOME"/sessions/*/*/*/rollout-*.jsonl 2>/dev/null | head -1)
```

### session_meta 라인

rollout JSONL 파일의 **첫 번째 줄**이 session_meta입니다:

```json
{
  "timestamp": "2026-06-27T02:30:59.672Z",
  "type": "session_meta",
  "payload": {
    "id": "019f06ea-3133-71b1-a023-8c8aa403aaa8",
    "cwd": "/Users/.../projects/my-project",
    "originator": "Codex Desktop",
    "cli_version": "0.133.0"
  }
}
```

어댑터는 이 줄에서 다음 필드를 추출합니다:

| 필드 | 경로 | 설명 |
|------|------|------|
| session ID | `payload.id` | 세션 식별자 |
| 작업 디렉토리 | `payload.cwd` | 라우팅 분류 기준 |

폴백 체인:
- `payload.cwd` → 없으면 notify 페이로드의 `cwd` → 없으면 `$PWD`
- `payload.id` → 없으면 rollout 파일명의 basename

## 요약기

어댑터는 요약 호출에 `codex exec`를 기본으로 사용하고, 실패하면 `claude`로 fallback합니다:

```bash
bash "$ADAPTER_DIR/../lib/summarize.sh" "$ROLLOUT" "$CWD" "$MACHINE" "$DATE" "$TIME" codex
```

`summarize.sh`의 `codex` 모드는 rollout 파일을 직접 읽어 요약합니다.  
`SUMMARIZER_CMD` 환경 변수로 요약 커맨드를 직접 지정할 수 있습니다(테스트·디버깅 용도).

## 재귀 가드

어댑터 자체가 Codex 세션에서 실행될 경우 무한 루프가 발생할 수 있습니다.  
이를 방지하기 위해 환경 변수 `CODEX_JOURNAL_RUNNING`을 사용합니다:

```bash
if [ -n "${CODEX_JOURNAL_RUNNING:-}" ]; then exit 0; fi
```

어댑터는 서브셸 내에서 `export CODEX_JOURNAL_RUNNING=1`을 설정한 뒤 작업을 수행합니다.

## 비동기 실행

어댑터는 Codex의 응답 지연을 막기 위해 서브셸을 **백그라운드**(`&`)로 실행하고 `disown`합니다. notify 콜백 자체는 거의 즉시 exit 0을 반환합니다.

## 디버깅

모든 실행 로그(stdout + stderr)는 `~/.claude/journal-hook.log`에 기록됩니다.

```bash
tail -f ~/.claude/journal-hook.log
```

rollout 파일을 직접 확인하려면:

```bash
ls -lt ~/.codex/sessions/*/*/*/rollout-*.jsonl | head -5
head -1 $(ls -t ~/.codex/sessions/*/*/*/rollout-*.jsonl | head -1)
```

## 페이로드 검증

notify 페이로드 키 목록 (codex-cli 0.134.0 기준, 검증 완료):

```
type, thread-id, turn-id, cwd, client, input-messages, last-assistant-message
```

이 키들은 실제 바이너리의 `legacy_notify` 정의에서 확인된 것입니다.  
codex 버전 업그레이드 후 페이로드 구조가 변경된 경우 `~/.claude/journal-hook.log`를 확인하세요.
