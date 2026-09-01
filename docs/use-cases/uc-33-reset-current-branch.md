# UC-33 · 선택한 과거 commit으로 mixed Reset

> 우선순위: P1

| 항목 | 내용 |
| --- | --- |
| 사용자 목표 | 최근 commit을 local branch에서 되돌리되 파일 내용은 작업 트리에 남긴다. |
| 시작 조건 | 변경이 없는 attached local branch의 History에서 현재 HEAD의 과거 ancestor commit을 선택했다. |
| 진입점 | 선택한 commit 상세의 `Reset…` |
| 완료 상태 | 현재 local branch와 index는 선택한 commit을 가리키고 기존 파일 내용은 unstaged·untracked 변경으로 남는다. |

## 정상 흐름

1. 사용자가 History에서 현재 branch의 과거 commit을 선택하고 `Reset…`을 실행한다.
2. Gallae가 현재 branch, 대상 commit 제목·SHA와 branch History 변경 범위를 Reset sheet에 표시한다.
3. 사용자가 기본값인 Mixed를 선택하고 Reset을 확인한다.
4. Gallae가 Repository가 깨끗한 attached local branch인지, 대상 commit이 현재 HEAD의 ancestor인지 다시 확인한다.
5. Gallae가 mixed Reset으로 branch와 index를 대상 commit에 맞추고 working tree 파일은 그대로 둔다.
6. Gallae가 Repository와 History를 다시 읽어 대상 commit을 새 HEAD로, 이후 파일 내용을 unstaged·untracked 변경으로 표시한다.

## 대안 흐름

- Cancel 또는 Escape는 Repository를 바꾸지 않는다.
- 사용자가 staged 상태를 유지하려면 [soft Reset](uc-34-soft-reset-current-branch.md)을 선택한다.
- 사용자가 이후 파일과 변경을 폐기하려면 [hard Reset](uc-35-hard-reset-current-branch.md)을 선택한다.
- staged·unstaged·untracked 변경이 있으면 먼저 Commit하거나 Stash하도록 안내한다.
- detached HEAD, unborn branch, 현재 HEAD 또는 현재 branch의 ancestor가 아닌 commit에는 실행하지 않는다.
- Git이 실패하면 실행 전 HEAD로 복원을 시도하고 깨끗한 index·working tree가 돌아왔는지 확인한다.
- 자동 복원이 완전하지 않으면 실제 Repository 상태를 다시 읽어 보여 주고 추가 확인이 필요하다고 경고한다.

## 완료 확인

- local branch HEAD는 선택한 commit이며 index도 그 commit과 같다.
- 실행 전 working tree 파일 내용은 바뀌지 않고 Reset으로 되돌린 내용이 unstaged 또는 untracked 변경으로 나타난다.
- 실행 전 HEAD 이후 commit은 현재 local branch에서 빠진다. 다른 branch·Remote branch·tag가 가리키면 전체 History에는 계속 표시될 수 있다.
- Remote branch와 Remote Repository는 바뀌지 않는다.
- 다른 branch로의 이동과 reflog 복구 UI는 사용하지 않는다.

[soft Reset](uc-34-soft-reset-current-branch.md) · [hard Reset](uc-35-hard-reset-current-branch.md) · [일반 commit Revert](uc-31-revert-commit.md) · [Merge commit Revert](uc-32-revert-merge-commit.md) · [History 검사](uc-12-inspect-history.md) · [사용자 흐름 문서로 돌아가기](../README.md)
