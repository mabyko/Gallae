# UC-35 · 선택한 과거 commit으로 hard Reset

> 우선순위: P1

| 항목 | 내용 |
| --- | --- |
| 사용자 목표 | 최근 commit과 그 파일 변경을 local branch와 working tree에서 폐기한다. |
| 시작 조건 | 변경이 없는 attached local branch의 History에서 현재 HEAD의 과거 ancestor commit을 선택했다. |
| 진입점 | 선택한 commit 상세의 `Reset…` |
| 완료 상태 | 현재 local branch, index와 working tree가 선택한 commit과 일치하고 이후 tracked 파일과 변경은 남지 않는다. |

## 정상 흐름

1. 사용자가 History에서 현재 branch의 과거 commit을 선택하고 `Reset…`을 실행한다.
2. Gallae가 현재 branch, 대상 commit 제목·SHA와 branch History 변경 범위를 Reset sheet에 표시한다.
3. 사용자가 Hard를 선택하고 Reset을 실행한다.
4. Gallae가 이후 파일과 변경이 제거·교체되고 Gallae에서 실행 취소할 수 없다는 파괴적 확인을 추가로 표시한다.
5. 사용자가 Hard Reset을 다시 확인한다.
6. Gallae가 Repository가 깨끗한 attached local branch인지, 대상 commit이 현재 HEAD의 ancestor인지 다시 확인한다.
7. Gallae가 hard Reset으로 branch, index와 working tree를 대상 commit에 맞춘다.
8. Gallae가 Repository와 History를 다시 읽어 대상 commit을 새 HEAD로, working tree를 변경 없음으로 표시한다.

## 대안 흐름

- 첫 Reset sheet의 Cancel 또는 Escape는 Repository를 바꾸지 않는다.
- 추가 확인에서 Cancel 또는 Escape를 누르면 Reset sheet로 돌아가며 Repository를 바꾸지 않는다.
- staged·unstaged·untracked 변경이 있으면 먼저 Commit하거나 Stash하도록 안내한다.
- detached HEAD, unborn branch, 현재 HEAD 또는 현재 branch의 ancestor가 아닌 commit에는 실행하지 않는다.
- Git이 실패하면 실행 전 HEAD와 tracked 상태로 복원을 시도하고 실제 Repository 상태를 다시 읽는다.
- 복원이 완전하지 않으면 실제 상태를 보여 주고 추가 확인이 필요하다고 경고한다.

## 완료 확인

- local branch HEAD, index와 working tree는 선택한 commit과 같다.
- 이후 commit에서 추가된 tracked 파일은 제거되고 수정된 파일은 대상 commit 내용으로 돌아간다.
- 대상 파일을 막는 untracked 파일이나 폴더도 Git에 의해 삭제될 수 있음을 실행 전에 알린다.
- 실행 전 HEAD 이후 commit은 현재 local branch에서 빠진다. 다른 branch·Remote branch·tag가 가리키면 전체 History에는 계속 표시될 수 있다.
- Remote branch와 Remote Repository는 바뀌지 않는다.
- Gallae 안의 Undo와 선택한 Reflog 지점으로 복구하는 동작은 제공하지 않는다. 이전 HEAD 조회는 [UC-36](uc-36-inspect-reflog.md)에서 제공한다.

[mixed Reset](uc-33-reset-current-branch.md) · [soft Reset](uc-34-soft-reset-current-branch.md) · [Reflog 검사](uc-36-inspect-reflog.md) · [History 검사](uc-12-inspect-history.md) · [사용자 흐름 문서로 돌아가기](../README.md)
