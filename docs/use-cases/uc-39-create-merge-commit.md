# UC-39 · 갈라진 local branch Merge commit 생성

> 우선순위: P1

| 항목 | 내용 |
| --- | --- |
| 사용자 목표 | 서로 갈라진 다른 local branch의 commit을 현재 branch에 명시적인 merge commit으로 합친다. |
| 시작 조건 | 변경이 없는 attached local branch의 Repository Workspace가 열려 있다. |
| 진입점 | 문맥 바 branch 메뉴의 `Integrate…`, 또는 Repository 메뉴의 `Integrate…` |
| 완료 상태 | 현재 branch에 두 branch를 parent로 둔 merge commit이 생기고 Workspace가 갱신된다. |

## 정상 흐름

1. 사용자가 branch 메뉴 또는 Repository 메뉴에서 `Integrate…`를 누른다.
2. Gallae가 현재 branch를 제외한 local branch 목록을 읽고 사용자가 source branch를 고른다.
3. 사용자가 `Create Merge Commit`을 누른다.
4. Gallae가 두 branch의 history가 실제로 갈라졌는지 다시 확인한다.
5. Gallae가 `--no-ff --no-edit`로 merge commit을 만든 뒤 Repository, Changes, History와 Reflog를 다시 읽는다.

## 대안 흐름

- `Fast-Forward`가 기본 동작이며 Return도 [UC-38](uc-38-merge-local-branch.md)의 fast-forward를 실행한다.
- staged·unstaged·untracked 변경이 있으면 Merge commit 생성을 비활성화하고 먼저 commit하거나 stash하도록 안내한다.
- 두 branch가 갈라지지 않았으면 merge commit을 만들지 않고 Fast-Forward를 사용하도록 안내한다.
- Cancel 또는 Escape는 Repository를 바꾸지 않는다.
- 충돌이나 Git 실패가 나면 merge를 자동으로 중단하고 original HEAD와 깨끗한 working tree 복원을 확인한다.
- 복원이 끝나지 않으면 실제 Repository 상태를 다시 읽어 경고와 함께 보여 준다.

## 완료 확인

- 새 commit의 parent는 실행 전 현재 HEAD와 선택한 source branch commit이다.
- source branch와 Remote branch는 바뀌지 않는다.
- merge message, identity, hook과 서명은 사용자의 Git 설정을 따른다.
- 충돌 편집기는 제공하지 않는다.
- branch 선택과 두 동작, 취소는 키보드와 VoiceOver로 실행할 수 있다.

[다른 local branch fast-forward Merge](uc-38-merge-local-branch.md) · [기존 local branch 전환](uc-13-switch-local-branch.md) · [사용자 흐름 문서로 돌아가기](../README.md)
