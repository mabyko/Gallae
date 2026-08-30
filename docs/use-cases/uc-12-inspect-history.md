# UC-12 · 현재 HEAD의 commit History 검사

> 우선순위: P1

| 항목 | 내용 |
| --- | --- |
| 사용자 목표 | 현재 작업선의 최근 변경 맥락과 선택한 commit의 내용을 읽는다. |
| 시작 조건 | commit이 하나 이상 있는 Repository Workspace가 열려 있다. |
| 진입점 | Repository 헤더의 `History` |
| 완료 상태 | 선택한 commit의 메시지·작성자·revision·parent와 patch가 같은 Workspace에 표시된다. |

## 정상 흐름

1. 사용자가 Repository 헤더에서 `History`를 선택한다.
2. Gallae가 현재 HEAD에서 도달 가능한 최신 commit을 최대 100개까지 최신순으로 읽는다.
3. 사용자가 목록에서 commit을 선택한다.
4. Gallae가 선택한 commit의 메타데이터와 first-parent 기준 전체 patch를 읽는다.
5. 사용자는 방향키로 다른 commit을 선택해 같은 화면에서 검토를 이어 간다.
6. 필요하면 메시지·작성자·이메일·SHA를 입력해 이미 읽은 목록을 좁힌다.

## 대안 흐름

- 아직 commit이 없으면 오류 대신 `No Commits Yet` 빈 상태를 표시한다.
- root commit은 빈 tree와 비교한 patch를 표시한다.
- merge commit은 first parent와 비교한 patch를 표시한다.
- 목록 또는 patch 읽기가 실패하면 해당 영역에 오류와 `Try Again`을 표시한다.
- patch가 2MB를 넘으면 사용자가 16MB까지 확장할 수 있고, 그보다 크거나 UTF-8이 아니면 원인을 표시한다.
- 검색 결과가 없으면 별도 빈 상태와 `Clear Search`를 표시한다.

## 완료 확인

- History 진입과 commit 선택은 Repository나 index, working tree를 바꾸지 않는다.
- commit 행은 제목·작성자·시간·축약 SHA를 색 외의 텍스트로 식별할 수 있다.
- 선택 상세에는 제목·본문·작성자 이메일·전체 SHA·parent가 표시된다.
- 검색은 추가 Git 실행 없이 현재 읽은 최대 100개 commit 안에서만 수행한다.
- 이 흐름은 graph, 모든 branch/ref, 파일별 drill-down과 branch 이동·생성을 포함하지 않는다.

[사용자 흐름 문서로 돌아가기](../README.md)
