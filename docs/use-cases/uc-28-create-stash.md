# UC-28 · 새 Stash 생성

> 우선순위: P1

| 항목 | 내용 |
| --- | --- |
| 사용자 목표 | 현재 작업을 잃지 않고 잠시 보관한 뒤 깨끗한 tracked 작업 상태로 돌아간다. |
| 시작 조건 | 첫 commit이 있는 Repository Workspace에 충돌하지 않은 변경이 있다. |
| 진입점 | `Stashes`의 `New Stash` |
| 완료 상태 | 새 Stash가 목록 맨 위에 선택되고 Repository의 현재 변경 상태가 다시 표시된다. |

## 정상 흐름

1. 사용자가 `Stashes`에서 `New Stash`를 선택한다.
2. 필요하면 메시지를 입력한다.
3. untracked 파일도 보관하려면 `Include Untracked Files`를 켠다.
4. 사용자가 `Create Stash`를 실행한다.
5. Gallae가 staged·unstaged tracked 변경과 선택한 경우 untracked 파일을 저장한다.
6. Gallae가 Repository와 Stash 목록을 다시 읽고 새 Stash를 선택한다.

## 대안 흐름

- 메시지가 비어 있으면 Git이 기본 Stash 메시지를 만든다.
- 옵션을 끄면 untracked 파일은 작업 트리에 남는다. ignored 파일은 어느 경우에도 포함하지 않는다.
- 첫 commit 전, 충돌 중이거나 선택한 옵션으로 저장할 변경이 없으면 이유를 보여 주고 `Create Stash`를 비활성화한다.
- 실행 전 Cancel 또는 Escape는 Repository를 바꾸지 않는다.
- 생성에 실패하면 입력한 메시지와 옵션을 유지하고 오류를 표시해 다시 시도할 수 있게 한다.

## 완료 확인

- 성공 뒤 HEAD와 commit은 바뀌지 않는다.
- tracked index와 working tree는 HEAD 상태로 돌아가며, 포함하지 않은 untracked 파일은 그대로 남는다.
- 새 Stash의 메시지와 tracked·선택된 untracked 변경을 UC-27 흐름에서 다시 확인할 수 있다.
- Stash 적용은 [UC-29](uc-29-apply-stash.md), 삭제는 [UC-30](uc-30-delete-stash.md)에서 다룬다.

[사용자 흐름 문서로 돌아가기](../README.md)
