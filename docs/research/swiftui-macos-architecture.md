# SwiftUI macOS 앱의 아키텍처 관행

> 확인일: 2026-09-03
> Context7로 Apple SwiftUI 문서(`/websites/developer_apple_swiftui`)와 SwiftUI Expert Skill(`/avdlee/swiftui-agent-skill`)을 가져오고, WWDC 세션 녹취와 커뮤니티 논쟁 원문을 직접 확인했다.

## 1. Apple의 공식 입장에는 ViewModel이 없다

Apple의 SwiftUI 문서에는 View Model이라는 용어도, 화면당 모델을 두라는 지침도 없다. 대신 "data model"과 Observation 프레임워크로 설명한다.

- 앱은 데이터를 표현하는 custom type, 곧 data model을 만들어 상태를 관리한다. 뷰에서 데이터를 분리하면 모듈성·테스트 가능성·로직 명확성이 올라간다. 뷰는 observable data model에 의존을 형성해 UI가 자동으로 동기화된다. ([Managing model data in your app](https://developer.apple.com/documentation/swiftui/managing-model-data-in-your-app))
- `@Observable` 클래스 인스턴스는 뷰가 `@State`로 소유한다. `@StateObject`는 `ObservableObject`용이고, `@Observable`에는 `State`를 쓴다. ([State](https://developer.apple.com/documentation/swiftui/state%28%29), [StateObject](https://developer.apple.com/documentation/swiftui/stateobject))
- 여러 화면이 공유할 상태는 App 최상위에서 `@State`로 만들고 `.environment(_:)`로 내려보낸다. ([Wishlist 샘플](https://developer.apple.com/documentation/swiftui/wishlist-planning-travel-in-a-swiftui-app))
- `ObservableObject` + `@Published`는 `@Observable`로 옮기는 것이 현재 지침이다. ([Migrating to the Observable macro](https://developer.apple.com/documentation/swiftui/migrating-from-the-observable-object-protocol-to-the-observable-macro))

즉 Apple이 이름 붙여 미는 아키텍처는 없고, **모델 객체 + Observation + 소유권 규칙**이 전부다.

### WWDC에서 말한 규칙

문서보다 WWDC 녹취가 구체적이다. 이것이 Apple이 내놓은 가장 공식적인 지침이다.

**뷰마다 던지라는 세 질문** ([Data Essentials in SwiftUI, WWDC20-10040](https://developer.apple.com/videos/play/wwdc2020/10040/)) — 이 뷰는 무슨 데이터가 필요한가, 그 데이터를 어떻게 조작하는가, 데이터는 어디서 오는가. Curt Clifton은 "결국 source of truth라는 이 질문이 데이터 모델 설계에서 가장 중요한 질문"이라고 말한다.

**observable은 모델 전체가 아니라 의존 표면이다.** Luca Bernardi: "우리는 ObservableObject를 여러분의 data dependency surface로 생각합니다. 이것은 뷰에 데이터를 노출하는 모델의 일부이지, 반드시 모델 전체는 아닙니다."

**중앙 집중과 분산을 둘 다 공식적으로 인정한다.** 같은 세션에서 두 선택지를 나란히 제시한다.

> 전체 데이터 모델을 중앙에 모으고 모든 뷰가 공유하는 ObservableObject 하나를 둘 수 있습니다. 이러면 모든 로직이 한자리에 있어 앱의 가능한 모든 상태와 변경을 파악하기 쉽습니다.

> 또는 데이터 모델에 대한 특정한 투영을 제공하고 필요한 데이터만 노출하도록 설계된 ObservableObject 여러 개로 앱의 일부에 집중할 수도 있습니다. 이쪽은 **데이터 모델이 복잡하고 앱의 일부에 더 좁게 범위를 잡은 무효화를 주고 싶을 때** 더 낫습니다.

**source of truth 수는 줄여라.** Raj Ramamurthy: "복잡도를 낮추기 위해 source of truth의 수를 제한하려고 해야 합니다." 그리고 "여기에 정답은 하나가 아닙니다. 보통의 앱은 여러 도구를 섞어 씁니다."

**`body`는 순수 함수다.** 부수 효과 없이 뷰 서술만 만들어 돌려준다. 모델 객체를 `body` 안에서 만들면 매번 힙 할당이 일어난다.

### `@Observable`이 계산을 바꿨다

위 "좁은 무효화" 논거는 `ObservableObject` 시절 것이다. `@Observable`은 객체 단위가 아니라 **프로퍼티 단위로 추적**한다. ([Discover Observation in SwiftUI, WWDC23-10149](https://developer.apple.com/videos/play/wwdc2023/10149/))

> SwiftUI는 Observable 타입에서 사용된 프로퍼티 접근을 모두 추적합니다. (…) 가령 주문이 추가되어도 그 프로퍼티가 뷰 body 실행 중에 추적된 프로퍼티에 포함되지 않았다면 그 뷰는 무효화되지 않습니다.

이 세션은 모델을 쪼개라는 말을 하지 않는다. 즉 **`@Observable`을 쓰는 앱에서 "큰 모델 하나라서 무관한 변경에 전체가 다시 그려진다"는 논거는 성립하지 않는다.** 커뮤니티 글에 남아 있는 그 조언은 대개 `ObservableObject` 시절에 쓰였거나, 여러 뷰가 같은 컬렉션 프로퍼티 하나를 함께 읽는 좁은 경우(목록 행마다 배열 전체를 읽는 등)에 해당한다.

`@Observable` 클래스는 `@MainActor`로 표시하라는 것이 공통 권고다.

### 큰 앱 조직법에 대한 공식 지침은 없다

2024년 세션도 뷰가 값 타입 서술이라는 원리와 프로퍼티 단위 의존만 다루고, 큰 앱을 어떻게 나눌지나 MVVM·Redux·Clean 같은 패턴은 언급하지 않는다. ([SwiftUI essentials, WWDC24-10150](https://developer.apple.com/videos/play/wwdc2024/10150/)) Apple의 공식 best practice는 **패턴이 아니라 규칙 목록**이라고 보는 것이 정확하다.

## 2. 커뮤니티는 MVVM과 MV로 갈려 있다

**MVVM 쪽.** 상업 블로그와 컨설팅 글에서는 여전히 기본값으로 다룬다. `@Observable`이 `ObservableObject`를 대체했을 뿐 MVVM을 대체하진 않았고, ViewModel을 `@Observable` 클래스로 쓰면 된다는 논지다. 근거는 테스트 가능성, 화면 간 상태 공유, async 작업 조율이다. 다만 비동기 작업이 없는 단순한 뷰는 ViewModel 없이 `@State`만 쓰라고 같이 말한다. ([SwiftLee](https://www.avanderlee.com/swiftui/mvvm-architectural-coding-pattern-to-structure-views/), [Hacking with Swift](https://www.hackingwithswift.com/books/ios-swiftui/introducing-mvvm-into-your-swiftui-project))

**MV 쪽.** SwiftUI에 MVVM을 얹지 말라는 반론이며, 기술적 근거가 구체적이다. ([Apple Developer Forums · Stop using MVVM for SwiftUI](https://developer.apple.com/forums/thread/699003))

- SwiftUI가 이미 ViewController·ViewModel이 하던 일을 대신한다. MVVM은 명령형 UI(2005년 WPF)의 바인딩 계층을 푸는 패턴인데 선언형에는 그 문제가 없다.
- ViewModel 안에서는 `@Environment`를 쓸 수 없어 생성자 주입 우회가 강제된다.
- 화면마다 ViewModel을 두면 의존성이 없는 뷰에도 빈 ViewModel이 생긴다.
- ViewModel 사이 상태 공유가 어려워지고 "누가 상태를 소유하는가"가 흐려진다.
- 결과적으로 massive ViewController가 massive ViewModel로 이름만 바뀐다.

대안으로 제시하는 형태는 화면별 ViewModel 대신 **역할별 모델 객체**(`ProductStore`, `AppState`, `NavigationState` 같은)를 두고 뷰가 property wrapper로 직접 읽는 것이다. React·Vue·Flutter 같은 다른 선언형 프레임워크도 MVVM을 쓰지 않는다는 점을 근거로 든다.

같은 스레드의 반론도 기록해 둔다. MV는 테스트를 어렵게 하고 massive view를 부른다는 지적이 있고, 원저자의 답변은 "UI는 통합·UI 테스트로 덮고 계산과 알고리즘만 단위 테스트하라"였다. 이 답변은 근거보다 의견에 가깝다.

## 3. 그 밖에 언급되는 패턴들

MVVM과 MV 말고도 이름이 붙어 도는 것이 여섯 더 있다. 각각 어떤 문제를 풀려고 나왔는지와 지금 어떻게 평가되는지를 적는다.

| 패턴 | 무엇을 더하나 | 언제 값을 하나 |
| --- | --- | --- |
| MVVM-C (+DI) | ViewModel에 Coordinator(라우팅)와 의존성 주입을 얹는다 | 상업 블로그가 미는 2026년 기본값. 화면이 많고 네비게이션이 복잡한 팀 앱 |
| TCA / Redux | 상태를 reducer 상태 기계로 두고 모든 변경을 Action으로 통과시킨다 | 상태가 정확히 답해져야 하는 제품(거래, 멀티플레이어, 복잡한 undo) |
| MVU / Elm | 단방향 Model → View → Update 순환 | SwiftUI가 이미 같은 골격이라 따로 도입하는 경우는 드물다 |
| MVI | 사용자 의도를 Intent 타입으로 명시해 상태 전이를 추적 가능하게 | 경쟁하는 상태 전이가 많은 화면. 대가는 MVVM보다 많은 boilerplate |
| VIPER | View·Interactor·Presenter·Entity·Router로 역할을 강제 분리 | 30화면·iOS 엔지니어 10명 이상. 그 아래에서는 대략 두 배의 코드값 |
| Clean Architecture (SwiftUI판) | Interactor(업무 로직) + AppState + Repository(protocol) 3계층 | 데이터 소스를 mock으로 갈아 끼우며 높은 단위 테스트 커버리지를 노릴 때 |

기록해 둘 만한 세부는 이렇다.

**TCA.** Point-Free의 라이브러리로 macOS를 포함한 모든 Apple 플랫폼에서 쓸 수 있다. ([swift-composable-architecture](https://github.com/pointfreeco/swift-composable-architecture)) 다만 모든 뷰가 애플리케이션 전체 상태 struct를 받는 설계 때문에 상태 변경이 광범위한 재평가를 부르는 성능 문제가 보고됐고, 이는 SwiftUI가 효율적으로 동작하는 방식과 정면으로 부딪힌다. ([swiftyplace · TCA 성능](https://www.swiftyplace.com/blog/the-composable-architecture-performance)) 여러 팀이 함께 쓰는 대형 앱에서는 캡슐화 부족 문제도 지적된다. 권고는 일관되게 "기본값으로 쓰지 말고 결정론적 상태가 곧 제품일 때만"이다.

**Redux 계열 일반.** SwiftUI에서는 데이터 흐름이 이미 통제되고 추적 가능하므로 상태 변경에 Command 패턴을 덧씌울 필요가 있는지 자체가 의문이라는 평가가 있다. ([Naumov · Clean Architecture for SwiftUI](https://nalexn.github.io/clean-architecture-swiftui/))

**Coordinator.** VIPER·RIBs·MVVM-R의 핵심 부품이었지만, SwiftUI에서는 라우팅이 Binding을 통한 상태 변화로 완전히 통제되므로 Presenter·Builder와 함께 존재 이유를 잃는다는 지적이 있다. 같은 글은 VIPER가 "이제는 없는 문제를 푼다"고 본다. ([Naumov](https://nalexn.github.io/clean-architecture-swiftui/))

**SwiftUI판 Clean Architecture.** 흥미롭게도 이 글은 MVVM의 ViewModel도, Redux도, VIPER도 모두 거부하고 **중앙 집중 `AppState` 하나**를 단일 진실 원천으로 두라고 한다. Gallae의 `AppModel`이 바로 그 형태다. 이 글이 Gallae보다 더 가진 것은 둘이다 — 업무 로직을 `AppState`에서 떼어낸 **Interactor**, 그리고 데이터 접근을 protocol로 감싼 **Repository**. 후자는 mock 기반 단위 테스트(97% 커버리지 주장)를 위한 것이고, `docs/IMPLEMENTATION_PLAN.md:97`이 금지한 "구현체가 하나뿐인 protocol"에 정확히 해당한다. 전자는 protocol 없이도 취할 수 있는 아이디어다.

Clean Architecture를 통째로 권하는 글은 대체로 대규모 팀이나 Kotlin Multiplatform 같은 멀티플랫폼 공유 코드 맥락에서 나온다. 단일 플랫폼 SwiftUI 앱에서는 protocol과 DI container 비용이 얻는 것보다 크다는 쪽이 다수다.

## 4. 양쪽이 공통으로 말하는 확장 기법

패턴 이름과 무관하게 큰 앱에서 반복해 나오는 조언은 둘이다.

- **하나의 큰 observable을 역할별로 쪼개고 environment로 주입한다.** 단 1절에서 본 대로 `@Observable`에서는 성능 논거가 대부분 사라졌다. 이 조언이 남는 경우는 여러 뷰가 같은 프로퍼티 하나를 함께 읽을 때다. 인용된 예도 목록 행마다 `model.isFavorite(landmark)`로 `favorites` 배열 전체를 읽어 모든 행이 같은 의존을 갖는 모양이다. ([SwiftUI Expert Skill · performance-patterns](https://github.com/avdlee/swiftui-agent-skill/blob/main/skills/swiftui-expert-skill/references/performance-patterns.md))
- **큰 뷰를 작은 뷰로 나눠 상태 변화의 영향 범위를 좁힌다.** ([SwiftUI Expert Skill · view-structure](https://github.com/avdlee/swiftui-agent-skill/blob/main/skills/swiftui-expert-skill/references/view-structure.md))

## 5. Gallae에 적용하면

현재 구조를 문서와 대조한 결과다.

| 항목 | Gallae | Apple 문서 |
| --- | --- | --- |
| 모델 | `@Observable @MainActor final class AppModel` | 일치 |
| 소유 | `AppView`의 `@State private var model = AppModel()` | 일치 |
| Git 접근 | 뷰는 `RepositoryInspector`를 직접 호출하지 않음 | 모델/뷰 분리 일치 |
| Scene | `Window(id: "main")` 단일 창 | 공유 모델 하나로 충분 |
| protocol·DI | 없음 (`docs/IMPLEMENTATION_PLAN.md`에 금지로 명시) | 문서에 요구 없음 |

Gallae는 이미 Apple이 문서로 보여 주는 형태 그 자체다. **MVVM이나 Clean Architecture를 새로 얹을 근거는 리서치에서 나오지 않았다.** 단일 창 앱이라 멀티 윈도우 상태 소유권 문제도 없다.

3절의 패턴들도 Gallae에 걸리는 조건이 없다. Coordinator는 단일 창에 `AppScreen` enum으로 이미 상태 기반 라우팅이고, VIPER는 1인 개발이며, TCA는 결정론적 상태가 제품인 경우가 아닌 데다 전체 상태 관찰로 인한 재평가 문제를 새로 들여온다. MVI가 노리는 "경쟁하는 상태 전이 추적"은 Gallae의 부담 지점이 아니다.

실제 문제는 아키텍처 부재가 아니라 크기다. `AppModel`은 `Gallae/AppView.swift:1669-4508`, 2,839줄에 저장 프로퍼티 98개, 함수 104개로 "화면 전환, 선택과 비동기 작업 취소만 맡는다"는 계획 문서의 정의를 이미 넘었다. 이는 4절의 첫 번째 기법, 곧 역할별로 쪼개는 것으로 다룬다. 계층을 늘리는 것이 아니라 같은 계층을 나누는 일이다.

여기에 3절에서 하나만 빌려올 수 있다. SwiftUI판 Clean Architecture가 `AppState`에서 Interactor를 떼어내듯, `AppModel`의 **상태 98개와 동작 104개를 갈라놓는 것**이다. protocol도 DI도 필요 없고, Gallae에는 이미 데이터 접근 계층(`RepositoryInspector`)이 있으므로 Repository에 해당하는 부분은 도입할 것이 없다.

쪼갤 근거는 성능이 아니라 사람이 읽는 비용이라는 점을 분명히 해 둔다. Gallae는 `@Observable`을 쓰므로 프로퍼티 단위 추적이 이미 무효화 범위를 좁혀 준다. 그리고 Apple의 "source of truth 수를 제한하라"는 규칙은 오히려 무분별한 분할을 말린다. 따라서 분할은 Data Essentials가 말한 조건 — **데이터 모델이 복잡할 때** — 에 해당하는 만큼만, 경계가 이미 뚜렷한 곳에서만 한다.
