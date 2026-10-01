# UC-49 · 좁은 창에서 Navigator로 이동

> 우선순위: P1

| 항목 | 내용 |
| --- | --- |
| 사용자 목표 | 창이 좁아 Navigator가 접힌 상태에서 창 크기를 바꾸지 않고 목적지나 branch·remote·tag로 이동한다. |
| 시작 조건 | Repository Workspace의 창 폭이 마지막 Navigator 폭 + 728pt보다 좁아 Navigator가 접혀 있다. 기본 Navigator 폭 220pt일 때 기준은 948pt다. |
| 진입점 | 툴바의 Navigator 버튼, ⌃⌘S, 또는 문맥 바의 위치 칸(설정에 따라) |
| 완료 상태 | 고른 화면이 본문에 보이고 창 폭은 그대로다. 열렸던 패널이나 메뉴는 닫혀 있다. |

## 정상 흐름

1. 사용자가 툴바의 Navigator 버튼을 누른다. 설정 Appearance › Navigator in Narrow Windows에 따라 다음 중 하나가 열린다.
   - Floating Navigator(기본): 같은 Navigator가 툴바 버튼에 붙은 네이티브 팝오버로 뜬다. 폭은 마지막 사이드바 폭을 따르며 기본 220pt, 최대 320pt다. 높이는 본문 공간에 맞추되 최대 560pt다.
   - Toolbar Menu: 버튼이 메뉴가 되어 Workspace·Recovery·Branches·Remotes·Tags를 보인다.
   - Location Menu: 버튼은 비활성이고, 문맥 바의 branch 메뉴 뒤 위치 칸(`History`, `feature · Local branch`…)이 목적지·Remotes·Tags 메뉴를 연다.
2. 사용자가 항목을 고른다. 현재 위치에는 체크(메뉴) 또는 선택 표시(패널)가 붙어 있다.
3. Gallae가 본문을 그 화면으로 바꾸고 패널이나 메뉴를 닫는다. 창 폭은 바뀌지 않는다.
4. 다른 branch의 History가 필요하면 어느 설정에서든 문맥 바 branch 메뉴의 `Show History ▸`로 간다.

## 대안 흐름

- 패널을 연 채 바깥을 누르거나 Escape를 누르면 아무것도 고르지 않고 닫힌다.
- 패널이 열린 채 창을 마지막 Navigator 폭 + 728pt 이상으로 넓히면 패널이 닫히고 자동으로 접혔던 사이드바 Navigator가 돌아온다.
- ⌃⌘S는 Floating Navigator에서만 패널을 여닫는다. 메뉴 방식에서는 View 메뉴 항목이 비활성이다.
- 현재 화면이나 reference를 다시 골라도 패널이 닫힌다. Worktree 선택도 같은 방식으로 닫힌다.
- 패널을 다시 열거나 사이드바로 돌아와도 Navigator 검색어, remote 펼침·접힘, 선택과 목록 스크롤 위치를 유지한다. 목록 내용이나 가용 높이가 바뀌면 스크롤 가능한 범위에 맞추며, Worktrees 섹션이 나타나거나 사라질 때는 목록 처음으로 돌아간다. 다른 Repository를 열면 검색어, remote 펼침·접힘과 스크롤 위치를 초기화한다.

## 완료 확인

- 어떤 설정에서도 Navigator를 열거나 항목을 고를 때 창 크기가 바뀌지 않는다.
- 세 방식 모두 목적지 넷, remote, tag에 닿고, 현재 위치를 표시한다.
- 설정을 바꾸면 열려 있던 패널이 닫히고 다음 열기부터 새 방식이 적용된다.
- 키보드로 팝오버를 열고 항목을 고르거나 Escape로 닫을 수 있다. 포커스 이동·복귀와 시스템 모션 줄이기 설정은 실행한 macOS 앱에서 확인한다.

[사용자 흐름 문서로 돌아가기](../README.md)
