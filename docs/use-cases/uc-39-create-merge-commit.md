# UC-39 · 갈라진 local branch Merge commit 생성

> 우선순위: P1

| 항목 | 내용 |
| --- | --- |
| 사용자 목표 | 서로 갈라진 다른 local branch의 commit을 target branch에 명시적인 merge commit으로 합친다. |
| 시작 조건 | commit이 있는 local Repository가 열려 있고, 대상 Worktree에 진행 중인 작업이나 미커밋 변경이 없다. |
| 진입점 | 상단 Fetch 왼쪽의 `Merge / Rebase…`, 문맥 바 branch 메뉴·Repository 메뉴의 `Merge / Rebase…` |
| 완료 상태 | target branch에 두 branch를 parent로 둔 merge commit이 생기고 Workspace가 갱신된다. |

## 정상 흐름

1. 사용자가 상단 도구 막대나 branch 메뉴에서 `Merge / Rebase…`를 누른다.
2. 사용자가 `Update branch`에서 변경할 target을, `Using branch`에서 가져올 source를 고른다. 현재 checkout과 무관하게 두 local branch를 선택할 수 있다.
3. 사용자가 `Method → Merge Commit`을 선택하고 `Create Merge Commit`을 누른다.
4. Gallae가 두 branch의 history가 실제로 갈라졌는지 다시 확인한다.
5. Gallae가 `--no-ff --no-edit`로 merge commit을 만든 뒤 Repository, Changes, History와 Reflog를 다시 읽는다.

## 대안 흐름

- 직선 관계에서는 `Fast-Forward`, 갈라진 관계에서는 `Merge Commit`이 기본 선택이다. Return은 현재 선택한 방식의 실행 버튼을 누른다.
- 대상 Worktree에 staged·unstaged·untracked 변경이 있으면 Merge commit 생성을 비활성화하고 먼저 commit하거나 stash하도록 안내한다.
- 두 branch가 갈라지지 않았으면 merge commit을 만들지 않고 Fast-Forward를 사용하도록 안내한다.
- Cancel 또는 Escape는 Repository를 바꾸지 않는다.
- 충돌이 나면 Merge 상태와 대상 Worktree를 보존한다. 현재 작업 폴더가 대상이면 Changes에서 해결하고, 다른 Worktree면 `Open Worktree` 또는 `Abort Merge`를 선택한다.
- 충돌 외의 Git 실패는 merge를 자동으로 중단하고 original HEAD와 깨끗한 working tree 복원을 확인한다.
- 복원이 끝나지 않으면 실제 Repository 상태를 다시 읽어 경고와 함께 보여 준다.

## 완료 확인

- 대상이 다른 Worktree에 있으면 그 폴더에서 실행한다. 체크아웃되지 않은 대상은 임시 Worktree를 사용하고 성공 후 제거한다. 충돌·복구 실패가 남은 폴더는 보존한다.
- 현재 열어 둔 Workspace를 임의로 전환하지 않는다. 실행 직전 두 branch tip과 대상 Worktree를 다시 확인하고 비교 이후 바뀌었으면 재검토를 요청한다.
- 새 commit의 parent는 실행 전 target branch tip와 선택한 source branch commit이다.
- source branch와 Remote branch는 바뀌지 않는다.
- merge message, identity, hook과 서명은 사용자의 Git 설정을 따른다.
- 내장 비교는 읽기 전용이며 Open in Merge Tool에서 Git 설정·VS Code·Sublime Merge로 해결할 수 있다. [외부 도구 지원 범위](../../README.ko.md#충돌-해결과-merge-tool)를 따른다.
- branch·적용 방식 선택과 실행, 취소는 키보드와 VoiceOver로 실행할 수 있다.

[다른 local branch fast-forward Merge](uc-38-merge-local-branch.md) · [기존 local branch 전환](uc-13-switch-local-branch.md) · [사용자 흐름 문서로 돌아가기](../README.md)
