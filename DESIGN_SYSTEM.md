# Gallae UI 및 테마 시스템

> 상태: 초안 · 2026-08-27

## 목적

Gallae의 Git 동작과 기존 기능을 유지하면서 탐색, 검토, 작성의 화면 구조와 시각 위계를 일관되게 개선한다. 색, 재질, 간격, 타이포그래피와 컨트롤 표현은 같은 테마 규칙을 따른다. Theme와 Appearance Mode는 제품 개념이고, Prototype Variant는 디자인 비교용 장치다.

| 개념 | 의미 | 현재 값 |
| --- | --- | --- |
| Theme | 색, 타이포그래피, 밀도와 컴포넌트 스타일을 아우르는 전체 시각 체계 | Gallae |
| Appearance Mode | 같은 Theme 안에서 밝기 팔레트를 선택하는 화면 모드 | System, Light, Dark |
| Material Response | 같은 Theme가 macOS 접근성 설정에 응답하는 방식 | Standard(시스템 재질), Reduced Transparency(불투명), Increased Contrast(고대비) |
| Prototype Variant | 정보 구조·재질 후보를 비교하는 시안 전용 장치 | 시안 5의 `?theme=glass·neutral·contrast` |

## 테마 seam

실제 앱에서는 하나의 `GallaeTheme` 모듈이 시각 규칙을 모은다. 화면이 알아야 하는 역할은 다음 네 가지뿐이다.

- `colors`: surface, text, selection, action, Git 상태처럼 의미가 있는 색
- `metrics`: 간격, 행 높이, 모서리와 구분선처럼 밀도를 만드는 값
- `typography`: title, body, caption, code 같은 글자 역할
- `motion`: 즉시 반응, 상태 전환과 Reduce Motion 규칙
- `materials`: 사이드바·툴바의 시스템 재질 사용과 콘텐츠 패널의 불투명 규칙, 접근성 응답별 팔레트 선택

흐름은 다음과 같다.

```text
Primitive values
      ↓
Semantic GallaeTheme
      ↓
Component styles
      ↓
Feature views
```

| 층 | 책임 | 예시 | 직접 사용하는 곳 |
| --- | --- | --- | --- |
| Primitive | 원시 팔레트와 수치 | neutral-850, blue-650, space-2 | 테마 구현 내부 |
| Semantic | 제품 안에서의 의미 | surfaceContent, textSecondary, statusAdded | 컴포넌트 스타일 |
| Component | 반복되는 화면 요소의 기본값 | selectedRowBackground, primaryButtonFill, diffAddedBackground | Feature view |

Feature view에는 임의의 RGB 값이나 화면별 간격 상수를 넣지 않는다. Theme 전체를 바꿀 때는 Semantic 층의 매핑을 바꾸고, 특정 요소만 바꿀 때는 Component 층을 조정한다.

## SwiftUI 적용 규칙

- `GallaeTheme`는 `colors`, `metrics`, `typography`, `motion`, `materials`를 가진 하나의 값 모듈로 둔다.
- `AppearanceMode`는 `.system`, `.light`, `.dark` 상태로 Theme와 분리한다.
- Material Response는 `@Environment(\.accessibilityReduceTransparency)`, `@Environment(\.colorSchemeContrast)`와 설정의 Translucent 값을 합쳐 앱 루트에서 한 번 결정하고, 해석된 Theme에 담아 내려보낸다.
- 앱 루트에서 `.system`을 SwiftUI의 현재 `colorScheme`으로 해석하고 Gallae Theme의 해당 팔레트를 선택한다.
- 해석된 Theme는 SwiftUI Environment에 넣고 하위 화면은 `@Environment`로 읽는다.
- 실제 Theme가 하나뿐이므로 provider protocol, factory, 테마 저장소나 Theme 선택 UI는 만들지 않는다.
- Git과 Repository 모듈은 `Color`, `Font`, `ShapeStyle` 같은 SwiftUI 타입을 알지 않는다.
- 공통 `ButtonStyle`, 선택 행, diff 행 표현은 같은 규칙이 두 번 이상 나타날 때만 테마 모듈 안으로 올린다.
- 열 구성이나 화면 이동처럼 구조적인 UI 변경은 Feature view에서 처리한다. 테마 값으로 레이아웃을 분기하지 않는다.

