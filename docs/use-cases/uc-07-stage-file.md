# UC-07 · 파일 단위 Stage/Unstage

> 우선순위: P1

| 항목 | 내용 |
| --- | --- |
| 사용자 목표 | 검토한 파일 하나 이상을 다음 commit에 포함하거나 다시 제외한다. |
| 시작 조건 | 변경 파일이 있는 Repository Workspace가 열려 있다. |
| 진입점 | 선택한 파일의 diff 헤더 또는 Changes 목록의 우클릭 메뉴 |
| 완료 상태 | 최신 index 상태와 diff가 같은 Workspace에 반영된다. |

## 정상 흐름

1. 사용자가 변경 파일과 diff를 검토한다.
2. 필요하면 Status 또는 Folders 목록에서 ⌘클릭·Shift 클릭으로 여러 파일을 선택한다. ⌘A는 Status에서 현재 파일이 속한 그룹만, Folders에서 모든 변경 파일을 선택한다.
3. 단일 파일의 diff 헤더 또는 선택 파일의 우클릭 메뉴에서 Stage나 Unstage를 실행한다.
4. Gallae가 동작 가능한 선택 파일의 경로를 한 번에 index에 반영하고 Repository 상태를 다시 읽는다.
5. diff는 마지막으로 선택한 한 파일을 계속 보여 준다.

## 대안 흐름

- 선택에 staged와 unstaged 변경이 함께 있으면 Stage와 Unstage를 모두 표시하고 각 동작이 가능한 파일에만 적용한다.
- untracked 파일은 Stage할 수 있고, 최초 commit 전 staged 파일도 삭제 없이 Unstage할 수 있다.
- rename은 원본과 새 경로를 함께 처리한다.
- 충돌 파일은 다중 선택에 포함되어도 Stage와 Unstage 대상에서 제외한다.
- Git 명령이 실패하면 기존 화면 상태를 유지하고 오류를 표시한다.

## 완료 확인

- 성공 뒤 파일 상태와 diff를 다시 읽고 가능한 다음 동작을 표시한다.
- Stage와 Unstage는 working tree 파일 내용을 변경하거나 삭제하지 않는다.
- 파일 단위 discard는 [UC-11](uc-11-discard-file.md)에서 다루며, 이 흐름은 hunk 단위 Stage, commit과 충돌 해결을 포함하지 않는다.

[사용자 흐름 문서로 돌아가기](../README.md)
