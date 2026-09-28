# UC-50 · 선택한 일반 commit Cherry-pick

> 우선순위: P1

| 항목 | 내용 |
| --- | --- |
| 사용자 목표 | History에서 검토한 commit 하나의 변경을 현재 branch에 적용한다. |
| 시작 조건 | 기존 local branch가 열려 있고, 작업 폴더가 깨끗하며 다른 Git 작업이 진행 중이지 않다. |
| 진입점 | History의 선택한 commit 상세에 있는 Cherry-Pick…; 상하 배치에서는 Details… |
| 완료 상태 | 현재 branch에 적용한 결과 또는 충돌·빈 Cherry-pick의 실제 진행 상태가 보인다. |

## 정상 흐름

1. 사용자가 History에서 merge가 아닌 commit 하나를 검토한다.
2. Cherry-Pick…을 선택하고 대상 commit과 현재 branch를 확인한다.
3. Gallae가 확인한 HEAD, branch와 작업 상태를 다시 검사한다.
4. Git이 선택한 commit의 변경을 현재 branch에 적용한다.
5. Gallae가 Repository를 다시 읽어 최신 HEAD와 Changes를 보여 준다.

## 대안 흐름

- staged·unstaged·untracked 변경이 있으면 먼저 Commit이나 Stash하도록 안내한다.
- merge commit, Detached HEAD, commit이 없는 branch, 진행 중인 다른 작업에서는 실행하지 않는다.
- 확인 후 HEAD·branch·Repository가 바뀌었으면 이전 확인으로 실행하지 않는다.
- 충돌이 나면 Cherry-pick 상태를 유지하고 Changes에서 충돌 파일을 보여 준다. 해결 후 Continue하거나 확인을 거쳐 Skip·Abort한다.
- 변경이 이미 적용됐거나 충돌 해결 뒤 적용할 변경이 남지 않으면 빈 commit을 자동 생성하지 않고 Skip·Abort를 안내한다.
- Git 실행에 실패하면 실제 Repository 상태를 다시 읽고 오류를 표시한다.

## 완료 확인

- 앱에서 시작하는 Cherry-pick은 일반 commit 하나를 현재 branch에 적용한다. 다른 branch나 임시 Worktree를 대상으로 실행하지 않는다.
- 확인을 취소하면 HEAD·index·working tree를 바꾸지 않는다.
- 연결된 Worktree에서도 해당 작업 폴더의 상태를 검사한다.
- 터미널에서 시작한 Cherry-pick의 진행 상태도 [UC-44](uc-44-inspect-in-progress-operation.md)에서 확인하고 [UC-45](uc-45-continue-or-abort-operation.md)에서 Continue·Skip·Abort한다.

[Repository commit History 검사](uc-12-inspect-history.md) · [사용자 흐름 문서로 돌아가기](../README.md)