현재 SwiftUI 문서에서는 `EnvironmentValues`의 사용자 정의 값을 `@Entry`로 선언하고 Scene 또는 View의 `environment` modifier로 하위 뷰에 전달할 수 있다. 구체 코드는 Xcode 프로젝트를 만들며 확정한 SDK와 최소 macOS 버전에 맞춰 작성한다.

## 재질과 접근성 응답

기본 모습은 macOS가 `NavigationSplitView` 사이드바와 통합 툴바에 주는 시스템 재질이다. Gallae는 이 재질 위에 배경을 칠하지 않는다. 목록, diff, 상세 같은 콘텐츠 패널은 항상 불투명하다.

| 응답 | 조건 | 사이드바·툴바 | 선택 | diff |
| --- | --- | --- | --- | --- |
| Standard | 기본 | 시스템 재질 | accent 틴트, 모서리 8pt | 기본 팔레트 |
| Reduced Transparency | 시스템 투명도 줄이기가 켜짐, 또는 설정의 Translucent Sidebar and Toolbar가 꺼짐 | 불투명 뉴트럴(시안 2·A) | accent 틴트, 모서리 6pt | 기본 팔레트 |
| Increased Contrast | 시스템 대비 증가가 켜짐 | 불투명, 구분선·글자 대비 상향 | accent 채움에 흰 글자, 모서리 4pt | 사용자 지정 글자 크기 유지, 추가·삭제 행 왼쪽 컬러 바 |

세 응답은 별개 테마가 아니라 한 테마의 Semantic 매핑 세 벌이다. 사용자는 테마를 고르지 않고, 설정에서 Translucent Sidebar and Toolbar, Compact Rows와 UI·코드 폰트를 조정한다. 대비 증가는 시스템 설정을 따르며 앱 설정으로 켜지 않는다.

## 툴바 묶음과 History 헤더

Workspace는 B 시안의 검토 중심 구조를 따른다. History·Changes·파일·diff 헤더는 공통 제목·아이콘·개수 표현을 사용하고, 작업 대상과 보조 도구를 별도 줄에 배치한다. 공통 패널 여백은 좌우 14pt·위아래 8pt, 내부 간격은 8pt, 인셋 패널 모서리는 8pt다. 인셋 패널은 시스템 `controlBackgroundColor`와 `separatorColor`를 사용한다. 글꼴 설정·강조색·재질·Git 의미 색은 유지한다. 기본 행의 세로 여백은 6pt, 넓은 History 행은 3pt이며 Compact Rows의 3pt·2pt 값은 유지한다. 변경 파일 목록 기본 폭은 230pt·최대 폭은 320pt이며 저장한 폭과 좁은 영역의 파일 선택 메뉴·앞뒤 이동을 유지한다.

작업 브랜치와 작업 사본 상태는 Workspace 상단에 구분해 표시한다. Navigator는 Workspace·Recovery 화면 탐색과 References 탐색을 분리하며 참조 필터를 참조 목록 위에 둔다. 같은 사이드바를 Floating Navigator에서도 사용한다. 키보드 이동, 검색어, remote 접힘, 스크롤 위치와 선택 보존은 유지한다.

