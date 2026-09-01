# UC-32 · merge commit mainline 선택 Revert

> 우선순위: P1

| 항목 | 내용 |
| --- | --- |
| 사용자 목표 | merge commit이 가져온 변경을 유지할 parent를 분명히 고른 뒤 History를 다시 쓰지 않고 되돌린다. |
| 시작 조건 | 변경이 없는 attached local branch의 History에서 현재 branch에 포함된 merge commit을 선택했다. |
| 진입점 | 선택한 merge commit 상세의 `Revert` |
| 완료 상태 | 선택한 parent를 mainline으로 삼은 inverse commit이 현재 HEAD 위에 생기고 기존 merge와 History는 유지된다. |

## 정상 흐름

1. 사용자가 merge commit 상세에서 `Revert`를 실행한다.
2. Gallae가 parent 번호와 각 parent의 commit 제목·SHA를 보여 준다.
3. 사용자가 유지할 mainline parent를 직접 선택한다.
4. 사용자가 `Revert Merge`를 실행한다.
5. Gallae가 Repository와 선택한 전체 SHA·parent 번호를 다시 검증하고 merge를 Revert한다.
6. Gallae가 Repository와 History를 다시 읽고 새 HEAD를 표시한다.

## 대안 흐름

- parent를 선택하기 전에는 `Revert Merge`를 실행할 수 없다.
- Cancel 또는 Escape는 Repository를 바꾸지 않는다.
- parent commit이 최근 100개 History 밖에 있으면 번호와 SHA만 표시한다.
- staged·unstaged·untracked 변경, detached HEAD 또는 unborn branch에서는 Revert를 시작하지 않는다.
- 선택한 merge commit이 현재 branch에 포함되지 않으면 Repository를 바꾸지 않고 오류를 표시한다.
- Git이 충돌하거나 실패하면 자동으로 Revert를 abort하고 기존 HEAD와 깨끗한 index·working tree가 복원됐는지 확인한다.

## 완료 확인

- 새 commit은 선택한 parent를 기준으로 merge가 가져온 tree 변경을 반대로 적용한다.
- 기존 merge commit과 그 parent, 이후 History는 그대로 남는다.
- 성공 뒤 index와 working tree는 깨끗하다.
- reset, force 또는 History 재작성은 사용하지 않는다.

[일반 commit Revert](uc-31-revert-commit.md) · [Mixed Reset](uc-33-reset-current-branch.md) · [History 검사](uc-12-inspect-history.md) · [사용자 흐름 문서로 돌아가기](../README.md)
