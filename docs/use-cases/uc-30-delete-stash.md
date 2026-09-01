# UC-30 · Stash 삭제

> 우선순위: P1

| 항목 | 내용 |
| --- | --- |
| 사용자 목표 | 더 이상 필요 없는 Stash 한 건을 다른 작업과 혼동하지 않고 정리한다. |
| 시작 조건 | Repository Workspace에 삭제할 Stash가 선택되어 있다. |
| 진입점 | 선택한 Stash 상세의 `Delete…` |
| 완료 상태 | 확인한 Stash만 목록에서 사라지고 Repository 상태와 다른 Stash는 유지된다. |

## 정상 흐름

1. 사용자가 Stash와 저장된 변경을 검토한다.
2. 사용자가 `Delete…`를 실행한다.
3. Gallae가 영구 삭제와 실행 취소 불가, Repository 비변경을 설명하는 확인 대화상자를 표시한다.
4. 사용자가 `Delete Stash`를 확인한다.
5. Gallae가 선택한 commit ID를 현재 Stash 목록에서 다시 찾아 해당 항목만 삭제한다.
6. Gallae가 Repository와 Stash 목록을 다시 읽고 남은 첫 항목을 선택한다.

## 대안 흐름

- Cancel 또는 Escape는 Stash와 Repository를 바꾸지 않는다.
- 선택 뒤 다른 Stash가 추가되어 번호가 바뀌면 commit ID가 같은 현재 항목을 찾아 삭제한다.
- 선택한 Stash가 이미 사라졌으면 다른 항목을 대신 삭제하지 않고 목록을 다시 읽어 오류를 표시한다.
- Git이 삭제를 거부하면 현재 Repository와 Stash 목록을 유지하고 오류를 표시한다.

## 완료 확인

- 선택한 Stash만 영구 삭제되며 Gallae에서 실행 취소할 수 없다.
- 삭제는 저장된 변경을 적용하지 않고 HEAD·index·working tree와 untracked 파일을 바꾸지 않는다.
- 다른 Stash의 commit ID와 저장된 변경은 유지된다.

[사용자 흐름 문서로 돌아가기](../README.md)
