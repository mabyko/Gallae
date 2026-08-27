# Gallae UI 및 테마 시스템

> 상태: 초안 · 2026-08-27

## 목적

Gallae의 화면 구조와 Git 동작을 건드리지 않고 색, 재질, 간격, 타이포그래피와 컨트롤 표현을 바꿀 수 있게 한다. Theme와 Appearance Mode는 제품 개념이고, Prototype Variant는 디자인 비교용 장치다.

| 개념 | 의미 | 현재 값 |
| --- | --- | --- |
| Theme | 색, 타이포그래피, 밀도와 컴포넌트 스타일을 아우르는 전체 시각 체계 | Gallae |
| Appearance Mode | 같은 Theme 안에서 밝기 팔레트를 선택하는 화면 모드 | System, Light, Dark |
| Prototype Variant | 정보 구조 후보를 비교하는 시안 전용 장치 | A, B, C |

## 테마 seam

실제 앱에서는 하나의 `GallaeTheme` 모듈이 시각 규칙을 모은다. 화면이 알아야 하는 역할은 다음 네 가지뿐이다.

- `colors`: surface, text, selection, action, Git 상태처럼 의미가 있는 색
- `metrics`: 간격, 행 높이, 모서리와 구분선처럼 밀도를 만드는 값
- `typography`: title, body, caption, code 같은 글자 역할
- `motion`: 즉시 반응, 상태 전환과 Reduce Motion 규칙

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

- `GallaeTheme`는 `colors`, `metrics`, `typography`, `motion`을 가진 하나의 값 모듈로 둔다.
- `AppearanceMode`는 `.system`, `.light`, `.dark` 상태로 Theme와 분리한다.
- 앱 루트에서 `.system`을 SwiftUI의 현재 `colorScheme`으로 해석하고 Gallae Theme의 해당 팔레트를 선택한다.
- 해석된 Theme는 SwiftUI Environment에 넣고 하위 화면은 `@Environment`로 읽는다.
- 실제 Theme가 하나뿐이므로 provider protocol, factory, 테마 저장소나 Theme 선택 UI는 만들지 않는다.
- Git과 Repository 모듈은 `Color`, `Font`, `ShapeStyle` 같은 SwiftUI 타입을 알지 않는다.
- 공통 `ButtonStyle`, 선택 행, diff 행 표현은 같은 규칙이 두 번 이상 나타날 때만 테마 모듈 안으로 올린다.
- 열 구성이나 화면 이동처럼 구조적인 UI 변경은 Feature view에서 처리한다. 테마 값으로 레이아웃을 분기하지 않는다.

현재 SwiftUI 문서에서는 `EnvironmentValues`의 사용자 정의 값을 `@Entry`로 선언하고 Scene 또는 View의 `environment` modifier로 하위 뷰에 전달할 수 있다. 구체 코드는 Xcode 프로젝트를 만들며 확정한 SDK와 최소 macOS 버전에 맞춰 작성한다.

## 현재 시안

시안의 CSS도 같은 세 층으로 나뉜다. A·B·C는 하나의 테마 매핑을 공유하고, A의 고해상도 Component 규칙만 별도로 둔다. 기존 구조 CSS에는 Semantic 값을 연결하는 얇은 adapter만 남겨 두었다.

```text
?variant=A&screen=library&appearance=system
?variant=A&screen=changes&appearance=light
?variant=A&screen=history&appearance=dark
```

`system`은 macOS 설정을 따르고, `light`와 `dark`는 같은 Gallae Theme의 Appearance를 독립적으로 검토하기 위한 시안 옵션이다. `variant`는 사용자 설정이 아니다. 제품은 A의 시각 언어 하나만 사용하고, A·B·C 전환 장치는 프로토타입 검토 도구로만 남긴다.

## 변경 방법

| 바꾸려는 것 | 수정할 층 |
| --- | --- |
| 전체 색감과 스타일 | Theme의 Semantic·Component |
| Light·Dark 팔레트 동작 | Theme 내부 Appearance 매핑 |
| 기본 밀도, 글자 단계, 모서리 | Primitive와 Semantic |
| 버튼, 선택 행, diff 한 종류 | Component |
| 패널 배치나 탐색 구조 | Feature view |

## 지금 만들지 않는 것

사용자 제작 Theme, 외부 Theme 파일, Theme 마켓, 런타임 편집기와 플러그인 interface는 만들지 않는다. 실제 요구가 생기기 전까지 하나의 Gallae Theme와 Light·Dark Appearance면 충분하다.

## 공개 근거

- [SwiftUI EnvironmentValues](https://developer.apple.com/documentation/swiftui/environmentvalues)
- [SwiftUI ColorScheme](https://developer.apple.com/documentation/swiftui/colorscheme)
- [Apple Human Interface Guidelines: Color](https://developer.apple.com/design/human-interface-guidelines/color)