History 제목과 조회 범위 메뉴, 선택 ref의 이름·종류·대상별 작업을 분리한다. Graph View Settings와 검색을 유지하며 선택 ref의 작업 줄은 좁은 폭에서 다음 줄로 내려간다. 두 History Layout 모두 Commit review 막대에서 이전·다음 커밋으로 이동한다. Expand Review는 Top and Bottom에 유지한다. 상하 목록의 초기 높이는 220pt이며 저장한 높이는 창 안에 맞춰 유지한다. 검토 영역은 공간이 허용하는 한 최소 260pt를 확보해 작은 창에서도 diff를 읽을 수 있게 한다. UI 기본 크기에서 320pt보다 짧은 검토 영역에서는 작성자·메시지를 압축해 diff 공간을 남긴다. UI 글꼴이 커지면 압축 기준도 그 비율로 늘린다. 압축된 요약은 작성자·짧은 SHA·서명을 표시하며 이메일·시각·본문은 Details에서 확인한다. 선택 커밋은 제목·작성자·짧은 SHA·서명·본문 미리보기를 한 인셋 패널에 묶고 Rebase Plan·Revert·Reset·Cherry-Pick은 그 아래에 직접 노출한다. 작업 버튼은 폭에 따라 줄을 나눈다. Details에는 전체 메시지와 펼치기, 전체 SHA·부모 SHA·서명과 같은 작업 버튼을 유지한다.

Changes는 파일 목록 제목과 Status·Folders 선택을 분리한다. 커밋 작성은 Create commit / Amend commit 패널로 묶고 Summary·Description의 고정 레이블, staged 개수, Amend, Stage All, Commit과 ⌘↩ 안내를 표시한다. 본문은 두 줄에서 시작해 세 줄까지 늘어난 뒤 필드 안에서 스크롤한다. 초안과 Amend 사전 입력, Git 작업·확인·비활성 조건은 그대로 유지한다. diff는 파일 이름·경로·추가/삭제 개수와 레이아웃·파일 작업을 구분하며 충돌 작업 버튼도 좁은 폭에서 줄을 나눈다. Library·Stashes·Reflog도 공통 패널 제목과 중립적인 메타데이터 패널을 따른다.

실험실의 Visual Diff는 파일 diff 헤더의 Unified·Split 옆에 Visualize를 추가한다. 클릭하면 현재 Changes·History·Stash 비교에서 변경 파일과 diff 기호 참조 관계를 로컬 그래프로 생성한다. 시각화 중에는 Visualize 버튼을 Back to Diff로 바꾸며, 새 파일처럼 Split이 없는 경우에도 복귀할 수 있다. Unified·Split으로도 복귀하며 지원하지 않는 Split은 Unified로 표시한다. 파일 헤더와 그래프 헤더는 내용 높이에 맞추고 그래프가 남은 공간을 채운다. Local diff 표시와 실제 비교 범위·파일 수를 그래프 헤더에 둔다. 외부 가져오기는 More로 이동하며 Imported snapshot으로 구분한다. Refresh는 현재 비교를 다시 생성한다. 그래프는 Light·Dark를 따르고 선택한 파일 노드를 강조한다. 전체 화면에는 Exit Full Screen을 표시하며 Esc는 확대·이동 상태를 유지한 채 원래 시각화 영역으로 복귀한다. 내장 그래프의 Esc와 파일 노드 선택은 코드 diff로 돌아간다. Labs 기본값은 꺼짐이며 끄면 그래프와 전체 화면을 정리한다.

B의 디자인은 History Layout과 별개다. Top and Bottom과 C에 해당하는 기존 Side by Side 모두 같은 컴포넌트를 사용하고 `historyLayout`의 저장값을 유지한다. 시안 이름을 새로운 설정 항목으로 추가하거나 개인 선택을 강제로 덮어쓰지 않는다.

