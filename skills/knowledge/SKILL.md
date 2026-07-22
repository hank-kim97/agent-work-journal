---
name: knowledge
description: RE팀 업무 기록(팀 지식 카드 레포)에서 증상·키워드로 트러블슈팅 지식을 검색한다. Use when the user or agent hits an error/problem and wants to check if a teammate already solved it — triggers on "/knowledge", "팀 지식", "이거 누가 겪어봤나", "비슷한 문제 있었나", or before debugging an unfamiliar error.
---

# /knowledge — RE팀 업무 기록 검색

팀원들의 업무일지에서 자동 증류된 트러블슈팅 카드(문제상황→시도→해결→정리)를 검색한다.

## 절차

1. **레포 위치 확인**: agent-work-journal 도구 디렉토리의 `config.json`에서 `knowledge_repo` 값을 읽는다 (`~` 확장 필요).
   ```bash
   python3 -c "import json,os;print(os.path.expanduser(json.load(open('<TOOL_DIR>/config.json')).get('knowledge_repo','')))"
   ```
   값이 없으면: "팀 지식 레포가 설정되지 않았습니다 — `install-knowledge.sh --repo <path>` 실행 필요"라고 안내하고 종료.

2. **검색** (질의를 핵심 키워드 2~4개로 분해):
   - 1차: 키워드 AND — `grep -li` 를 키워드마다 파이프로 좁혀가며 `cards/*.md` 검색
   - 히트 0이면 2차: 키워드 OR — `grep -lie kw1 -e kw2 ...` + `INDEX.md`의 제목·태그 행 매치
   - 한국어 증상 표현은 영어 태그로도 변환해 시도 (예: "느려요"→slow/performance/cache, "막혀요"→blocked/egress/403)

3. **제시**:
   - 상위 1~3개 카드의 **제목 + 정리 섹션**을 먼저 보여주고, 가장 관련 높은 카드는 전문 인용
   - 카드의 `sources`(코드명/날짜)를 함께 표기해 원 세션 추적 가능하게
   - 히트 0이면: "팀 기록에 없음 — 해결하게 되면 이번 세션 일지가 다음 주간 추출에서 자동으로 카드화됩니다" 안내

## 규칙

- 카드 내용을 각색하지 말고 인용한다 (해결 절차의 정확성이 생명)
- "해결 미기록 — 출처 세션 참조" 카드는 그 한계를 그대로 전달한다
- 검색만 한다 — 이 스킬에서 카드를 쓰거나 수정하지 않는다 (쓰기는 주간 추출 배치의 몫)
