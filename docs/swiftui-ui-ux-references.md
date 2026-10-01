# SwiftUI UI/UX 참고 근거

Gallae에서 반복 조작을 줄이는 참고 기록이다. 다른 앱의 코드·자산·화면 치수를 옮기지 않고 작업 흐름만 참고한다. 공식 자료와 원본 미디어의 확인 범위를 구분하며, 미확인 영상의 동작이나 게시 날짜를 추정하지 않는다. 출처에서 확인한 사실과 Gallae의 적용 판단을 나눠 적었다.

| 출처 | 확인한 범위 | Gallae에서 줄일 작업 | 적용 판단 |
| --- | --- | --- | --- |
| Mitchell Hashimoto의 [Command Palette 원문](https://x.com/mitchellh/status/1914380359107797146), [Ghostty 공식 소스](https://github.com/ghostty-org/ghostty/blob/main/macos/Sources/Features/Command%20Palette/CommandPalette.swift) | 현재 소스는 검색어로 명령을 좁히고 방향키로 고른 뒤 실행한다. 제목 아래 설명과 단축키도 표시한다. 원문 영상은 확인하지 않았다. | 메뉴를 차례로 열어 명령을 찾는 수고를 줄이는 방식이다. 현재 Navigator와 History의 검색을 먼저 활용한다. | 별도 palette는 보류한다. 기존 검색으로 닿지 않는 명령이 실제로 늘어날 때 검토한다. |
| Mitchell Hashimoto의 [Zed 스타일 SwiftUI 시안 원문](https://x.com/mitchellh/status/1913331535945859235) | 원문 링크만 확보했고 영상은 확인하지 않았다. | 확인한 상호작용이 없어 Gallae에서 줄일 조작을 판단하지 않았다. | 적용을 보류하며 이번 구현의 근거로 사용하지 않는다. |
| Axel Le Pennec의 [원문과 답글](https://x.com/alpennec/status/1885629083649757313) | 본문·답글 확인. Picker에는 같은 subtitle 표현을 적용할 수 없다는 지적에 작성자가 동의한다. | 제목·설명·아이콘의 계층으로 선택 대상을 구분하면 항목을 열었다가 취소하는 일을 줄일 수 있다. | 기존 macOS Menu 동작은 유지한다. Menu·Button·Picker와 모든 OS가 같은 표현을 지원한다고 단정하지 않는다. |
| Commit+의 [Threads 원문](https://www.threads.com/@commitplus.app/post/DditY92k5od), [공식 소개](https://commitplus.app), [공식 revision 안내](https://commitplus.app/blog/browse-and-compare-git-revisions) | 첫 스크린샷을 확대 확인했다. 왼쪽 탐색, 중앙 graph와 message·author·date·commit 열, 하단 대상 헤더와 files·diff가 보인다. 공식 자료는 Swift·SwiftUI와 checkout 없는 탐색을 설명한다. 영상은 확인하지 않았다. | 구획별 대상과 조작을 분리한 화면을 참고한다. Gallae에서는 좁은 History 헤더의 대상 설명이 작업 버튼과 폭을 다투고, 좁은 revision 화면에서는 다음 파일마다 메뉴를 다시 열어야 한다. | 우리 diff 헤더의 `ViewThatFits`를 History 헤더에도 적용하고 Fetch의 보조 작업을 메뉴에 묶는다. 파일 메뉴 옆에는 순번·이전·다음을 추가한다. 파일 선택 binding만 바꾸며 Git 쓰기 작업은 추가하지 않는다. 이 개선은 확인한 구획 배치와 Gallae의 반복 조작에서 도출했으며 Commit+의 동일 동작을 확인한 것은 아니다. |
| Stephan Casas의 [Inspector 원문](https://x.com/stephancasas/status/1665174127575986176) | 원문 링크만 확보했고 영상은 확인하지 않았다. | 확인한 상호작용이 없어 Gallae에서 줄일 조작을 판단하지 않았다. | 새 inspector는 보류하며 이번 구현의 근거로 사용하지 않는다. |

이번 범위는 History 헤더의 가용 폭 대응과 revision 파일 이동이다. 기존 선택·검색·diff 흐름을 이어 쓰고 첫·마지막 파일의 이동 경계를 지킨다. 좁은 창, 긴 파일명과 키보드 접근을 검증한다. 새 palette와 inspector는 보류한다.
