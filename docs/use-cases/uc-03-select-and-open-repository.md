# UC-03 · 발견한 Repository 선택 및 열기

> 우선순위: P0

| 항목 | 내용 |
| --- | --- |
| 사용자 목표 | 목록을 훑고 원하는 Repository로 이동한다. |
| 시작 조건 | Library에 하나 이상의 Repository가 있다. |
| 진입점 | Recent 또는 Library Folder의 Repository 목록 |
| 완료 상태 | 선택한 Repository Workspace가 열린다. |

## 정상 흐름

1. 사용자가 방향키나 포인터로 Repository를 선택한다.
2. 선택한 Repository의 경로, 현재 브랜치, 변경 유무와 열 수 있는 상태를 확인한다.
3. commit 수와 최근 활동은 선택한 Repository에서만 읽는다.
4. Return, 이중 클릭 또는 Open Repository 명령으로 연다.
5. 같은 메인 윈도우가 선택한 Repository Workspace로 전환된다.

## 상호작용 원칙

- Repository를 선택하면 요약만 바뀐다.
- 선택만으로 Workspace를 열지 않는다.
- Open은 Active Repository를 바꾸는 별도 명령이다.
- 마우스와 키보드 어느 쪽으로도 같은 흐름을 마칠 수 있어야 한다.

## 대안 흐름

- 선택한 Repository에 접근할 수 없다면 원인과 다시 연결하는 방법을 안내한다.
- 탐색 도중 Repository가 사라지면 목록 상태를 갱신하되 다른 선택은 유지한다.
- Open에 실패해도 Repository Library와 기존 Workspace는 그대로 둔다.

[사용자 흐름 문서로 돌아가기](../README.md)
