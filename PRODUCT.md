# Gallae 제품 기준

> 상태: 초안 · 2026-08-27
> 제품명: **Gallae** · 공개 표기: **Gallae for Git**
> 라이선스: [MIT License](LICENSE)

## 한 문장 정의

Gallae는 로컬 저장소의 상태와 변경 이유를 빠르게 읽고, 안전하게 Git 작업을 끝낼 수 있게 해 주는 무료·오픈소스 macOS Git GUI다.

## 제품 방향

- GitFox와 Fork가 보여 주는 높은 정보 밀도, 빠른 반응, 익숙한 Git 작업 흐름을 품질 기준으로 삼는다.
- 결과물은 macOS의 메뉴, 단축키, 포커스, 선택, 분할 보기 관례에 맞춘 독립 설계다.
- 기본 흐름은 마우스만으로 이해할 수 있고, 반복 작업은 키보드만으로 끝낼 수 있어야 한다.
- 상태를 숨기지 않는다. 현재 저장소, 브랜치, 선택 항목, 실행할 Git 동작과 위험도를 화면에서 확인할 수 있어야 한다.
- 긴 작업은 UI를 막지 않고 진행 상태와 취소 가능 여부를 보여 준다.

## 클린룸 원칙

구현의 근거는 공개된 Git 동작과 문서, Apple 공개 API와 Human Interface Guidelines다. 경쟁 앱은 사용자 문제와 기능 범위를 이해하기 위한 참고 자료일 뿐이다.

다음 항목은 가져오거나 재현하지 않는다.

- 경쟁 앱의 코드, 비공개 동작, 에셋, 스크린샷
- 정확한 레이아웃 수치, 아이콘 구성, 문구, 색 조합, 모션
- 제품을 혼동하게 만드는 이름, 시각 자산, 화면 복제

기능은 같은 Git 개념을 다룰 수 있지만, 정보 구조와 표현은 Gallae의 원칙에서 다시 설계한다.

## 핵심 사용자와 작업

주 사용자는 터미널 Git을 이해하지만, 저장소 상태를 더 빨리 읽고 실수를 줄이고 싶은 macOS 개발자다.

가장 자주 수행할 작업은 다음과 같다.

1. 저장소를 열고 현재 브랜치와 작업 트리 상태를 파악한다.
2. 변경 파일과 diff를 검토하고 원하는 범위만 스테이징한다.
3. 커밋을 만들고 원격과 동기화한다.
4. 히스토리와 브랜치 관계를 읽고 필요한 지점으로 이동한다.
5. 충돌이나 잘못된 작업에서 데이터 손실 없이 복구한다.

구체적인 진입 흐름, 정상·예외 상태와 우선순위는 [Gallae 사용자 흐름 문서](docs/README.md)에서 관리한다.

## 저장소 라이브러리

Gallae는 저장소를 하나씩 기억하는 것에 더해, 사용자가 등록한 상위 폴더 아래의 로컬 Git 저장소를 찾아 한곳에서 선택할 수 있게 한다.

- Repository Library에서 폴더를 선택하면, Repository는 바로 열고 일반 폴더는 **Library Folder**로 등록한다.
- 사용자는 하나 이상의 Library Folder를 표준 macOS 폴더 선택기로 직접 등록할 수도 있다.
- Gallae는 사용자가 허용한 폴더 안에서만 하위 폴더를 탐색하고, 발견한 **Repository**를 Library Folder별로 묶어 보여 준다. 디스크 전체를 임의로 검색하지 않는다.
- 직접 연 Repository는 Library Folder 밖에 있어도 최근 항목에 나타난다.
- Repository를 선택하면 요약을 확인할 수 있고, 열면 같은 메인 윈도우가 그 저장소의 **Repository Workspace**로 전환된다.
- 경로를 전달받아 실행된 경우에는 해당 Repository를 바로 열고, 복원할 작업공간이 없으면 Repository Library를 보여 준다.

## UX 원칙

### 정보 구조

