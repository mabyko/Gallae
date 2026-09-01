# UC-13 · 기존 local branch 전환 또는 Worktree 열기

> 우선순위: P1

| 항목 | 내용 |
| --- | --- |
| 사용자 목표 | 기존 local branch를 찾아 안전하게 전환하거나, 이미 연결된 Worktree에서 연다. |
| 시작 조건 | Repository Workspace가 열려 있다. |
| 진입점 | Repository 헤더의 현재 branch |
| 완료 상태 | 선택한 branch 또는 연결된 Worktree의 HEAD, Changes와 History가 같은 Workspace에 표시된다. |

## 정상 흐름

1. 사용자가 Repository 헤더의 현재 branch를 누른다.
2. Gallae가 기존 local branch와 연결된 Worktree를 읽고 현재 branch를 표시한다.
3. 사용자가 이름으로 목록을 좁히고 branch를 선택한다.
4. 연결된 Worktree가 없으면 사용자가 `Switch`, Return 또는 행 이중 클릭으로 전환한다.
5. Gallae가 안전한 Git switch를 실행하고 Repository, Changes와 History를 다시 읽는다.

## 대안 흐름

- detached HEAD에서는 현재 표시 없이 local branch를 선택할 수 있다.
- 다른 existing Worktree에서 체크아웃된 branch는 폴더 배지와 `Open Worktree`를 표시한다. 폴더명이 branch와 다르면 배지에 실제 폴더명을 표시하고 전체 경로를 도움말과 VoiceOver로 제공한다. `Open Worktree`, Return 또는 행 이중 클릭을 실행하면 현재 Repository를 바꾸지 않고 연결된 폴더를 같은 창의 Workspace로 연다.
- 검색 결과가 없으면 별도 빈 상태와 `Clear Search`를 표시한다.
- branch 목록을 읽지 못하면 같은 선택기에서 다시 시도할 수 있다.
- 선택한 branch가 사라졌거나 local 변경과 충돌하면 전환하지 않고 기존 branch·index·working tree와 Workspace를 유지한다.
- 누락되었거나 정리 가능한 Worktree는 열지 않는다.

## 완료 확인

- 현재 branch와 선택 동작은 색 외의 텍스트와 VoiceOver 이름으로 식별할 수 있다.
- 전환은 force·merge 옵션을 쓰거나 local 변경을 버리지 않는다.
- Worktree 생성·삭제, branch 강제 전환, remote-tracking branch 전환과 stash 보조 동작은 포함하지 않는다.

[사용자 흐름 문서로 돌아가기](../README.md)
