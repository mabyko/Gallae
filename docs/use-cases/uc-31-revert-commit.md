# UC-31 · 선택한 commit Revert

> 우선순위: P1

| 항목 | 내용 |
| --- | --- |
| 사용자 목표 | 과거 commit 하나의 변경을 History를 다시 쓰지 않고 안전하게 되돌린다. |
| 시작 조건 | 변경이 없는 attached local branch의 History에서 현재 branch에 포함된 일반 commit을 선택했다. |
| 진입점 | 선택한 commit 상세의 `Revert` |
| 완료 상태 | 선택한 변경을 반대로 적용한 새 commit이 현재 HEAD 위에 생기고 기존 History는 유지된다. |

## 정상 흐름

1. 사용자가 History에서 되돌릴 일반 commit을 선택한다.
2. Gallae가 `Revert`를 실행하기 직전에 Repository 상태와 선택한 전체 SHA를 다시 확인한다.
3. Gallae가 선택한 commit이 현재 HEAD의 ancestor인지 확인한다.
4. Gallae가 Git의 기본 Revert 메시지로 inverse commit을 만든다.
5. Gallae가 Repository와 History를 다시 읽고 새 HEAD를 표시한다.

## 대안 흐름

- staged·unstaged·untracked 변경이 있으면 `Revert`를 비활성화하고 먼저 정리하거나 Stash하도록 안내한다.
- detached HEAD 또는 unborn branch에서는 실행하지 않는다.
- merge commit은 [UC-32](uc-32-revert-merge-commit.md)의 mainline 선택 흐름으로 이동한다.
- 선택한 commit이 현재 branch에 포함되지 않으면 Repository를 바꾸지 않고 오류를 표시한다.
- Git이 충돌하거나 실패하면 자동으로 Revert를 abort하고 기존 HEAD와 깨끗한 index·working tree가 복원됐는지 확인한다.
- 자동 복원이 완전하지 않으면 실제 Repository 상태를 다시 읽어 보여 주고 추가 확인이 필요하다고 경고한다.

## 완료 확인

- 기존 commit과 이후 commit은 History에 그대로 남는다.
- 새 commit의 parent는 실행 전 HEAD이며 선택한 변경만 반대로 적용한다.
- 실행 전 HEAD 이후에 생긴 다른 파일과 변경은 유지된다.
- 성공 뒤 index와 working tree는 깨끗하다.
- reset, force 또는 History 재작성은 사용하지 않는다.

[Merge commit Revert](uc-32-revert-merge-commit.md) · [Mixed Reset](uc-33-reset-current-branch.md) · [History 검사](uc-12-inspect-history.md) · [사용자 흐름 문서로 돌아가기](../README.md)