- 화면마다 필요한 역할만 둔다. Repository Library는 **Library Folder 탐색 · Repository 목록 · 선택 요약**의 세 역할로 나눈다.
- 첫 Changes는 상단 Repository 문맥 아래에 **변경 목록 · diff**의 2열만 둔다. 역할이 없는 빈 탐색 패널은 만들지 않는다.
- 현재 브랜치와 upstream 대비 ahead/behind 상태는 모든 작업 공간의 상단에서 항상 확인할 수 있어야 한다.
- 선택은 곧 문맥이다. 선택한 저장소, 파일, 커밋이 바뀌면 나머지 영역이 예측 가능하게 갱신되어야 한다.
- 위험한 동작은 일반 탐색과 시각적으로 구분하고, 되돌릴 수 없는 경우에만 확인을 요구한다.

### 시각 언어

- 디자인 다이얼: 밀도 9/10, 변주 3/10, 모션 2/10.
- 시스템 글꼴, 시스템 색상, SF Symbols와 표준 macOS 컨트롤을 우선한다.
- 장식보다 정렬, 간격, 타이포그래피 위계로 밀도를 다룬다.
- 상태 색에는 항상 `수정됨`, `추가됨`, `추적 안 됨`, `충돌` 같은 텍스트나 기호를 함께 둔다.
- 라이트/다크 모드, 충분한 대비, 명확한 키보드 포커스, Reduce Motion을 기본 요구사항으로 둔다.
- 선택 전환은 짧고 미묘하게 처리하며, 작업 결과를 기다리게 하는 장식 애니메이션은 넣지 않는다.

### 조작

- 메뉴와 화면 버튼은 같은 명령 모델을 공유한다.
- 주요 명령은 macOS 메뉴에서 발견할 수 있고 안정적인 단축키를 제공한다.
- 상단의 현재 브랜치 버튼 한 번으로 검색 가능한 브랜치 목록을 열며, Navigator가 있는 화면에서는 전체 목록과 현재 항목도 함께 표시한다.
- 커밋 작성은 문맥을 잃는 모달보다 현재 변경사항과 함께 보이는 인라인 영역을 우선한다.
- 작은 창에서는 보조 영역부터 접고, 선택 항목과 핵심 동작은 남긴다.

## 기능 로드맵

| 단계 | 사용자 결과 | 포함 기능 |
| --- | --- | --- |
| 1. Open & Inspect | Repository를 찾고 작업 트리를 빠르게 이해한다 | Repository 직접 열기, Library Folder 탐색, 마지막 Workspace 복원, 현재 브랜치, staged/unstaged/untracked/conflicted 목록, 텍스트 diff |
| 2. Commit | 검토한 변경만 안전하게 기록한다 | 파일·hunk 스테이징, 커밋, amend, 안전한 discard |
| 3. History | 변경의 맥락과 브랜치 관계를 읽는다 | 커밋 목록/그래프, 커밋 상세와 diff, 검색·필터, 브랜치 이동·생성 |
| 4. Sync | 기존 인증 환경으로 원격과 동기화한다 | fetch, pull, push, 진행·오류 표시 |
| 5. Recovery | 실수와 분기 작업에서 복구한다 | stash, revert, reset, merge, rebase, reflog 기반 복구 보조 |
| 6. Advanced | 복잡한 저장소도 앱 안에서 다룬다 | 충돌 해결, interactive rebase, worktree, submodule, LFS, 서명, 이미지 diff, 서비스 연동 |

각 단계는 독립적으로 쓸 수 있는 상태로 끝낸다. 뒤 단계의 UI나 추상화를 미리 만들지 않는다.

## 첫 수직 슬라이스

### 시나리오

사용자가 Library Folder를 등록하면 Gallae가 그 아래 Repository를 찾아 목록에 보여 준다. Repository를 열면 현재 브랜치와 변경 파일이 나타나고, 파일을 선택하면 텍스트 diff를 읽을 수 있다. 이 단계는 조회 전용이다.

### 완료 조건

