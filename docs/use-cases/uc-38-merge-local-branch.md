# UC-38 · 다른 local branch fast-forward Merge

> 우선순위: P1

| 항목 | 내용 |
| --- | --- |
| 사용자 목표 | 다른 local branch의 직선상 commit을 target branch에 안전하게 반영한다. |
| 시작 조건 | commit이 있는 attached local branch의 Repository Workspace가 열려 있다. |
| 진입점 | 상단 Fetch 왼쪽의 `Merge / Rebase…`, 문맥 바 branch 메뉴·Repository 메뉴의 `Merge / Rebase…` |
| 완료 상태 | target branch가 선택한 source branch commit으로 fast-forward되고 Workspace가 갱신된다. |

## 정상 흐름

1. 사용자가 상단 도구 막대나 branch 메뉴에서 `Merge / Rebase…`를 누른다.
2. Gallae가 `Update branch`에 현재 branch를 기본 선택하고, `Using branch`에 다른 local branch를 선택한다. 양쪽 모두 변경할 수 있으며 같은 branch를 동시에 선택하지 않는다.
   - 두 branch를 좌우로 배치하고 화살표가 `Update branch`를 가리킨다. 화살표 버튼을 누르면 branch 위치를 유지한 채 적용 방향과 역할을 뒤집고 비교 결과를 갱신한다.
3. 사용자가 두 branch와 비교 결과를 확인하고 `Method → Fast-Forward`를 선택한 뒤 Fast-Forward 또는 Return으로 실행한다.
4. Gallae가 선택한 target branch를 `--ff-only`로 갱신한 뒤 Repository, Changes, History와 Reflog를 다시 읽는다.

## 대안 흐름

- Cancel 또는 Escape는 Repository를 바꾸지 않는다.
- 선택할 다른 local branch가 없으면 빈 상태를 표시한다.
- branch 목록을 읽지 못하면 원인과 `Try Again`을 같은 sheet에 표시한다.
- 두 branch가 갈라졌거나 local 변경이 대상 파일과 겹치면 merge commit이나 rebase를 만들지 않고 오류를 표시한다.
- source branch의 commit이 이미 target에 포함돼 있으면 `Already up to date`를 표시하고 실행을 비활성화한다.

## 완료 확인

- 대상이 다른 Worktree에 있으면 그 폴더에서 실행한다. 체크아웃되지 않은 대상은 임시 Worktree를 사용하고 성공 후 제거한다. 충돌·복구 실패가 남은 폴더는 보존한다.
- 현재 열어 둔 Workspace를 임의로 전환하지 않는다. 실행 직전 두 branch tip과 대상 Worktree를 다시 확인하고 비교 이후 바뀌었으면 재검토를 요청한다.
- 성공해도 source branch와 Remote branch는 바뀌지 않는다.
- 겹치지 않는 staged·unstaged·untracked 변경은 보존한다.
- 실패하면 기존 HEAD·index·working tree와 local 파일을 유지한다.
- detached HEAD와 unborn branch에서는 Merge를 실행할 수 없다.
- branch 선택, 기본 동작과 취소는 키보드와 VoiceOver로 실행할 수 있다.

[기존 local branch 전환](uc-13-switch-local-branch.md) · [configured upstream fast-forward Pull](uc-16-pull-fast-forward.md) · [사용자 흐름 문서로 돌아가기](../README.md)
