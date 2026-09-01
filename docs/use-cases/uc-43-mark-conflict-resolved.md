# UC-43 · 현재 working tree 내용으로 충돌 해결

> 우선순위: P1

| 항목 | 내용 |
| --- | --- |
| 사용자 목표 | 외부 편집기에서 합친 현재 파일 상태를 해당 경로의 해결 결과로 기록한다. |
| 시작 조건 | Base·Ours·Theirs 비교가 열린 충돌 파일이 선택되어 있다. |
| 진입점 | `Mark Resolved…` |
| 완료 상태 | 현재 working tree 상태가 index에 기록되고 해당 파일의 unmerged 상태가 사라진다. |

## 정상 흐름

1. 사용자가 외부 편집기에서 충돌 파일을 합친다.
2. 사용자가 Gallae의 충돌 비교 화면에서 `Mark Resolved…`를 누른다.
3. Gallae가 현재 디스크 상태를 stage하며 충돌 marker를 검사하지 않는다고 설명한다.
4. 사용자가 실행을 확인한다.
5. Gallae가 해당 경로가 여전히 unmerged인지 다시 확인하고 현재 working tree 상태를 index에 기록한다.
6. Gallae가 Repository와 diff를 다시 읽는다.

## 대안 흐름

- 파일이 삭제된 상태면 삭제를 해결 결과로 stage한다.
- Cancel 또는 Escape는 working tree와 index를 바꾸지 않는다.
- 파일이 이미 해결됐거나 상태가 바뀌었으면 실행하지 않고 최신 Repository를 다시 읽는다.
- Git 실행이 실패하면 실제 Repository 상태를 다시 읽어 부분적으로 바뀐 내용도 숨기지 않고 오류를 표시한다.

## 완료 확인

- 현재 파일 내용 또는 삭제 상태가 index에 반영되고 해당 경로의 stage 1·2·3 entry는 사라진다.
- 현재 HEAD와 다른 충돌 파일은 바뀌지 않는다.
- Gallae는 남아 있는 충돌 marker나 결과의 의미를 자동으로 판정하지 않는다.
- 실행과 취소를 키보드와 VoiceOver로 수행할 수 있다.
- 진행 중인 Merge·Rebase의 종류와 남은 충돌 수는 [상태 영역](uc-44-inspect-in-progress-operation.md)에 표시하고, 마지막 충돌을 해결한 뒤 [계속하거나 중단](uc-45-continue-or-abort-operation.md)할 수 있다.

[충돌 파일을 Ours 또는 Theirs로 해결](uc-42-resolve-conflict-with-side.md) · [진행 중인 Merge·Rebase 상태 검사](uc-44-inspect-in-progress-operation.md) · [진행 중인 Merge·Rebase 계속 또는 중단](uc-45-continue-or-abort-operation.md) · [사용자 흐름 문서로 돌아가기](../README.md)