- 표준 macOS 폴더 선택기에서 Repository를 직접 열거나 일반 폴더를 Library Folder로 등록한다.
- 등록한 범위 안에서 Repository를 재귀적으로 찾고, Library Folder별 계층과 최근 항목으로 탐색할 수 있다.
- 탐색 중 발견한 Repository를 점진적으로 보여 주며 앱 조작을 막지 않는다.
- 유효하지 않은 경로와 bare 저장소를 구분해 설명한다.
- 현재 브랜치 또는 detached HEAD 상태를 표시한다.
- staged, unstaged, untracked, conflicted 상태를 구분한다.
- 파일 선택과 키보드 이동이 즉시 diff 문맥을 바꾼다.
- 추가/삭제 행, 행 번호, 파일 경로를 색만이 아닌 정보로 식별할 수 있다.
- 큰 diff를 읽는 동안 창 조작과 선택이 멈추지 않는다.
- 앱을 다시 열면 기존 Repository Workspace를 예측 가능하게 복원하고, 복원할 항목이 없으면 Repository Library를 보여 준다.
- Library에서 Repository를 열면 같은 메인 윈도우가 Workspace로 전환된다.

### 이번 슬라이스에서 하지 않는 것

스테이징, 커밋, 원격 통신, 그래프, 충돌 편집, 지속적인 파일 시스템 감시는 넣지 않는다. Library Folder는 추가 시점, 앱 실행 시점, 사용자의 새로고침 요청에 다시 탐색한다. 열린 Repository는 실행·복원·앱 활성화 시점과 사용자의 새로고침 요청에 다시 읽는다. 이후 흐름이 자연스럽게 이어지는지 확인할 수 있도록 시안에는 비활성 또는 예시 영역이 나타날 수 있다.

## 디자인 시안 2

`Repository Library`, `Changes`, `History`는 서로 경쟁하는 시안이 아니라 사용자가 이동하는 제품 상태다. 각 디자인 안은 세 상태를 모두 같은 시각 언어와 탐색 규칙으로 표현한다. 시안은 제품 코드가 아니라 정보 구조를 선택하기 위한 일회용 HTML이다.

### 제품 상태

| 상태 | 진입 시점 | 핵심 목적 | 기본 구성 |
| --- | --- | --- | --- |
| Repository Library | 복원할 저장소가 없거나 사용자가 Library로 이동했을 때 | 등록한 범위에서 저장소를 찾고 연다 | Library Folder 탐색, 저장소 목록, 선택 항목 요약 |
| Changes | Repository를 열었을 때의 기본 상태 | 현재 브랜치와 작업 트리를 파악하고 diff를 읽는다 | 저장소 문맥, 상태별 파일 목록, 선택 파일 diff |
| History | 사용자가 히스토리로 이동했을 때 | 커밋 관계와 선택한 변경의 맥락을 읽는다 | 참조 탐색, 커밋 그래프/목록, 커밋 상세와 변경 파일 |

첫 수직 슬라이스가 실제로 구현하는 상태는 Repository Library와 조회 전용 Changes다. History 시안은 이후 기능이 같은 작업공간 안에 자연스럽게 들어가는지만 검증한다.

### 검토한 디자인 방향

| 안 | 구조 | 확인할 질문 |
| --- | --- | --- |
| A · Balanced | 탐색, 목록, 내용을 분명히 나누는 3열 기본형 | 저장소와 브랜치 문맥을 잃지 않으면서 처음 보는 사람도 빠르게 읽을 수 있는가? |
| B · Compact | 상단 문맥 전환과 2열 콘텐츠를 중심으로 한 압축형 | 작은 창에서도 diff와 그래프에 충분한 면적을 주고 키보드 흐름을 유지하는가? |
| C · Review | 큰 콘텐츠 캔버스와 선택 문맥용 Inspector를 결합한 검토형 | 고밀도 정보를 유지하면서 선택 이유와 다음 행동을 가장 명료하게 보여 주는가? |

제품의 시각 언어는 A를 기준으로 한다. B와 C는 구조를 검토한 기록이며 제품 설정이나 런타임 선택지로 만들지 않는다. 경쟁 제품에서 확인한 명시적인 탐색성과 콘텐츠 중심의 고밀도 표현을 품질 기준으로 삼되, 화면 배치·문구·아이콘·색·수치는 Gallae 기준으로 새로 정한다.

### A 고해상도 패스

