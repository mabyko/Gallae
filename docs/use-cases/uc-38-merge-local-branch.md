# UC-38 · 다른 local branch fast-forward Merge

> 우선순위: P1

| 항목 | 내용 |
| --- | --- |
| 사용자 목표 | 다른 local branch의 직선상 commit을 현재 branch에 안전하게 반영한다. |
| 시작 조건 | commit이 있는 attached local branch의 Repository Workspace가 열려 있다. |
| 진입점 | 문맥 바 branch 메뉴의 `Integrate…`, Repository 메뉴의 `Integrate…`, 또는 Navigator branch 행의 문맥 메뉴·branch 화면의 `Integrate…`(그 branch가 미리 선택됨) |
| 완료 상태 | 현재 branch가 선택한 source branch commit으로 fast-forward되고 Workspace가 갱신된다. |

## 정상 흐름

1. 사용자가 branch 메뉴 또는 Repository 메뉴에서 `Integrate…`를 누른다.
2. Gallae가 현재 branch를 제외한 local branch 목록을 읽고 첫 항목을 선택한다.
3. 사용자가 source branch를 확인하고 Fast-Forward 또는 Return으로 실행한다.
4. Gallae가 현재 branch를 `--ff-only`로 갱신한 뒤 Repository, Changes, History와 Reflog를 다시 읽는다.

## 대안 흐름

- Cancel 또는 Escape는 Repository를 바꾸지 않는다.
- 선택할 다른 local branch가 없으면 빈 상태를 표시한다.
- branch 목록을 읽지 못하면 원인과 `Try Again`을 같은 sheet에 표시한다.
- 두 branch가 갈라졌거나 local 변경이 대상 파일과 겹치면 merge commit이나 rebase를 만들지 않고 오류를 표시한다.
- source branch가 이미 현재 branch에 포함돼 있으면 Git의 up-to-date 결과를 받아 현재 상태를 다시 읽는다.

## 완료 확인

- 성공해도 source branch와 Remote branch는 바뀌지 않는다.
- 겹치지 않는 staged·unstaged·untracked 변경은 보존한다.
- 실패하면 기존 HEAD·index·working tree와 local 파일을 유지한다.
- detached HEAD와 unborn branch에서는 Merge를 실행할 수 없다.
- branch 선택, 기본 동작과 취소는 키보드와 VoiceOver로 실행할 수 있다.

[기존 local branch 전환](uc-13-switch-local-branch.md) · [configured upstream fast-forward Pull](uc-16-pull-fast-forward.md) · [사용자 흐름 문서로 돌아가기](../README.md)
