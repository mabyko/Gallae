# UC-12 · Repository commit History 검사

> 우선순위: P1

| 항목 | 내용 |
| --- | --- |
| 사용자 목표 | 현재 작업선과 다른 branch·tag의 최근 변경 맥락, 선택한 commit의 내용을 읽는다. |
| 시작 조건 | commit이 하나 이상 있는 Repository Workspace가 열려 있다. |
| 진입점 | Navigator의 `History`(⌘2), Navigator에서 branch·tag 선택, 또는 문맥 바 branch 메뉴의 `Show History ▸` |
| 완료 상태 | 선택한 commit의 메시지·작성자·revision·parent, 변경 파일과 선택 파일 patch가 같은 Workspace에 표시된다. |

## 정상 흐름

1. 사용자가 Navigator에서 `History`를 선택한다. branch·remote branch·tag를 선택하면 현재 그래프에서 해당 ref의 끝 commit을 선택하고 그 위치로 스크롤한다. 클릭은 조회 범위나 checkout을 바꾸지 않는다.
2. Gallae가 현재 HEAD, local·remote-tracking branch와 tag에서 도달 가능한 최신 commit을 합쳐 최초 100개를 topology 순서로 읽는다. Load Older Commits는 100개씩 더 읽고, 아직 읽지 않은 ref의 끝 commit을 선택하면 그 위치까지 확장한다. 명시적 필터로 ref를 골랐으면 `refs/heads/…`·`refs/tags/…`로 정확히 그 ref만 읽는다.
3. Gallae가 현재 HEAD commit을 처음 선택하고(조회 범위 밖이면 목록의 첫 commit), ref 탐색 시에는 해당 ref의 끝 commit을 선택한다. 사용자가 필요하면 목록에서 다른 commit을 선택한다.
4. Gallae가 선택한 commit의 메타데이터와 first-parent 기준 변경 파일을 읽고 첫 파일을 선택한다. 기본 상하 배치는 커밋 머리에 작성자·서명과 짧은 본문을 표시하고, Details…에서 원문·전체 SHA·parent·커밋 작업을 제공한다.
5. Gallae가 선택한 파일의 patch를 읽는다.
6. 사용자는 방향키로 다른 commit이나 파일을 선택해 같은 화면에서 검토를 이어 간다.
7. 필요하면 메시지·작성자·이메일·SHA·ref를 입력해 이미 읽은 목록을 좁힌다.
8. commit에 닿은 branch와 tag가 있으면 행에서 이름과 종류를 확인한다.
9. 목록 왼쪽 graph에서 일반 commit과 merge의 부모 관계를 확인한다.
10. 상하 배치에서 Expand Review로 검토 영역을 넓히고 Show History로 목록에 돌아온다. 현재 검색·조회 범위 안에서 이전/다음 commit을 고를 수 있다.

## 대안 흐름

- Appearance → History Colors에서 그래프 시작색과 로컬·원격 branch·tag 배지색을 각각 선택하고 기본색으로 초기화한다. 색상은 저장되며 배지 글자는 시스템 기본 글자색을 유지한다.
- Appearance → History Layout에서 기본 Top and Bottom과 Side by Side를 고른다. 배치 전환과 검토 확장·복귀는 선택한 commit·파일을 유지한다.
- History 머리의 조회 범위 메뉴에서 All Branches & Tags 또는 로컬 branch를 선택한다. 이 메뉴만 조회 범위를 바꾸며 checkout은 실행하지 않는다. Clear Filter로 전체로 돌아온다. 선택한 ref가 필터 밖이면 Show in All History를 제공한다.
- branch 더블클릭이나 Open Worktree로 기존 Worktree를 열면 이동 전의 명시적 필터를 유지하고 대상 HEAD 위치를 선택한다. 이동 실패 시 현재 Worktree와 조회 범위가 유지되고, Library 등에서 일반적인 다른 Repository를 열면 전체 이력으로 초기화한다.
- 아직 commit이 없으면 오류 대신 `No Commits Yet` 빈 상태를 표시한다.
- root commit은 빈 tree와 비교한 변경 파일과 patch를 표시한다.
- merge commit은 first parent와 비교한 변경 파일과 patch를 표시한다.
- rename 파일은 원래 경로를 함께 표시한다.
- 변경 파일이 없는 commit은 오류와 다른 빈 상태를 표시한다.
- History, 변경 파일 또는 patch 읽기가 실패하면 해당 영역에 오류와 `Try Again`을 표시한다.
- patch가 2MB를 넘으면 사용자가 16MB까지 확장할 수 있고, 그보다 크거나 UTF-8이 아니면 원인을 표시한다.
- 검색 결과가 없으면 별도 빈 상태와 `Clear Search`를 표시한다. Navigator에서 ref로 이동하면 텍스트 검색을 해제해 대상 commit이 검색에 가려지지 않게 한다.
- annotated tag는 실제 commit 위치에 표시하고 remote의 symbolic HEAD는 생략한다.
- detached HEAD는 branch ref가 없어도 목록과 graph에 포함한다.
- 검색으로 중간 commit이 숨겨지면 연결선을 생략하고 각 결과의 commit 점만 표시한다.

## 완료 확인

- History 진입과 commit 선택은 Repository나 index, working tree를 바꾸지 않는다.
- commit 행은 제목·작성자·시간·축약 SHA를 색 외의 텍스트로 식별할 수 있다.
- 선택 상세에서 제목·작성자 이메일·서명 상태를 확인할 수 있고, 상하 배치의 Details…에서 전체 SHA·parent와 줄바꿈을 보존한 원문을 읽을 수 있다.
- 상하 배치의 본문 미리보기는 공백·줄바꿈을 접어 가용 폭 안에서 두 줄로 표시한다. 이전/다음 commit 이동은 현재 검색·조회 범위를 벗어나지 않는다.
- 변경 파일은 상태와 경로를 색 외의 텍스트로 식별할 수 있고, 파일 선택은 해당 파일의 patch만 갱신한다.
- graph는 현재 HEAD와 local·remote-tracking branch, tag에서 도달 가능한 목록의 분기·합류를 표시하고 VoiceOver 이름은 root와 merge commit을 구분한다.
- 검색은 추가 Git 실행 없이 현재 읽은 commit 안에서 ref 이름까지 대상으로 수행한다.
- History 목록은 stash·notes ref를 포함하지 않으며, Stash 검사는 별도 `Stashes` 화면에서 제공한다.
- 선택한 일반 commit Revert는 [UC-31](uc-31-revert-commit.md), merge commit Revert는 [UC-32](uc-32-revert-merge-commit.md), 현재 branch mixed Reset은 [UC-33](uc-33-reset-current-branch.md), soft Reset은 [UC-34](uc-34-soft-reset-current-branch.md), hard Reset은 [UC-35](uc-35-hard-reset-current-branch.md), HEAD 이동 기록은 [UC-36](uc-36-inspect-reflog.md)에서 다룬다.

[사용자 흐름 문서로 돌아가기](../README.md)
