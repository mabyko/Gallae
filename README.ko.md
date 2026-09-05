# Gallae for Git

[English](README.md) | **한국어**

로컬 저장소의 상태와 변경 이유를 빠르게 읽고, 안전하게 Git 작업을 끝낼 수 있게 해 주는 macOS Git GUI다. 무료이고 오픈소스다.

**macOS의 시스템 Git(`/usr/bin/git`)을 사용한다.** 별도의 Git 구현 없이 기존 로컬 저장소와 Git 설정을 읽는다.

> **상태: 개발 중.** 아직 배포판이 없다. 직접 빌드해 쓸 수 있다.

| 상하 배치 · Top and Bottom (기본) | 좌우 배치 · Side by Side |
| :---: | :---: |
| [![커밋 그래프 아래에 Split diff를 배치한 History](docs/screenshots/history-top-and-bottom.png)](docs/screenshots/history-top-and-bottom.png) | [![커밋 목록 오른쪽에 커밋 상세와 Unified diff를 배치한 History](docs/screenshots/history-side-by-side.png)](docs/screenshots/history-side-by-side.png) |

History 배치와 diff 방식은 각각 선택할 수 있다. 이미지를 누르면 원본 크기로 볼 수 있다.

## 무엇을 할 수 있나

| 작업 | 주요 기능 |
| --- | --- |
| **저장소 탐색** | Library에 폴더 등록, 하위 저장소 탐색, 최근 저장소, 마지막 Workspace 복원 |
| **변경 검토·커밋** | Unified·Split diff, 파일·hunk·줄 단위 Stage/Unstage, Commit·Amend, 확인을 거치는 Discard |
| **History** | 전체 branch·tag 그래프, 메시지·작성자·SHA·ref 검색, 파일별 patch, 작성자·서명 상태, Revert·Reset |
| **Worktree** | 기본·연결된 작업 폴더 목록, 새 branch 또는 기존 branch로 Worktree 생성, 폴더 전환·제거 |
| **동기화** | Fetch·Fetch & Prune·자동 Fetch, fast-forward Pull, Push·Publish, Remote 관리 |
| **병합·복구** | Merge·Rebase, 충돌 버전 비교·외부 Merge Tool, Continue·Abort, Interactive Rebase, Stash·Reflog |
| **외부 앱** | 작업 폴더를 Finder·터미널·에디터에서 열기, 경로 복사, `gallae [path]` 명령 설치 |

History는 기본으로 커밋 목록을 위에, 변경 검토를 아래에 배치한다. **Expand Review**로 검토 영역을 넓히거나, Appearance에서 **Side by Side**로 바꿀 수 있다. branch를 한 번 선택하면 전체 그래프에서 해당 커밋으로 이동하고, 두 번 클릭하면 branch를 전환하거나 연결된 Worktree를 연다.

Branches·Remotes·Tags의 **⋯** 메뉴는 목록이 비어 있어도 사용할 수 있다. **Add Remote…**는 Fetch·Publish 없이 원격 주소만 등록하고, **New Tag…**는 지정한 커밋(기본 `HEAD`)에 로컬 lightweight tag를 만든다. branch 전환이나 자동 push는 하지 않는다. **Worktrees** 제목 옆의 화살표는 항상 표시되며 목록을 접거나 펼칠 수 있다.

Appearance에서 시스템·라이트·다크 테마, 행 밀도, 앱 강조색과 History 그래프·배지 색을 고를 수 있다. 앱 강조색의 기본값은 macOS 설정을 따르는 **System**이다.

## 외부 앱 연동

branch의 우클릭 메뉴 또는 상단 작업 위치 메뉴에서 **Open in**을 선택한다. 현재 branch는 현재 작업 폴더를, 다른 Worktree에서 체크아웃한 branch는 해당 폴더를 연다. 폴더가 없는 branch에서는 비활성화하며, 외부 앱을 여는 것으로 checkout이 바뀌지는 않는다.

**Settings → General**에서 기본 터미널과 에디터를 각각 선택한다. 아래는 앱에 내장된 선택지이며, 터미널·에디터 목록에는 설치된 앱이 표시된다.

| 용도 | 기본 지원 앱 | 동작 |
| --- | --- | --- |
| Finder | macOS Finder | 작업 폴더 위치 표시 |
| 터미널 | Terminal, Ghostty, Warp, iTerm2, cmux, Kaku, WezTerm, kitty, Alacritty, Rio | 선택한 작업 폴더로 터미널 열기 |
| 에디터 | VS Code, Zed | 선택한 작업 폴더 열기 |
| 사용자 지정 | 터미널·에디터의 **Other…** | 폴더 열기를 지원하는 다른 macOS 앱 지정 |