A의 재질, 타이포그래피 위계와 조밀한 표현을 유지하되 열 구성은 화면 역할에 맞춘다. Repository Library는 3개 역할을, 첫 Changes는 2개 역할을 사용한다. 패널마다 상자를 두르는 대신 배경 재질과 낮은 대비의 구분선으로 깊이를 만들고, 한 화면의 강조색은 선택과 핵심 동작에만 쓴다. 시스템 글꼴과 일관된 선형 아이콘을 사용하며 코드·해시·브랜치처럼 정렬이 중요한 정보만 고정폭으로 표시한다. 변경 상태는 차분한 의미색과 문자 표기를 함께 사용하고, 장식 모션은 추가하지 않는다.

평가 순서는 `현재 저장소·브랜치 인지 → 상태 파악 속도 → 선택 문맥의 명확성 → diff 가독성 → 키보드 흐름 → 좁은 창 적응 → 시각적 완성도`다. 경쟁 앱과의 외형 유사도는 평가 기준으로 삼지 않는다.

시안 실행:

```sh
python3 -m http.server 8765 --directory prototype/gallae-workspace
```

그다음 `http://localhost:8765/?variant=A&screen=library&appearance=system`을 연다. 화면 안에서 Library·Changes·History를 이동하고, 아래 전환기나 `←` `→` 키로 A·B·C 시안을 비교한다. `variant`는 시안 전용이며 제품 설정으로 만들지 않는다. `appearance`에는 `system`, `light`, `dark`를 사용할 수 있다.

## 구현 기준

- 개발 도구 기준: Xcode 26.6, Swift 6.3.3 컴파일러
- 언어: Swift 6 언어 모드
- 최소 지원 버전: macOS 15.0
- UI: SwiftUI를 기본으로 사용하고, 실제 품질 요구가 확인된 지점에서만 AppKit을 보완적으로 사용한다.
- 테마: 화면은 [Gallae UI 및 테마 시스템](DESIGN_SYSTEM.md)의 Semantic·Component 역할만 사용한다.
- 화면 모드: `system`, `light`, `dark`는 테마와 분리하고, `system`은 macOS 설정을 따른다.
- Git: 사용자의 시스템 Git을 별도 프로세스로 실행하고, 공개된 porcelain 출력을 우선 사용한다.
- 초기 UI 후보: `NavigationSplitView`, `Table`, `HSplitView`, `Commands`와 표준 키보드 단축키.
- 창 구성: 하나의 메인 윈도우에서 Repository Library와 Repository Workspace를 전환한다. 여러 창은 실제 병렬 작업 요구가 확인될 때 검토한다.
- 배포: App Sandbox에서는 시스템 Git의 `xcrun` 진입점이 실행을 거부하므로 첫 버전은 Sandbox를 사용하지 않는다. Hardened Runtime을 유지하고 Developer ID 서명·공증을 거치는 직접 배포를 기준으로 한다.

### 번들 ID 가드레일

- 공개 canonical ID는 `com.mabyko.gallae`다. 조직 팀에서 등록하기 전에는 어떤 빌드·서명 설정에도 넣지 않는다.
- 개인 개발 ID와 개인 서명 팀은 gitignore된 `Config/Local.xcconfig`에만 둔다.
- 저장소에 추적되는 기본 빌드는 조직 namespace가 없는 `forked.gallae.local`을 사용한다.

## 아직 정하지 않은 것

- 조직 Apple Developer Team에서 canonical App ID를 등록할 시점
- 공개 배포에 사용할 Developer ID Application 인증서와 배포 채널

## 공개 근거

- [Apple Human Interface Guidelines: Split views](https://developer.apple.com/design/human-interface-guidelines/split-views)
- [Apple Human Interface Guidelines: Sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars)
- [Apple Human Interface Guidelines: Lists and tables](https://developer.apple.com/design/human-interface-guidelines/lists-and-tables)
- [SwiftUI Table](https://developer.apple.com/documentation/swiftui/table)
- [SwiftUI HSplitView](https://developer.apple.com/documentation/swiftui/hsplitview)
- [SwiftUI EnvironmentValues](https://developer.apple.com/documentation/swiftui/environmentvalues)
- [Git documentation](https://git-scm.com/docs)
- [Fork public product site](https://git-fork.com/)
- [GitFox public support documentation](https://www.gitfox.app/support)