상단 툴바는 탐색(Navigator·Library) 다음에 동기화(Fetch·Pull·Push), 통합(Merge / Rebase), 새로고침(Refresh) 순서로 놓는다. Refresh는 맨 끝에 홀로 둔다. macOS 26 이상에서는 `ToolbarItem`·`ToolbarItemGroup`을 그대로 두고 각 항목에 `.sharedBackgroundVisibility(.hidden)`을 붙여 항상 보이는 유리 캡슐을 없앤 뒤, 버튼과 Fetch 메뉴 뒤에 `toolbarBezel()`로 무광 bezel을 그린다. bezel은 `controlColor`를 30% 불투명도로 옅게 채우고 `.separator` 1pt 테두리를 두른 모서리 8pt 둥근 사각형이며, 컨트롤 프레임보다 위아래 2pt씩 안쪽에 그린다. 유리·그림자 없이 콘텐츠 패널의 조용한 버튼보다 한 단계 더 가볍다. 툴바의 `.buttonStyle(.bordered)`는 macOS 26 툴바 안에서 아무것도 그리지 않아 쓰지 않는다. 장식 사각형은 background에만 있어 클릭을 가로채지 않고 접근성 트리에도 오르지 않는다. 두 색은 시스템 의미 색이므로 Light·Dark와 Increase Contrast에 따라 바뀐다. hover·누름·키보드 포커스·비활성·메뉴·overflow는 시스템 그대로다. 묶음 사이의 `ToolbarSpacer(.fixed)`가 동기화·통합·새로고침을 간격으로 구분한다. Library 화면의 Choose Folder도 같은 처리를 받는다. 창 단위 `toolbarBackgroundVisibility`는 Reduced Transparency의 불투명 툴바 배경을 맡는 별개 설정이며 버튼 캡슐과 무관하다. 좁은 창에서 시스템이 만드는 overflow(») 버튼의 유리 원형은 공개 API로 바꿀 수 없다. SwiftUI의 `toolbarOverflowMenu`는 macOS에서 사용할 수 없고 `NSToolbar`에도 overflow 모양 속성이 없으므로 시스템 모습을 그대로 둔다. macOS 15에서는 같은 순서로 두되 Pull·Push만 한 개짜리 `ControlGroup`과 `ToolbarDivider`로 묶고, Merge / Rebase와 Refresh는 각각 `ToolbarItem`으로 둔다. 두 경로는 같은 버튼 정의를 공유하므로 이름·단축키·도움말·접근성 이름은 OS에 따라 달라지지 않는다.

History의 조회 범위 메뉴는 `All Branches & Tags` 또는 `Filter: <ref>`를 표시하며 필터가 있을 때 Clear Filter를 제공한다. 선택 ref 패널에는 `<ref> · Local branch / Remote / Tag`와 대상별 Switch·Check Out·Fetch를 표시하고 HEAD에 `· HEAD`를 붙인다. Remote의 Fetch & Prune·Edit…는 Remote Actions 메뉴에 유지한다. 조회 범위와 작업 브랜치는 서로 다른 개념이며 범위 변경은 checkout을 실행하지 않는다. Expand Review로 목록이 가려졌을 때만 검토 막대에 범위를 반복한다.

좁은 창의 Floating Navigator는 툴바 Navigator 버튼에 붙은 네이티브 팝오버다. 사이드바와 같은 Navigator를 사용하고 검색어, remote 펼침·접힘과 선택을 공유한다. 폭은 마지막 사이드바 폭(기본 220pt, 최대 320pt)을 따르며 높이는 본문 공간 안에서 최대 560pt로 제한한다. 창 폭이 마지막 Navigator 폭 + 728pt보다 작으면 사이드바를 접고 팝오버로 탐색하며 창을 키우지 않는다. 같은 항목을 다시 선택해도 닫힌다. 팝오버의 연결 위치·등장과 퇴장·바깥 클릭·키보드 포커스는 시스템에 맡기며 별도 모션 시스템을 만들지 않는다. 포커스 이동·복귀와 Reduce Motion 응답은 macOS 앱에서 검증한다.

## 현재 시안

시안 2(`prototype/gallae-workspace`)는 정보 구조 후보 A·B·C를 비교한다. 시안 5는 채택한 구조 위에서 세 Material Response와 밀도를 비교하는 로컬 일회용 HTML이며 저장소에 넣지 않는다. 시안 5의 토큰은 `:root[data-theme]`로 응답별 Semantic 값을 덮어쓰고 Light·Dark를 각각 가지며, 설정 창 목업의 두 토글과 시스템 접근성 토글 시뮬레이션으로 응답 전환을 확인한다. 제품에서는 시스템 설정과 두 개의 앱 설정으로만 응답이 결정된다.