앱은 별도로 설치해야 한다. 사용자 지정 앱의 폴더 처리 방식은 해당 앱에 따라 다르다.

### 충돌 해결과 Merge Tool

일반 Merge에서 충돌이 나면 병합 상태를 유지하고 **Changes → Conflicts**로 이동한다. **Base·Ours·Theirs**를 비교하거나 **Open in Merge Tool**로 외부 도구를 열 수 있다. 사용할 도구는 **Settings → General → Merge Tool**에서 고른다.

| 선택지 | 지원 방식 | 편집 후 처리 |
| --- | --- | --- |
| **Use Git Configuration** | Git의 `merge.guitool`, 없으면 `merge.tool` 사용 | Git 설정에 따라 해결 파일이 스테이징될 수 있으며 Gallae가 상태를 다시 읽는다. 터미널 입력이 필요한 도구는 터미널에서 실행해야 한다. |
| **VS Code** | Base·Ours·Theirs·결과 파일을 전달해 3-way Merge Editor 열기 | 편집 화면을 닫고 Gallae에서 결과를 검토한 뒤 **Mark Resolved…** |
| **Sublime Merge** | 전용 Merge Tool에 세 버전과 결과 파일 전달 | 편집 화면을 닫고 Gallae에서 결과를 검토한 뒤 **Mark Resolved…** |

VS Code·Sublime Merge는 설치된 앱에 포함된 실행 도구를 사용한다. **Zed는 Open in 에디터로 제공하며, Merge Tool 선택지에는 포함하지 않는다.**

외부 병합 연동은 양쪽에 있는 일반 파일을 대상으로 한다. VS Code·Sublime Merge 직접 연동은 UTF-8 텍스트를 지원한다. 삭제 충돌·심볼릭 링크·서브모듈 등은 **Use Ours / Use Theirs** 또는 터미널로 해결한다. **Mark Resolved는 충돌 표시가 남았는지 검사하지 않으므로 저장한 내용을 먼저 확인해야 한다.** 모든 충돌을 해결하면 **Continue**, 병합을 중단하려면 **Abort…**를 사용한다.

Pull은 **fast-forward만 허용**한다. 이력이 갈라져 있으면 자동 병합하지 않고 멈춘다.

## 다른 점

**변경 검토와 부분 Stage에 필요한 patch 형식을 고정한다.** 외부 diff 도구·색·접두사·문맥 설정이 앱의 patch 해석에 영향을 주지 않도록 처리하고, 파일 내용에 영향을 주는 `core.autocrlf`와 `.gitattributes`는 존중한다. → [무엇을 고정하고 무엇을 존중하는가](docs/git-configuration.md)

**설정 때문에 Git이 아예 실행되지 않으면 그 이유를 보여 준다.** 어느 설정의 어느 값이 문제인지 화면에서 읽고 고칠 수 있다.

## 빌드

```sh
git clone <this repository>
cd Gallae
open Gallae.xcodeproj
```

서명이 필요하면 `Config/Local.xcconfig`를 만든다. 추적되지 않는 파일이라 개인 식별자가 저장소에 들어가지 않는다.

```
GALLAE_BUNDLE_ID = <your-bundle-id>
GALLAE_BUNDLE_ID[config=Debug] = <your-debug-bundle-id>
DEVELOPMENT_TEAM = <your-team-id>
```

명령줄에서:

```sh
xcodebuild test -project Gallae.xcodeproj -scheme Gallae -destination 'platform=macOS'
```

**요구 사항** — macOS 15 이상, Xcode, 시스템 Git(Xcode Command Line Tools).

## 문서

| | |
| --- | --- |
| [PRODUCT.md](PRODUCT.md) | 현재 제품 범위, UX·개발 기준, 클린룸 원칙 |
| [CONTEXT.md](CONTEXT.md) | 도메인 용어 |
| [DESIGN_SYSTEM.md](DESIGN_SYSTEM.md) | 재질·대비·밀도 응답 |
| [docs/git-configuration.md](docs/git-configuration.md) | Gallae가 Git 설정을 다루는 방식 |
| [docs/README.md](docs/README.md) | 유즈케이스 색인 |

## 기여

구현의 근거는 공개된 Git 동작과 문서, Apple 공개 API와 Human Interface Guidelines다. 경쟁 앱의 코드·에셋·문구·수치는 가져오지 않는다. 자세한 기준은 [PRODUCT.md의 클린룸 원칙](PRODUCT.md#클린룸-원칙)에 있다.

분기나 반복이 있는 로직은 임시 저장소를 쓰는 작은 통합 테스트를 남긴다.

## 라이선스

[MIT License](LICENSE)
