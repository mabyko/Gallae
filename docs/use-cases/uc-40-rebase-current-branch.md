# UC-40 · 선택한 branch를 다른 local branch 위로 Rebase

> 우선순위: P1

| 항목 | 내용 |
| --- | --- |
| 사용자 목표 | 선택한 target branch의 고유 commit을 다른 local branch 위에 다시 적용해 선형 history로 만든다. |
| 시작 조건 | commit이 있는 local Repository가 열려 있고, 대상 Worktree에 진행 중인 작업이나 미커밋 변경이 없다. |
| 진입점 | 상단 Fetch 왼쪽의 `Merge / Rebase…`, 문맥 바 branch 메뉴·Repository 메뉴의 `Merge / Rebase…` |
| 완료 상태 | target branch 이름은 유지되고 고유 commit이 선택한 branch tip 위의 새 commit으로 바뀌며 Workspace가 갱신된다. |

## 정상 흐름

1. 사용자가 상단 도구 막대나 branch 메뉴에서 `Merge / Rebase…`를 누른다.
2. 사용자가 `Update branch`에서 다시 쓸 target을, `Using branch`에서 기준 source를 고른다. 현재 checkout과 무관하게 두 local branch를 선택할 수 있다.
3. 사용자가 commit ID가 바뀌고 Gallae가 force-push하지 않는다는 설명을 확인한다.
4. 사용자가 `Method → Rebase`를 선택하고 `Rebase`를 누른다.
5. Gallae가 선택한 target branch만 source branch 위로 Rebase한 뒤 Repository, Changes, History와 Reflog를 다시 읽는다.

## 대안 흐름

- 대상 Worktree에 staged·unstaged·untracked 변경이 있으면 Rebase를 비활성화하고 먼저 commit하거나 stash하도록 안내한다.
- source branch의 commit이 이미 target에 포함돼 있으면 `Already up to date`를 표시하고 실행을 비활성화한다.
- Cancel 또는 Escape는 Repository를 바꾸지 않는다.
- 선택할 다른 local branch가 없으면 빈 상태를 표시하고, 목록 읽기 실패에는 같은 sheet에서 재시도한다.
- 충돌이나 Git 실패가 나면 rebase를 자동으로 중단하고 original branch·HEAD와 깨끗한 working tree 복원을 확인한다.
- 복원이 끝나지 않으면 실제 Repository 상태를 다시 읽어 경고와 함께 보여 준다.

## 완료 확인

- 대상이 다른 Worktree에 있으면 그 폴더에서 실행한다. 체크아웃되지 않은 대상은 임시 Worktree를 사용하고 성공 후 제거한다. 충돌·복구 실패가 남은 폴더는 보존한다.
- 현재 열어 둔 Workspace를 임의로 전환하지 않는다. 실행 직전 두 branch tip과 대상 Worktree를 다시 확인하고 비교 이후 바뀌었으면 재검토를 요청한다.
- source branch와 다른 local·Remote branch는 바뀌지 않는다.
- Rebase 뒤 target branch의 고유 commit ID는 바뀔 수 있다.
- Gallae는 force-push를 실행하지 않는다.
- 이 흐름에서 충돌 해결과 Continue·Abort는 실행하지 않는다. Rebase가 진행 중인 상태는 [UC-45](uc-45-continue-or-abort-operation.md), interactive rebase는 [UC-48](uc-48-run-interactive-rebase-plan.md)에서 이어 다룬다. Rebase Skip은 제공하지 않는다.
- branch·적용 방식 선택과 실행, 취소는 키보드와 VoiceOver로 실행할 수 있다.

[다른 local branch fast-forward Merge](uc-38-merge-local-branch.md) · [갈라진 local branch Merge commit 생성](uc-39-create-merge-commit.md) · [진행 중인 Merge·Rebase 계속 또는 중단](uc-45-continue-or-abort-operation.md) · [사용자 흐름 문서로 돌아가기](../README.md)
