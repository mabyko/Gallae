# UC-49 · 좁은 창에서 Navigator로 이동

> 우선순위: P1

| 항목 | 내용 |
| --- | --- |
| 사용자 목표 | 창이 좁아 Navigator가 접힌 상태에서 창 크기를 바꾸지 않고 목적지나 branch·remote·tag로 이동한다. |
| 시작 조건 | Repository Workspace가 948pt보다 좁은 창에 열려 있어 Navigator가 접혀 있다. |
| 진입점 | 툴바의 Navigator 버튼, ⌃⌘S, 또는 문맥 바의 위치 칸(설정에 따라) |
| 완료 상태 | 고른 화면이 본문에 보이고 창 폭은 그대로다. 열렸던 패널이나 메뉴는 닫혀 있다. |

## 정상 흐름

1. 사용자가 툴바의 Navigator 버튼을 누른다. 설정 Appearance › Navigator in Narrow Windows에 따라 다음 중 하나가 열린다.
   - Floating Navigator(기본): 같은 Navigator가 본문 왼쪽 위에 220pt 패널로 뜬다.
   - Toolbar Menu: 버튼이 메뉴가 되어 Workspace·Recovery·Branches·Remotes·Tags를 보인다.
   - Location Menu: 버튼은 비활성이고, 문맥 바의 branch 메뉴 뒤 위치 칸(`History`, `feature · Local branch`…)이 목적지·Remotes·Tags 메뉴를 연다.
2. 사용자가 항목을 고른다. 현재 위치에는 체크(메뉴) 또는 선택 표시(패널)가 붙어 있다.
3. Gallae가 본문을 그 화면으로 바꾸고 패널이나 메뉴를 닫는다. 창 폭은 바뀌지 않는다.
4. 다른 branch의 History가 필요하면 어느 설정에서든 문맥 바 branch 메뉴의 `Show History ▸`로 간다.

## 대안 흐름

- 패널을 연 채 바깥을 누르거나 Escape를 누르면 아무것도 고르지 않고 닫힌다.
- 패널이 열린 채 창을 948pt 이상으로 넓히면 패널이 닫히고 사이드바 Navigator가 돌아온다.
- ⌃⌘S는 Floating Navigator에서만 패널을 여닫는다. 메뉴 방식에서는 View 메뉴 항목이 비활성이다.

## 완료 확인

- 어떤 설정에서도 Navigator를 열거나 항목을 고를 때 창 크기가 바뀌지 않는다.
- 세 방식 모두 목적지 넷, remote, tag에 닿고, 현재 위치를 표시한다.
- 설정을 바꾸면 열려 있던 패널이 닫히고 다음 열기부터 새 방식이 적용된다.

[사용자 흐름 문서로 돌아가기](../README.md)
