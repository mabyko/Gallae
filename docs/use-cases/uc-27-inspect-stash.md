# UC-27 · Stash 변경 검사

> 우선순위: P1

| 항목 | 내용 |
| --- | --- |
| 사용자 목표 | 보관한 작업의 파일과 patch를 Repository를 바꾸지 않고 확인한다. |
| 시작 조건 | Repository Workspace가 열려 있다. |
| 진입점 | Repository 헤더의 `Stashes` |
| 완료 상태 | 선택한 Stash의 식별 정보, 변경 파일과 선택 파일 patch가 같은 Workspace에 표시된다. |

## 정상 흐름

1. 사용자가 Repository 헤더에서 `Stashes`를 선택한다.
2. Gallae가 최신 Stash를 최대 100개까지 최신순으로 읽고 첫 항목을 선택한다.
3. Gallae가 선택한 Stash에 함께 저장된 tracked·untracked 파일을 읽고 첫 파일을 선택한다.
4. Gallae가 선택한 파일 하나의 patch를 표시한다.
5. 사용자는 방향키로 다른 Stash나 파일을 선택해 검토를 이어 간다.

## 대안 흐름

- 저장된 Stash가 없으면 오류 대신 `No Stashes` 빈 상태를 표시한다.
- rename 파일은 원래 경로를 함께 표시한다.
- 목록, 변경 파일 또는 patch 읽기가 실패하면 해당 영역에 오류와 `Try Again`을 표시한다.
- patch가 2MB를 넘으면 사용자가 16MB까지 확장할 수 있고, binary 또는 UTF-8이 아니면 원인을 표시한다.
- 다른 화면이나 항목으로 이동하면 진행 중인 조회 결과는 현재 선택에 적용하지 않는다.

## 완료 확인

- Stashes 진입과 항목·파일 선택은 Stash, HEAD, index와 working tree를 바꾸지 않는다.
- Stash 행은 ref·제목·시간·축약 SHA를 색 외의 텍스트로 식별할 수 있다.
- 변경 파일은 상태와 경로를 색 외의 텍스트로 식별할 수 있고, 파일 선택은 해당 파일의 patch만 갱신한다.
- Stash 생성은 [UC-28](uc-28-create-stash.md), 적용은 [UC-29](uc-29-apply-stash.md), 삭제는 [UC-30](uc-30-delete-stash.md)에서 다루며, 이 검사 흐름은 Repository를 바꾸지 않는다.

[사용자 흐름 문서로 돌아가기](../README.md)
