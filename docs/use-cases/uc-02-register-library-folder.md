# UC-02 · Library Folder 등록 및 탐색

> 우선순위: P0

| 항목 | 내용 |
| --- | --- |
| 사용자 목표 | 관리하는 폴더 아래의 Repository를 한 번에 찾는다. |
| 시작 조건 | Repository Library가 열려 있다. |
| 진입점 | Repository Library의 Choose Folder 또는 Library Folder 추가 명령 |
| 완료 상태 | 허용된 범위가 저장되고 발견한 Repository가 Library에 표시된다. |

## 정상 흐름

1. 사용자가 표준 macOS 폴더 선택기로 일반 폴더를 고른다. Repository를 고르면 Library에 등록하지 않고 바로 연다.
2. Gallae가 탐색할 범위를 표시하고 탐색을 시작한다.
3. Repository를 발견하는 대로 Library Folder 아래에 추가한다.
4. 탐색이 끝나면 결과 수와 마지막 탐색 상태를 갱신한다.
5. 다음 실행에서는 저장한 Library Folder를 복원하고 현재 내용을 다시 탐색한다.

## 대안 흐름

- 사용자가 선택을 취소하면 아무것도 바꾸지 않는다.
- 진행 중인 탐색을 취소하면 이미 발견한 Repository는 유지하고 중단 상태와 재탐색 명령을 표시한다.
- Repository를 찾지 못하면 탐색이 정상적으로 끝났음을 알리고 다른 폴더 선택과 재탐색 명령을 함께 둔다.
- 일부 경로를 읽지 못해도 나머지 탐색은 계속하고 부분 실패를 요약한다.
- Library Folder가 이동했거나 읽을 수 없게 됐다면 항목을 지우지 않고 다시 찾는 방법을 안내한다.
- 사용자는 저장한 Library Folder를 다시 연결하거나 Library에서 제거할 수 있으며, 디스크의 파일은 바꾸지 않는다.

## 완료 확인

- Gallae는 사용자가 허용한 폴더 밖을 탐색하지 않는다.
- symlink를 따라가지 않고 숨김·package 디렉터리와 `.git` 내부를 건너뛴다.
- 발견한 Repository는 탐색이 끝나기 전에도 목록에 나타난다.
- 탐색은 Library와 Repository Workspace 조작을 막지 않는다.

[사용자 흐름 문서로 돌아가기](../README.md)
