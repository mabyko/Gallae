# UC-42 · 충돌 파일을 Ours 또는 Theirs로 해결

> 우선순위: P1

| 항목 | 내용 |
| --- | --- |
| 사용자 목표 | 충돌 파일의 한쪽 전체 버전을 선택해 해당 파일의 충돌을 해결한다. |
| 시작 조건 | Base·Ours·Theirs 비교가 열린 충돌 파일이 선택되어 있다. |
| 진입점 | `Use Ours…` 또는 `Use Theirs…` |
| 완료 상태 | 선택한 전체 버전이 working tree와 index에 기록되고 해당 파일의 unmerged 상태가 사라진다. |

## 정상 흐름

1. 사용자가 Base·Ours·Theirs를 비교하고 `Use Ours…` 또는 `Use Theirs…`를 누른다.
2. Gallae가 파일을 선택한 버전으로 교체하고 stage한다는 설명을 보여 준다.
3. 사용자가 선택을 확인한다.
4. Gallae가 해당 경로가 여전히 unmerged인지 다시 확인하고 선택한 Git index stage를 working tree에 쓴 뒤 resolved 상태로 stage한다.
5. Gallae가 Repository와 diff를 다시 읽는다.

## 대안 흐름

- 선택한 쪽에 파일이 없으면 삭제를 해결 결과로 먼저 알리고, 확인 시 삭제를 stage한다.
- Cancel 또는 Escape는 working tree와 index를 바꾸지 않는다.
- 파일이 이미 해결됐거나 상태가 바뀌었으면 실행하지 않고 최신 Repository를 다시 읽는다.
- Git 실행이 실패하면 실제 Repository 상태를 다시 읽어 부분적으로 바뀐 내용도 숨기지 않고 오류를 표시한다.

## 완료 확인

- 선택한 결과가 working tree와 index에 반영되고 해당 경로의 stage 1·2·3 entry는 사라진다.
- 현재 HEAD와 다른 충돌 파일은 바뀌지 않는다.
- Gallae 안에서 이 선택을 실행 취소할 수 없음을 확인 전에 알린다.
- 실행과 취소를 키보드와 VoiceOver로 수행할 수 있다.
- 직접 편집한 내용을 해결로 표시하는 동작은 [UC-43](uc-43-mark-conflict-resolved.md), Merge·Rebase를 계속하거나 중단하는 동작은 [UC-45](uc-45-continue-or-abort-operation.md)에서 제공한다.

[충돌 파일의 Base·Ours·Theirs 검사](uc-41-inspect-conflict-versions.md) · [현재 working tree 내용으로 충돌 해결](uc-43-mark-conflict-resolved.md) · [진행 중인 Merge·Rebase 계속 또는 중단](uc-45-continue-or-abort-operation.md) · [사용자 흐름 문서로 돌아가기](../README.md)
