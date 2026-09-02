# UC-12 · Repository commit History 검사

> 우선순위: P1

| 항목 | 내용 |
| --- | --- |
| 사용자 목표 | 현재 작업선과 다른 branch·tag의 최근 변경 맥락, 선택한 commit의 내용을 읽는다. |
| 시작 조건 | commit이 하나 이상 있는 Repository Workspace가 열려 있다. |
| 진입점 | Navigator의 `History`(⌘2), 또는 Navigator에서 branch·tag 선택 |
| 완료 상태 | 선택한 commit의 메시지·작성자·revision·parent, 변경 파일과 선택 파일 patch가 같은 Workspace에 표시된다. |

## 정상 흐름

1. 사용자가 Navigator에서 `History`를 선택한다. branch나 tag를 선택하면 같은 화면이 그 ref 하나의 log로 좁혀지고, 헤더에 ref 이름과 종류(Local branch·HEAD·Worktree 위치·Tag)가 뜬다.
2. Gallae가 현재 HEAD, local·remote-tracking branch와 tag에서 도달 가능한 최신 commit을 합쳐 최대 100개까지 topology 순서로 읽는다. ref 하나를 골랐으면 `refs/heads/…`·`refs/tags/…`로 정확히 그 ref만 읽는다.
3. Gallae가 정확한 현재 HEAD commit을 처음 선택하고(ref 하나면 그 ref의 끝 commit), 사용자가 필요하면 목록에서 다른 commit을 선택한다.
4. Gallae가 선택한 commit의 메타데이터와 first-parent 기준 변경 파일을 읽고 첫 파일을 선택한다.
5. Gallae가 선택한 파일의 patch를 읽는다.
6. 사용자는 방향키로 다른 commit이나 파일을 선택해 같은 화면에서 검토를 이어 간다.
7. 필요하면 메시지·작성자·이메일·SHA·ref를 입력해 이미 읽은 목록을 좁힌다.
8. commit에 닿은 branch와 tag가 있으면 행에서 이름과 종류를 확인한다.
9. 목록 왼쪽 graph에서 일반 commit과 merge의 부모 관계를 확인한다.

## 대안 흐름

- 아직 commit이 없으면 오류 대신 `No Commits Yet` 빈 상태를 표시한다.
- root commit은 빈 tree와 비교한 변경 파일과 patch를 표시한다.
- merge commit은 first parent와 비교한 변경 파일과 patch를 표시한다.
- rename 파일은 원래 경로를 함께 표시한다.
- 변경 파일이 없는 commit은 오류와 다른 빈 상태를 표시한다.
- History, 변경 파일 또는 patch 읽기가 실패하면 해당 영역에 오류와 `Try Again`을 표시한다.
- patch가 2MB를 넘으면 사용자가 16MB까지 확장할 수 있고, 그보다 크거나 UTF-8이 아니면 원인을 표시한다.
- 검색 결과가 없으면 별도 빈 상태와 `Clear Search`를 표시한다.
- annotated tag는 실제 commit 위치에 표시하고 remote의 symbolic HEAD는 생략한다.
- detached HEAD는 branch ref가 없어도 목록과 graph에 포함한다.
- 검색으로 중간 commit이 숨겨지면 연결선을 생략하고 각 결과의 commit 점만 표시한다.

## 완료 확인

- History 진입과 commit 선택은 Repository나 index, working tree를 바꾸지 않는다.
- commit 행은 제목·작성자·시간·축약 SHA를 색 외의 텍스트로 식별할 수 있다.
- 선택 상세에는 제목·본문·작성자 이메일·전체 SHA·parent가 표시된다.
- 변경 파일은 상태와 경로를 색 외의 텍스트로 식별할 수 있고, 파일 선택은 해당 파일의 patch만 갱신한다.
- graph는 현재 HEAD와 local·remote-tracking branch, tag에서 도달 가능한 목록의 분기·합류를 표시하고 VoiceOver 이름은 root와 merge commit을 구분한다.
- 검색은 추가 Git 실행 없이 현재 읽은 최대 100개 commit 안에서 ref 이름까지 대상으로 수행한다.
- History 목록은 stash·notes ref를 포함하지 않으며, Stash 검사는 별도 `Stashes` 화면에서 제공한다.
- 선택한 일반 commit Revert는 [UC-31](uc-31-revert-commit.md), merge commit Revert는 [UC-32](uc-32-revert-merge-commit.md), 현재 branch mixed Reset은 [UC-33](uc-33-reset-current-branch.md), soft Reset은 [UC-34](uc-34-soft-reset-current-branch.md), hard Reset은 [UC-35](uc-35-hard-reset-current-branch.md), HEAD 이동 기록은 [UC-36](uc-36-inspect-reflog.md)에서 다룬다.

[사용자 흐름 문서로 돌아가기](../README.md)
