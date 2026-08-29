# UC-01 · Repository 직접 열기

> 우선순위: P0

| 항목 | 내용 |
| --- | --- |
| 사용자 목표 | 알고 있는 Repository를 바로 열어 상태를 읽는다. |
| 시작 조건 | 앱이 실행 중이거나 Repository 경로와 함께 실행된다. |
| 진입점 | 파일 메뉴의 열기 명령, Repository Library의 Choose Folder, Finder에서 전달된 경로 |
| 완료 상태 | 유효한 Repository Workspace의 Changes가 열리고 최근 항목에 반영된다. |

## 정상 흐름

1. 사용자가 폴더를 선택하거나 경로를 전달한다.
2. Gallae가 해당 경로를 읽을 수 있는 로컬 Git 작업 트리인지 확인한다.
3. Repository 이름, 경로, HEAD와 작업 트리 상태를 읽는다.
4. Repository Workspace의 Changes를 연다.

## 대안 흐름

- Repository Library의 Choose Folder에서 일반 폴더를 골랐다면 Library Folder로 등록하고 탐색한다.
- 파일 메뉴의 직접 열기에서 일반 폴더를 골랐다면 Git Repository가 아니라고 설명하고 다른 폴더를 고르게 한다.
- bare Repository라면 유효한 Git 저장소지만 첫 슬라이스에서 열 수 없는 유형이라고 설명한다.
- 경로를 읽을 수 없다면 원인을 설명하고 다시 선택하거나 취소하게 한다.
- 확인 과정에서 실패해도 이미 열려 있던 Workspace는 유지한다.

## 완료 확인

- Active Repository와 HEAD가 화면에 보인다.
- 읽기 실패가 Git 상태나 기존 Workspace를 바꾸지 않는다.
- Library Folder 밖의 Repository는 최근 항목에 남고, 기존 항목과 중복되지 않는다.

[사용자 흐름 문서로 돌아가기](../README.md)