구현은 `Gallae/GallaeTheme.swift`다. `GallaeMaterialResponse.resolve`가 응답을 정하고 `GallaeTheme.resolve(response:compactRows:)`가 그 응답과 밀도의 Semantic 값을 돌려준다. 응답별로 달라지는 값은 배지·diff 배경 농도, diff 컬러 바 폭, 행 세로 여백, 사이드바·툴바의 재질 사용 여부뿐이며 색 이름과 배치는 같다.

## 변경 방법

| 바꾸려는 것 | 수정할 층 |
| --- | --- |
| 전체 색감과 스타일 | Theme의 Semantic·Component |
| Light·Dark 팔레트 동작 | Theme 내부 Appearance 매핑 |
| 기본 밀도, 글자 단계, 모서리 | Primitive와 Semantic |
| 버튼, 선택 행, diff 한 종류 | Component |
| 접근성 응답(불투명·고대비) 팔레트 | Theme 내부 Material Response 매핑 |
| 패널 배치나 탐색 구조 | Feature view |

## 지금 만들지 않는 것

사용자 제작 Theme, 외부 Theme 파일, Theme 마켓, 런타임 편집기와 플러그인 interface는 만들지 않는다. 테마 선택 UI도 만들지 않는다. 시안 5의 A·B·C는 고를 수 있는 테마가 아니라 한 테마의 접근성 응답이며, 설정에서 Translucent Sidebar and Toolbar, Compact Rows와 UI·코드 폰트를 조정한다. 실제 요구가 생기기 전까지 하나의 Gallae Theme와 Light·Dark Appearance, 세 응답이면 충분하다.

## 공개 근거

- [SwiftUI EnvironmentValues](https://developer.apple.com/documentation/swiftui/environmentvalues)
- [SwiftUI ColorScheme](https://developer.apple.com/documentation/swiftui/colorscheme)
- [Apple Human Interface Guidelines: Color](https://developer.apple.com/design/human-interface-guidelines/color)
- [Apple Human Interface Guidelines: Materials](https://developer.apple.com/design/human-interface-guidelines/materials)
- [SwiftUI EnvironmentValues: accessibilityReduceTransparency](https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityreducetransparency)
- [SwiftUI ColorSchemeContrast](https://developer.apple.com/documentation/swiftui/colorschemecontrast)

## 사용자 폰트 설정

Settings → Appearance → Fonts에서 UI와 Code & Diff의 글꼴(face)·크기를 각각 저장한다. UI는 설치된 글꼴을, Code & Diff는 설치된 고정폭 글꼴을 선택하며 기본값은 시스템 글꼴이다. 크기는 10–24pt이며 설정 즉시 반영하고 Reset Fonts로 복원한다. 글꼴 선택은 이름 검색이 가능한 팝오버를 사용하며 클릭 또는 방향키·Enter로 선택한다. 크기 숫자와 증감 버튼은 오른쪽에 붙여 배치한다. 글꼴이 없어지거나 코드용으로 유효하지 않으면 시스템 글꼴로 대체한다.

`GallaeTypography`는 색·재질 테마와 독립된 Environment 값이다. 메인 창과 설정 창의 루트에 같은 저장 설정을 연결하고, 하위 화면·시트·툴바에 전달한다. `gallaeFont`는 UI 기본 크기에 맞춰 제목·본문·보조 설명의 상대 크기와 굵기를 유지한다. SHA·경로 등 고정폭 메타데이터는 코드 글꼴을 쓰되 크기는 UI 역할을 따른다. macOS 메뉴·시스템 대화상자와 고정 크기 장식 아이콘은 시스템 표현을 유지한다.

코드·diff 본문과 충돌 버전 미리보기는 코드 크기를 그대로 적용한다. 줄 번호 칸은 같은 실제 폰트로 숫자 폭을 측정하여 통합·분할 diff 모두에 적용한다. 고대비 모드는 글자 크기를 변경하지 않는다.
