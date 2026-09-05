# UC-13 · 기존 local branch 전환 또는 Worktree 열기

> 우선순위: P1

| 항목 | 내용 |
| --- | --- |
| 사용자 목표 | 기존 local branch를 찾아 안전하게 전환하거나, 이미 연결된 Worktree에서 연다. |
| 시작 조건 | Repository Workspace가 열려 있다. |
| 진입점 | Navigator의 Branches 목록(이중 클릭·문맥 메뉴), branch 화면의 `Switch`, 또는 문맥 바의 현재 branch 메뉴 |
| 완료 상태 | 선택한 branch 또는 연결된 Worktree의 HEAD, Changes와 History가 같은 Workspace에 표시된다. |

## 정상 흐름

1. 사용자가 Navigator의 Branches 목록을 보거나 문맥 바의 현재 branch 메뉴를 연다.
2. Gallae는 Workspace를 열 때 기존 local branch와 연결된 Worktree를 읽고 현재 branch에 HEAD를 표시한다.
3. 사용자가 Navigator 하단의 필터로 목록을 좁힌다.
4. 연결된 Worktree가 없으면 사용자가 행 이중 클릭, 문맥 메뉴의 `Switch`, 또는 branch 메뉴의 `Switch To`로 전환한다.
5. Gallae가 안전한 Git switch를 실행하고 Repository, Changes와 History를 다시 읽는다.

## 대안 흐름

- detached HEAD에서는 현재 표시 없이 local branch를 선택할 수 있다.
- 다른 existing Worktree에서 체크아웃된 branch는 폴더 배지와 `Open Worktree`를 표시한다. 폴더명이 branch와 다르면 배지에 실제 폴더명을 표시하고 전체 경로를 도움말과 VoiceOver로 제공한다. `Open Worktree`(문맥 메뉴·branch 메뉴) 또는 행 이중 클릭을 실행하면 현재 Repository를 바꾸지 않고 연결된 폴더를 같은 창의 Workspace로 연다.
- 필터 결과가 없으면 `No Matching Branches`를 표시한다.
- branch 목록을 읽지 못하면 Navigator에 실패와 원인(도움말)을 표시하고, 다음 새로고침(⌘R)이나 Repository 변경에서 다시 읽는다.
- 선택한 branch가 사라졌거나 local 변경과 충돌하면 전환하지 않고 기존 branch·index·working tree와 Workspace를 유지한다.
- 누락되었거나 정리 가능한 Worktree는 열지 않는다.

## Worktrees 목록과 생성

- 연결된 Worktree가 하나라도 있으면 Navigator의 Branches 위에 접을 수 있는 Worktrees 섹션을 표시한다. 기본 폴더만 있으면 생략한다.
- 목록은 Git이 등록한 모든 작업 폴더를 표시한다. 폴더 이름 아래에 branch 또는 `Detached HEAD · SHA`를 표시하고 현재 폴더는 체크 표시, 다른 기본 폴더는 `Primary`로 구분한다. 같은 이름의 폴더는 부모 경로를 함께 표시한다.
- 한 번 클릭하거나 방향키로 선택하면 전체 History에서 그 폴더의 HEAD로 이동한다. 작업 폴더와 명시적인 History 필터는 유지한다. HEAD가 필터 밖에 있으면 기존 필터 안내를 표시한다.
- 더블클릭·Return·문맥 메뉴의 `Open Worktree`는 선택한 폴더를 연다. `Open in`과 `Copy Path`도 해당 폴더를 대상으로 한다.
- `Branches ⋯`·`Worktrees ⋯`·상단 branch 메뉴의 `New Worktree…`로 생성 창을 연다. 체크아웃된 폴더가 없는 branch의 우클릭 메뉴에서는 해당 branch를 미리 선택한다.
- 새 branch는 이름과 시작점(기본 `HEAD`), 기존 branch는 사용 중이 아닌 local branch를 고른다. 생성 위치와 새 폴더 이름을 정하고 `Create Worktree`를 누른다. `Open after creation`은 기본으로 켜져 있다.
- 이미 존재하는 경로·중복 branch·잘못된 시작점·이미 체크아웃된 branch는 거부한다. 생성은 현재 폴더의 branch·index·수정 파일을 바꾸지 않는다.
- 기본 폴더는 제거 메뉴를 제공하지 않는다. 현재·잠긴·누락된 폴더는 제거할 수 없다. 그 밖의 폴더도 수정 파일이나 untracked 파일이 있으면 Git이 제거를 거부한다. Worktrees 목록의 제거는 branch와 commit을 남긴다. 강제 제거·자동 prune·자동 unlock은 하지 않는다.
- 목록 갱신 중에는 이전 정보를 유지하고 다른 저장소로 이동하면 초기화한다. 누락된 폴더도 등록 정보를 남겨 표시하며 열기를 비활성화한다.

## 완료 확인

- 현재 branch와 선택 동작은 색 외의 텍스트와 VoiceOver 이름으로 식별할 수 있다.
- 전환은 force·merge 옵션을 쓰거나 local 변경을 버리지 않는다.
- branch 강제 전환, remote-tracking branch 전환과 stash 보조 동작은 포함하지 않는다.

[사용자 흐름 문서로 돌아가기](../README.md)
