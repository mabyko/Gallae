# Gallae UI 및 테마 시스템

> 상태: 초안 · 2026-08-27

## 목적

Gallae의 화면 구조와 Git 동작을 건드리지 않고 색, 재질, 간격, 타이포그래피와 컨트롤 표현을 바꿀 수 있게 한다. Theme와 Appearance Mode는 제품 개념이고, Prototype Variant는 디자인 비교용 장치다.

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
| Increased Contrast | 시스템 대비 증가가 켜짐 | 불투명, 구분선·글자 대비 상향 | accent 채움에 흰 글자, 모서리 4pt | 11pt, 추가·삭제 행 왼쪽 컬러 바 |

세 응답은 별개 테마가 아니라 한 테마의 Semantic 매핑 세 벌이다. 사용자는 테마를 고르지 않고, 설정에는 Translucent Sidebar and Toolbar와 Compact Rows만 둔다. 대비 증가는 시스템 설정을 따르며 앱 설정으로 켜지 않는다.

## 현재 시안

시안 2(`prototype/gallae-workspace`)는 정보 구조 후보 A·B·C를 비교한다. 시안 5는 채택한 구조 위에서 세 Material Response와 밀도를 비교하는 로컬 일회용 HTML이며 저장소에 넣지 않는다. 시안 5의 토큰은 `:root[data-theme]`로 응답별 Semantic 값을 덮어쓰고 Light·Dark를 각각 가지며, 설정 창 목업의 두 토글과 시스템 접근성 토글 시뮬레이션으로 응답 전환을 확인한다. 제품에서는 시스템 설정과 두 개의 앱 설정으로만 응답이 결정된다.

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

사용자 제작 Theme, 외부 Theme 파일, Theme 마켓, 런타임 편집기와 플러그인 interface는 만들지 않는다. 테마 선택 UI도 만들지 않는다. 시안 5의 A·B·C는 고를 수 있는 테마가 아니라 한 테마의 접근성 응답이며, 설정에는 Translucent Sidebar and Toolbar와 Compact Rows만 둔다. 실제 요구가 생기기 전까지 하나의 Gallae Theme와 Light·Dark Appearance, 세 응답이면 충분하다.

## 공개 근거

- [SwiftUI EnvironmentValues](https://developer.apple.com/documentation/swiftui/environmentvalues)
- [SwiftUI ColorScheme](https://developer.apple.com/documentation/swiftui/colorscheme)
- [Apple Human Interface Guidelines: Color](https://developer.apple.com/design/human-interface-guidelines/color)
- [Apple Human Interface Guidelines: Materials](https://developer.apple.com/design/human-interface-guidelines/materials)
- [SwiftUI EnvironmentValues: accessibilityReduceTransparency](https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityreducetransparency)
- [SwiftUI ColorSchemeContrast](https://developer.apple.com/documentation/swiftui/colorschemecontrast)
