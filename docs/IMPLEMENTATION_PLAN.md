# Gallae 구현 계획

> 상태: 1 · Open & Inspect 완료 · 2 · Commit 완료 · 3 · History 완료 · 4 · Sync 완료 · 5 · Recovery 완료 · 6 · Advanced 완료 · 7 · Workspace 구조 진행 중 · 2026-09-03
> 현재 범위: 파일 목록 상태 배지를 한 글자로 축약 완료. diff 머리의 파일 식별·줄 수 요약·반응형 조작과 깨끗한 Changes 안내 개선 완료. 앞선 선택 보존·책임별 파일 분리는 완료. sem 요약은 뺐다(7D-3·7D-4).

## 시안 8 후속 개선

- 같은 Repository의 새로고침은 History·Stashes의 revision·파일 선택과 로드된 내용을 유지한다. 다른 revision 선택은 파일 상태를 초기화하며, 사라진 선택은 유효한 첫 항목으로 대체한다.
- `RepositoryDiffPresentation`이 현재 구획과 저장된 취향에서 실제 레이아웃을 결정한다. Changes·History·Stashes의 선택기와 본문이 이를 함께 사용한다.
- 저장된 변경 칸이 560pt보다 좁으면 파일 목록 대신 경로 선택 메뉴를 제공한다. 넓어지면 목록이 돌아오며 선택을 유지한다.
- 긴 커밋 본문은 펼쳐서 스크롤할 수 있고, 커밋 전환 시 접힌다. 분할선은 포커스·좌우 화살표·접근성 증감 동작을 제공한다.
- 기존 실제 Git 테스트에 새로고침 선택 보존·revision 전환·사라진 선택과 diff 레이아웃 판단 회귀 검증을 추가한다.

## diff 검토 화면 다듬기

- 파일 상태 배지는 고정 너비 한 글자로 표시하고 전체 이름·Staged/Working 범위는 툴팁과 접근성 이름에 유지한다.

- Changes와 저장된 diff가 `RepositoryDiffHeader`를 공유한다. 파일명·폴더·현재 구획의 추가/삭제 줄 수를 구분하고 좁은 칸에서는 조작을 아래 줄로 내린다.
- 파일 전체 Stage/Unstage의 범위를 이름으로 밝히고, Discard는 파일 메뉴로 옮기되 기존 확인과 안전 검사를 유지한다.
- 루트 파일의 이름 반복을 없애고 전체 상대 경로는 도움말과 복사 메뉴에 남긴다. 깨끗한 Changes에서는 Show History로 다음 탐색을 안내한다.
- 추가/삭제 집계는 기존 changedLineCount와 같은 계산을 공유하며 문맥·메타데이터를 제외하는 회귀 테스트로 검증한다.

## 사용자 결과

Open & Inspect는 사용자가 Repository를 찾고, 열고, 현재 브랜치와 작업 트리 변경을 읽는 데까지 제공한다. 구현은 작게 검증하기 위해 두 단계로 나눈다.

- **1A · 열기와 검사**: Repository 직접 열기 → HEAD와 상태 표시 → 파일 선택 → 텍스트 diff
- **1B · Library와 복원**: Library Folder 등록 → 점진적 탐색 → Repository 열기 → 재실행 복원

1A와 1B는 같은 Repository Workspace를 사용한다. 첫 공개 버전에는 둘 다 포함하지만 반드시 1A를 먼저 동작하게 만든다.

그 위에서 Commit, History와 Sync 단계를 완성했고, 같은 Workspace 안에서 Recovery를 작은 수직 슬라이스로 잇는다.

## 앱 진입 흐름

```text
앱 실행
├─ Repository 경로와 함께 실행
│  ├─ 유효함 → Repository Workspace / Changes(작업 트리가 깨끗하면 History)
│  └─ 열 수 없음 → 원인과 복구 경로
├─ 복원 가능한 Active Repository 있음 → Workspace 복원 후 새로고침
└─ 복원할 항목 없음 → Repository Library
   └─ 폴더 선택
      ├─ Repository → 직접 열기
      └─ 일반 폴더 → Library Folder 등록 → 점진적 탐색 → Repository 선택 → 열기
```

Library에서 선택은 요약만 바꾸고, 명시적인 Open 명령이 Workspace를 연다.

## 반드시 표현할 상태

| 상태 | 보여 줄 정보 | 다음 행동 |
| --- | --- | --- |
| Library가 비어 있음 | 등록된 위치와 최근 Repository가 없음 | 폴더를 선택해 Repository 열기 또는 Library Folder 등록 |
| 탐색 중 | 탐색 범위, 진행 여부, 발견 수 | 발견한 Repository 열기 또는 탐색 취소 |
| 탐색 결과 없음 | 탐색은 끝났지만 Repository가 없음 | 다른 폴더 선택 또는 재탐색 |
| 위치 접근 불가 | 읽을 수 없는 위치와 원인 | 위치 다시 선택 또는 Library에서 제거 |
| Git 사용 불가 | Git 또는 Command Line Tools 문제 | 설치·복구 후 다시 시도 |
| Git Repository가 아님 | 선택한 경로와 판정 | 다른 폴더 선택 |
| bare Repository | 지원하지 않는 Repository 유형 | 다른 Repository 선택 |
| Clean | 변경 파일이 없음 | History를 먼저 표시하고, Changes에서는 Finder 열기 제공 |
| detached HEAD | 브랜치 대신 현재 commit | 이후 브랜치 선택 |
| unborn branch | 브랜치 이름과 아직 commit이 없다는 상태 | 현재 상태 계속 검사 |
| History가 비어 있음 | 아직 commit이 없음 | Changes로 돌아가 첫 commit 작성 |
| History 읽기 실패 | 선택한 Repository와 Git 오류 | 같은 화면에서 다시 시도 |
| Stash가 비어 있음 | 저장된 Stash가 없음 | Changes나 History로 돌아가기 |
| Stash 읽기 실패 | 선택한 Repository와 Git 오류 | 같은 화면에서 다시 시도 |
| Reflog가 비어 있음 | 아직 기록된 HEAD 이동이 없음 | Changes나 History로 돌아가기 |
| Reflog 읽기 실패 | 선택한 Repository와 Git 오류 | 같은 화면에서 다시 시도 |
| upstream 없음 | 로컬 브랜치와 upstream 미설정 상태 | Publish로 remote branch와 upstream 생성 |
| remote 없음 | Fetch·Publish할 remote가 설정되지 않음 | Publish에서 Remote 추가 또는 Fetch 전 Remote 설정 |
| 충돌 있음 | 충돌 파일의 Base·Ours·Theirs 내용 | 한쪽 전체 버전으로 해결 또는 직접 편집 |
| Merge·Rebase 진행 중 | 작업 종류, 남은 충돌 수와 Continue 가능 여부 | 충돌 해결 뒤 Continue 또는 Abort |
| diff를 바로 표시할 수 없음 | 파일 유형, 크기 또는 실패 원인 | 외부에서 열기 또는 명시적으로 추가 로드 |
| 새로고침 실패 | 마지막 성공 상태와 현재 오류를 구분 | 다시 시도 또는 Repository 다시 열기 |
| Repository 이동·삭제 | 이전 경로와 실패 원인 | 다시 찾기, Library로 이동 또는 최근 항목 제거 |

빈 상태는 오류와 구분한다. 마지막 성공 상태를 남길 때는 최신 정보가 아님을 표시하고, 모든 실패에는 같은 화면에서 실행할 수 있는 다음 행동을 둔다.

## 기술 기준

- macOS 15.0 이상
- Swift 6 언어 모드, SwiftUI 우선
- macOS App 타깃 하나와 테스트 타깃 하나
- 시스템 Git을 `Foundation.Process`로 실행
- 외부 패키지, libgit2, 데이터베이스 없음
- 하나의 메인 윈도우에서 Repository Library와 Workspace 전환
- Open & Inspect와 History·Stash·Reflog의 검사 경로는 조회 전용이다. 충돌 해결과 Continue·Abort, Revert, Reset, Merge, Rebase, Stash 생성·적용·삭제, Commit, local branch 생성·전환, Remote 설정 변경, Pull과 Push는 사용자가 명시적으로 실행한다. Fetch는 직접 실행하거나 사용자가 먼저 자동 실행을 켠 경우에만 수행한다.
- 오픈소스 라이선스는 [MIT License](../LICENSE)

## 코드 경계

```text
GallaeApp
└─ AppModel @MainActor
   ├─ Repository Library
   │  ├─ RepositoryScanner
   │  └─ LibraryStore
   ├─ Changes
   │  └─ RepositoryInspector
   ├─ History
   │  └─ RepositoryInspector
   ├─ Stashes
   │  └─ RepositoryInspector
   ├─ Reflog
   │  └─ RepositoryInspector
   └─ GallaeTheme
```

- `AppView.swift`는 앱 루트와 시트 진입을, `AppModel.swift`는 화면 전환·선택·Git 작업 조정과 비동기 결과의 유효성 검사를 맡는다. 같은 저장소 갱신과 다른 저장소 진입을 구분하며 Git 명령 자체는 Inspector에 둔다.
- `RepositoryWorkspaceView.swift`는 Navigator와 Changes·History·Stashes·Reflog 화면 구성을 맡는다. 공용 파일 목록·diff 선택기·행 렌더링은 `RepositoryDiffView.swift`에 둔다.
- `WorkspaceLayout.swift`는 패널 폭 계산·분할선 조작·AppKit 사이드바 보정·스크롤바 정렬을 모은다. 기존 macOS 보정의 근거와 폭 계산 테스트는 유지한다.
- `RepositoryInspector`는 Git 실행과 출력을 숨기고 불변 snapshot과 진행 중인 Merge·Rebase 상태·Continue·Abort, Interactive Rebase 계획·실행, file diff, commit history/patch와 Revert, Stash 목록·파일·patch·생성·적용·삭제, HEAD Reflog, local branch 목록·생성·전환·Merge·Rebase, configured Remote와 Fetch/Pull/Push 결과를 돌려준다.
- `RepositoryScanner`는 허용된 Library Folder 안에서만 후보를 찾고 결과를 점진적으로 전달한다.
- `LibraryStore`는 URL bookmark, 최근 Repository, 마지막 Workspace와 자동 Fetch 선택을 저장한다.
- 구현체가 하나뿐인 protocol, DI container, coordinator, database layer는 만들지 않는다.
- 아키텍처 패턴은 얹지 않는다. Apple 문서와 WWDC가 주는 것은 패턴이 아니라 규칙이고 현재 구조가 이미 그 규칙을 지킨다. 근거는 `docs/research/swiftui-macos-architecture.md`.

### 툴바의 알려진 제약

2026-09-03에 접근성 좌표로 확인한 두 가지다.

- **툴바는 넘치지 않는다.** 최소 폭 720pt 창에서 Repository 이름을 68자까지 늘려도 툴바 항목 좌표가 바뀌지 않고 `>>` 오버플로도 나타나지 않는다. 제목은 Navigator 묶음과 Fetch 사이 169pt 칸에서 잘릴 뿐이다. 좁은 창의 툴바 오버플로 대응은 필요 없다.
- **한 ToolbarItem 안의 그룹 이름은 고칠 수 없다.** 촘촘한 구분선을 얻으려고 여러 컨트롤을 `HStack`으로 한 `ToolbarItem`에 담았는데, 그 안의 `ControlGroup`들이 접근성 트리에서 첫 컨트롤의 이름을 함께 쓴다(Publish·Refresh가 "Pull", Library가 "Navigator"). `ControlGroup(label:)`과 `.accessibilityLabel` 둘 다 이 이름을 바꾸지 못했다. AppKit이 NSToolbarItem에 붙인 이름이라 SwiftUI에 손잡이가 없다. 컨트롤마다 별도 `ToolbarItem`으로 쪼개면 고쳐지지만 구분선 배치가 깨진다. 버튼 자체의 이름은 모두 정확하므로 그대로 둔다.

### 7D-1 · Git diff 형식 고정 — 완료

- patch를 만드는 네 곳(commit `show`, stash `diff`, untracked `--no-index`, working tree `diff`)이 같은 고정 옵션을 쓴다. `--no-color`, `--src-prefix=a/ --dst-prefix=b/`, `--diff-algorithm=histogram`, `--unified=3`과 `-c core.quotepath=false -c diff.suppressBlankEmpty=false`다. 사용자의 diff 설정은 더 이상 patch 텍스트에 닿지 않는다.
- `--default-prefix` 대신 `--src-prefix`/`--dst-prefix`를 쓴다. 같은 설정 넷을 덮으면서 Git 2.45보다 오래된 버전에서도 동작한다.
- `core.autocrlf`·`core.eol`과 `.gitattributes`는 파일의 내용을 정의하므로 그대로 존중한다.
- 잘못된 설정 값은 git이 설정 파일을 읽는 단계에서 죽어 재정의로 구제되지 않는다. 대신 `RepositoryInspectionError`가 이미 들고 있던 git stderr의 첫 줄을 문구에 실어 원인을 말한다.
- 테스트 하나를 더했다. 깨뜨리는 설정 일곱을 하나씩 건 임시 저장소에서 hunk가 파싱되고, 빈 줄 뒤 줄 번호가 맞고, escape가 섞이지 않고, 한글 경로가 읽히고, patch가 index에 적용되는 것을 확인한다.

### 7D-2 · 패치 헤더 숨김 — 완료

- `diff --git`·`index`·`---`·`+++` 네 줄을 diff 화면에서 뺀다. 파일 이름과 상태는 diff를 둘러싼 화면이 이미 보여 주므로 이 줄들은 정보를 더하지 않는다.
- 모델에서 지우지는 않는다. `RepositoryDiff.Section.hunks`가 이 줄들을 패치 헤더로 그대로 써서 `git apply`에 넘기기 때문이다. `Line.isPatchHeader`로 표시할 때만 거른다.
- 새 파일과 삭제 파일의 mode는 화면에서 숨기되 패치에는 남긴다. chmod의 old mode/new mode와 rename의 옛 경로·새 경로는 표시한다. hunk 안의 `-`로 시작하는 내용 줄은 `.deletion`이라 헤더로 오인되지 않는다.

### 7D-3 · 7D-4 · sem entity 요약 — 넣었다가 뺌

`sem`이 있으면 diff 위에 그 patch가 건드린 함수·타입·속성을 한 줄로 붙이고, 설정의 Git 탭에서 켜고 끌 수 있게 했다(`2584404`, `0c97fbc`). 동작은 확인했다 — 켜고 끄면 앱 재시작 없이 줄이 붙고 떨어진다.

**뺀 이유**는 자리가 맞지 않아서다. 그 파일 diff를 이미 보고 있는데 그 파일의 목차를 한 줄로 되풀이하고, entity가 서넛만 넘어도 한 줄에 안 들어가 잘린다. `sem`이 잘하는 것은 여러 파일을 묶어 보여 주는 커밋 단위 목차인데, 그 자리(History의 커밋 diff)에는 애초에 붙이지 않았다. 대가로 파일을 고를 때마다 외부 프로세스를 하나 띄웠다 — 앱에서 Git이 아닌 도구를 부르는 유일한 곳이었다.

되살릴 자리는 History의 커밋 diff다. 그때 참고할 것:

- `sem diff --patch`는 unified diff를 stdin으로 받는다. 7D-1에서 고정한 patch를 그대로 넘기면 되고, diff 표시와 줄 단위 staging은 영향받지 않는다. difftastic은 출력이 patch가 아니라 staging을 못 쓰게 만들어 제외했다.
- `sem`은 patch의 경로를 자기 작업 디렉터리 기준으로 푼다. Repository 루트에서 실행하지 않으면 entity가 `orphan module-level`로 떨어진다.
- Finder로 실행한 앱은 PATH가 빈약하다. PATH 외에 `/opt/homebrew/bin`, `/usr/local/bin`, `~/.local/bin`도 찾아야 한다.
- 파싱하지 못한 파일에는 `chunk lines 1-1` 같은 줄 범위 entity가 온다. 옆 diff가 이미 보여 주는 정보라 걸러야 한다. `.txt`·`.md`·`.svg`는 걸러 내면 남는 게 없어 켜나 끄나 같아 보인다.

### 7E-1 · diff 칸 공통 개선 — 완료

시안 8(C2)의 공통 항목을 먼저 넣는다. 세그먼트 구조와 독립이다.

- **섹션이 하나뿐이면 구획 머리를 두지 않는다.** 파일 이름과 상태는 diff 위에 이미 있고, 대부분의 파일이 한쪽만 가진다.
- **hunk 머리가 위치를 말한다.** `Line 1`·`Lines 12–18`, 지우기만 하는 hunk는 `After line 4`. raw `@@ …`는 흐리게 옆에 남겨 Git을 아는 사람이 계속 읽을 수 있다.
- **`+`·`-` 접두사를 화면에서 뺀다.** 색과 칸과 변경 막대가 이미 말하는 것이고, 빼면 문맥 줄과 코드가 같은 열에서 시작한다. `Line.text`는 그대로 둔다. `Section.hunks`가 그것을 `git apply`에 넘기기 때문이다. 표시는 `displayText`가 맡는다.
- **새 파일과 삭제된 파일은 Split에서도 한 칸으로 그린다.** 비교할 반대편이 없어 절반이 비던 것을 없앤다(`Section.isOneSided`).
- 접근성 라벨도 접두사 대신 종류와 위치를 말한다. VoiceOver가 "Added"라고 이미 말하므로 `+`는 되풀이였다.

### 7E-3 · 새 파일의 부분 unstage — 완료

Staged 섹션에만 hunk 동작이 없어 Working Tree 와 비대칭이던 것을 없앤다. 7C-3 에서 untracked 파일의 부분 stage 를 열었으니 그 반대 방향이다.

- 새 파일의 patch 를 일부만 되돌리려면 헤더를 고쳐야 한다. `new file mode` 와 `--- /dev/null` 을 그대로 두면 Git 이 `new file … depends on old contents` 로 거절한다. 본문에 문맥 줄이 있는데 헤더는 옛 쪽이 비었다고 말하기 때문이다. `partialMetadata` 가 그 두 줄을 지우고 사라진 쪽 경로를 살아남은 쪽에서 빌려 온다. 삭제된 파일은 같은 일을 반대로 한다.
- 모든 줄을 고르면 문맥 줄이 없어 patch 가 정말로 파일을 만드는 것이 맞으므로 헤더를 그대로 둔다.
- `canUnstageSelectedHunks` 와 `updateIndexSynchronously` 의 관문이 `staged == .modified` 만 통과시키던 것을 `.added` 도 받도록 넓혔다.
- 테스트 둘. 세 줄짜리 새 파일에서 한 줄만 되돌리면 index 에 두 줄이 남고 디스크 파일은 그대로인 것, 그리고 `partialMetadata` 가 전부 고른 patch 는 건드리지 않고 일부만 고른 patch 의 헤더만 고치는 것.

### 7E-2 · C2 세그먼트 — 완료

시안 8의 본체다. 두 섹션을 세로로 쌓던 것을 한 번에 하나씩 보여 주는 구조로 바꾼다.

- diff 칸 머리에 `Staged 1 | Working Tree 1` 세그먼트를 둔다. 개수는 바뀐 줄 수(`Section.changedLineCount`)이고 문맥과 헤더는 세지 않는다. 옆 문구가 지금 보는 쪽이 커밋에 들어가는지 아닌지를 말한다.
- 그 아래 **반대편 한 줄**을 둔다. 색 막대와 함께 `Staged · 1 line · in the next commit`처럼 말하고 눌러 넘어갈 수 있다. 화면 밖으로 나간 목적지를 화면 안에 두는 장치이며, stage 한 줄이 "사라졌다"가 아니라 "저기로 갔다"로 읽히게 한다.
- 기본은 Working Tree다. 다음 동작이 일어나는 곳이기 때문이다.
- **자동으로 넘어가지 않는다.** 보고 있던 쪽이 비면 그 쪽에 남아 무슨 일이 일어났는지 말한다. 사용자가 누르지 않은 전환은 놀라움이 된다.
- 선택은 파일 하나에 대한 읽기 선택이지 모드가 아니므로 다른 파일을 고르면 초기화된다.
- 섹션이 하나뿐이면 세그먼트도 반대편 줄도 없다. 대부분의 파일이 그렇다.

## 단계별 완료 조건

### 0 · 프로젝트와 Git 실행 — 완료

- macOS 15 대상 Xcode 프로젝트가 빌드되고 테스트 명령이 동작한다.
- 추적 설정은 `forked.gallae.local`을 사용하며 개인 ID와 서명 팀은 로컬 xcconfig에만 존재한다.
- Debug는 `Gallae for Git Dev`와 전용 아이콘을 사용해 Release 빌드와 함께 설치해도 구분된다.
- 표준 폴더 선택기로 받은 URL을 bookmark로 저장하고 재실행 뒤 복원한다.
- 복원한 범위 안에서 시스템 Git을 실행할 수 있음을 확인한다.
- `/usr/bin/git`의 `xcrun` 진입점은 App Sandbox 안에서 실행을 거부한다. 첫 버전은 Sandbox를 끄고 Hardened Runtime과 직접 배포를 사용한다.

### 1A-1 · Repository 검사 — 완료

- Repository와 일반 폴더, bare Repository를 구분한다.
- branch, detached HEAD, unborn branch와 locally known upstream 상태를 표현한다.
- staged, unstaged, untracked, conflicted와 rename/delete를 구분한다.
- 공백, 한글과 특수문자가 있는 경로를 안전하게 읽는다.
- Git 또는 Command Line Tools를 사용할 수 없는 상태를 설명한다.
- 검사로 working tree, index와 refs의 의미 있는 상태를 바꾸지 않는다.

### 1A-2 · Changes — 완료

- 유효한 Repository를 연 뒤에만 현재 Workspace를 교체한다.
- 상단에서 Repository, 경로, branch와 추적 대상 remote branch를 확인할 수 있다. 사용자 화면에서는 Git의 upstream 관계를 `Tracking`으로 표시한다.
- 파일 목록과 선택한 텍스트 diff를 2열로 표시한다.
- 변경 파일은 기본 `Status`에서 Conflicts·Changes·Untracked Files 그룹으로 보고 각 그룹을 접고 펼칠 수 있으며, `Folders`에서 Repository 상대 경로 계층으로 전환할 수 있다. 그룹은 처음에 펼쳐지고 파일 상태는 의미색과 텍스트 배지를 함께 사용한다.
- 같은 경로에 staged와 unstaged 변경이 함께 있으면 범위를 나눠 표시한다.
- binary, 지원하지 않는 인코딩과 과대한 diff를 빈 상태와 구분한다.
- 텍스트 diff는 처음 2MB까지 읽고, 사용자가 요청하면 16MB까지 확장한다. 그보다 크거나 표시할 수 없는 파일은 외부에서 열 수 있다.
- 실행·복원·앱 활성화와 Refresh 명령에서 새로 읽는다.
- 취소된 작업과 늦게 끝난 이전 결과가 최신 화면을 덮어쓰지 않는다.

### 1B-1 · Repository Library — 완료

- Library의 Choose Folder는 선택한 경로가 Repository면 직접 열고, 일반 폴더면 Library Folder로 등록해 탐색한다.
- 사용자가 허용한 Library Folder 밖은 탐색하지 않는다.
- symlink를 따라가지 않고 package·숨김 디렉터리와 `.git` 내부를 건너뛴다.
- 유효한 Repository를 찾으면 그 하위 탐색을 멈춘다.
- 발견 결과를 즉시 보여 주고 탐색을 취소할 수 있다.
- 일부 경로의 실패가 전체 결과를 지우지 않는다.
- Scan Again은 기존 결과와 선택을 유지하고, 완료되면 사라진 Repository를 목록에서 정리한다.
- 선택은 요약만 바꾸며 Return, 이중 클릭 또는 Open 명령이 같은 윈도우를 Workspace로 전환한다. Workspace의 Library 명령은 같은 창을 Repository Library로 되돌린다.
- 같은 앱 실행 안에서 Workspace와 Library를 오가면 선택과 Library Folder 계층의 펼침 상태를 유지하고, 선택 강조가 다시 보이는 Repository 목록으로 키보드 포커스를 되돌린다.
- Library Folder 결과는 실제 상대 경로 계층으로 보여 주며, 폴더 행은 disclosure 또는 이중 클릭으로 접고 펼친다. 중간 폴더와 Repository는 서로 다른 아이콘으로 구분하고, 중간 폴더를 선택하면 경로와 하위 Repository 수만 요약한다. Recent는 최근 순서의 평면 목록을 유지한다. Recent 항목은 macOS 표준 다중 선택(⌘A·⌘클릭·Shift 클릭)으로 함께 골라, 디스크의 Repository를 바꾸지 않고 목록에서 제거할 수 있다. Repository 행은 이름부터 보여 주고 Recent에서는 경로도 함께 보여 준다. 브랜치와 변경 상태는 보이는 행부터 읽고, commit 수와 최근 활동은 선택한 Repository에서만 계산한다.

### 1B-2 · 복원 — 완료

- Library Folder, 최근 Repository와 마지막으로 성공한 Workspace 하나를 저장한다.
- 복원한 Workspace의 Git 데이터는 새로 읽는다.
- 삭제·이동·읽기 실패로 복원에 실패하면 Library에서 다시 연결하거나 제거할 수 있다.
- 실패한 위치를 사용자의 조치 없이 매 실행마다 반복해서 열지 않는다.
- Library Folder는 실행 시 다시 탐색하며, 일부 저장 위치가 실패해도 다른 Folder와 최근 Repository는 유지한다.

### 공개 전 점검 — 개발 검증 완료 · 배포 전 최종 재확인 예정

- 키보드만으로 열기, 선택, diff 이동과 새로고침을 마칠 수 있다.
- VoiceOver 이름과 포커스 순서가 명확하다.
- System, Light, Dark와 Reduce Motion을 확인한다.
- 많은 Repository, 많은 변경 파일과 큰 diff fixture에서 창 조작이 멈추지 않는다.
- untracked 파일 삭제, rename·hunk discard, 충돌 해결, 원격 통신, 그래프, 여러 창과 지속적인 파일 감시는 포함하지 않는다.
- 첫 화면에서 Repository와 HEAD를 바로 식별할 수 있다.
- 탐색이 끝나기 전에도 발견한 Repository를 열 수 있다.
- Repository, 파일과 diff를 키보드로 선택할 수 있다.
- Clean, detached HEAD, 충돌과 오류를 색 없이도 구분할 수 있다.
- 마지막 성공 상태와 현재 상태를 혼동하지 않는다.
- 모든 실패 상태에 사용자가 실행할 수 있는 다음 행동이 있다.
- 조회 동작이 Git 상태를 바꾸지 않는다.

빈 Repository Library와 깨끗한 Repository Workspace의 세로 확장 결함은 수정했고, 변경이 있는 Workspace를 포함해 기본·최소·확대 창의 접근성 frame을 확인했다. 실제 키 입력과 macOS 접근성 트리로 ⌘O·Esc, Return·이중 클릭, 방향키로 파일과 diff 전환, ⌘R 새로고침을 확인했고 Repository·경로·HEAD와 목록 행의 이름은 의미를 포함하며 중복해 읽히지 않는다. Finder가 전달한 폴더는 앱 실행 전과 실행 중 모두 같은 메인 윈도우에서 열리고, 유효하지 않은 폴더는 오류를 표시하면서 기존 Workspace를 유지하는 것을 확인했다. 탐색 중 취소 뒤 발견 결과 유지, 접근 불가 Library Folder의 재시도·재연결·제거, Recent Activity 실패의 재시도, 새로고침 실패 뒤 이전 Workspace 유지와 복구도 실제 상태로 확인했다. Light·Dark의 기본·최소 창은 실제 픽셀 캡처로 Library 세 열의 상단 정렬, 좁은 창의 빈 상태와 동작 노출, Changes 목록보다 diff에 더 넓은 면적을 두는 2열 균형을 확인했다. System은 현재 macOS Dark 설정을 그대로 따르며, 사용자 지정 애니메이션이 없어 Reduce Motion용 별도 분기 없이 표준 SwiftUI 동작을 따르는 것을 확인했다. 두 환경은 배포 전 최종 검수에서 다시 확인한다. 대량 경로는 임시 Library의 Repository 32개, 변경 파일 501개와 12,000행 diff fixture로 검증한다.

실제 53개 Repository Library의 전체 탐색은 Repository당 Git 검증을 한 번으로 줄이고 최대 4개씩 실행한 뒤 3회 0.20~0.27초로 측정했다.

공식 Git 저장소 `f78ce2f7b6`의 4,850개 파일에 500 commit 전 tree를 적용한 실제 fixture에서는 tracked 1,335개와 untracked 47개를 합쳐 변경 1,382개가 나왔다. 전체 diff는 약 7.1MB, 가장 큰 단일 파일 diff는 약 283KB였고 `RepositoryInspector`가 모든 파일을 19.8초에 읽는 동안 2MB 기본 한계에 걸린 파일은 없었다. 기본 2MB와 사용자 요청 시 16MB 확장 한계를 유지한다.

### 2A-1 · 파일 단위 Stage/Unstage — 완료

- 선택한 파일의 diff 헤더에서 전체 파일을 Stage하거나 Unstage한다.
- Status와 Folders 목록은 ⌘클릭·Shift 클릭 다중 선택과 우클릭 `Stage Selected`·`Unstage Selected`를 지원한다. Status의 ⌘A는 현재 선택 파일이 속한 그룹만, Folders의 ⌘A는 모든 변경 파일을 선택하며 diff는 마지막으로 선택한 한 파일을 유지한다.
- staged와 unstaged가 함께 있으면 두 동작을 모두 제공하고, 충돌 파일에는 제공하지 않는다.
- 실행 중에는 중복 입력을 막고, 성공하면 Repository snapshot과 선택한 diff를 다시 읽는다. 실패하면 기존 상태를 유지하고 오류를 알린다.
- 공백·한글·특수문자와 rename의 원본·새 경로를 명시적인 pathspec으로 전달한다.
- 최초 commit 전 Unstage도 파일을 삭제하지 않고 untracked 상태로 되돌린다.
- 일반 Commit 생성은 2A-2, hunk 단위 Stage/Unstage는 2A-3, 선택적 본문은 2A-4, Amend는 2A-5, 파일 단위 discard는 2A-6으로 분리한다. 충돌 해결은 이후 수직 슬라이스로 남긴다.

### 2A-2 · 일반 Commit 생성 — 완료

- Changes 하단에서 한 줄 제목을 입력하고 staged 변경으로 일반 commit을 만든다. `⌘Return`도 같은 동작을 실행한다.
- 빈 제목, staged 변경 없음과 미해결 충돌 상태에서는 Commit을 실행하지 않는다.
- 현재 index만 기록하고 unstaged 변경은 자동으로 포함하지 않는다.
- 사용자의 기존 Git identity, hook과 서명 설정을 우회하지 않는다.
- 실행 중 중복 입력을 막고, 성공하면 Repository snapshot과 최근 활동을 다시 읽을 수 있게 한다. 실패하면 staged 상태와 입력한 제목을 유지하고 Git 오류를 표시한다.
- hunk 단위 Stage/Unstage는 2A-3, 선택적 Commit 본문은 2A-4, Amend는 2A-5, 파일 단위 discard는 2A-6으로 분리한다. 충돌 해결은 이후 수직 슬라이스로 남긴다.

### 2A-3 · hunk 단위 Stage/Unstage — 완료

- 수정된 tracked 텍스트 파일은 diff의 각 hunk 헤더에서 해당 hunk만 Stage하거나 Unstage한다.
- Stage는 working tree diff의 선택 hunk만 index에 적용하고, Unstage는 staged diff의 선택 hunk만 index에서 되돌린다. 두 동작 모두 working tree 파일은 바꾸지 않는다.
- 실행 중 중복 입력을 막고, 성공하면 Repository snapshot과 선택 파일 diff를 다시 읽는다. 파일이 다시 바뀌어 patch를 적용할 수 없으면 기존 상태를 유지하고 Git 오류를 표시한다.
- 추적하지 않는 파일, 추가·삭제·rename, binary와 지원하지 않는 인코딩에는 hunk 동작을 제공하지 않고 파일 전체 Stage/Unstage를 유지한다.
- 선택적 Commit 본문은 2A-4, Amend는 2A-5, 파일 단위 discard는 2A-6으로 분리하고 충돌 해결은 이후 수직 슬라이스로 남긴다.

### 2A-4 · 선택적 Commit 본문 — 완료

- Changes 하단에서 필수 제목과 선택적 여러 줄 본문을 함께 작성한다. 본문이 없어도 기존 일반 Commit 흐름은 그대로 동작한다.
- 제목과 본문은 서로 다른 commit 문단으로 기록하며, 사용자의 Git identity, hook과 서명 설정을 우회하지 않는다.
- `⌘Return`은 두 입력 중 어디에 포커스가 있어도 현재 staged 변경을 Commit한다.
- 성공하면 두 입력을 비우고 Repository 상태를 다시 읽는다. 실패하면 staged 상태와 입력한 제목·본문을 유지한다.
- Amend는 2A-5, 파일 단위 discard는 2A-6으로 분리하고 충돌 해결은 이후 수직 슬라이스로 남긴다.

### 2A-5 · 최근 Commit Amend — 완료

- Changes 하단에서 `Amend last commit`을 명시적으로 선택하면 현재 staged 변경과 입력한 제목·본문으로 최신 commit을 교체한다.
- unstaged 변경은 포함하지 않고, 아직 commit이 없는 Repository와 미해결 충돌 상태에서는 실행하지 않는다.
- 사용자의 기존 Git identity, hook과 서명 설정을 우회하지 않으며 commit 수는 늘어나지 않는다.
- 성공하면 최신 HEAD와 Repository 상태를 다시 읽고 제목·본문·Amend 선택을 비운다. 실패하면 staged 상태와 입력·선택을 유지한다.
- 메시지만 바꾸는 Amend와 충돌 해결은 이후 수직 슬라이스로 남기고, 파일 단위 discard는 2A-6에서 다룬다.

### 2A-6 · tracked 파일의 unstaged 변경 Discard — 완료

- 선택한 tracked 파일의 unstaged 수정·타입 변경·삭제에만 `Discard…`를 제공한다.
- 확인 대화상자는 파일을 index 상태로 되돌리며 Gallae에서 실행 취소할 수 없음을 먼저 설명한다.
- staged와 unstaged 변경이 함께 있으면 working tree만 index 상태로 되돌려 staged 내용은 그대로 유지한다.
- 성공하면 Repository snapshot과 선택한 diff를 다시 읽고, 실패하면 기존 화면을 유지하며 오류를 표시한다.
- 충돌·untracked·rename 파일에는 제공하지 않는다. untracked 파일 삭제와 rename·hunk discard, 충돌 해결은 이후 수직 슬라이스로 남긴다.

### 3A-1 · 현재 HEAD의 최근 History — 완료

- Repository 헤더의 `Changes`/`History` 전환으로 같은 Workspace에서 이동한다.
- 현재 HEAD에서 도달 가능한 최신 commit 최대 100개를 최신순으로 읽고, 제목·작성자·시간·축약 SHA를 목록에 표시한다.
- 선택한 commit은 제목·본문·작성자 이메일·전체 SHA·parent와 first-parent 기준 전체 patch를 보여 준다. root commit도 빈 tree 기준 patch를 표시한다.
- 목록·patch 로딩, commit이 없는 빈 상태와 각각의 실패·재시도 상태를 구분한다. 목록은 키보드 선택과 VoiceOver 이름을 제공한다.
- patch는 기본 2MB, 사용자 요청 시 16MB까지 확장하고 그보다 크거나 UTF-8이 아니면 원인을 표시한다.
- 이 단계는 조회 전용이다. commit 그래프, 모든 branch/ref, 검색·필터, 파일별 drill-down과 branch 이동·생성은 이후 수직 슬라이스로 남긴다.

### 3A-2 · 최근 History 검색 — 완료

- 현재 HEAD에서 읽은 최대 100개 commit을 메시지·작성자·이메일·SHA로 즉시 검색한다.
- 공백으로 나눈 검색어는 서로 다른 필드에 있어도 모두 일치해야 하며 대소문자를 구분하지 않는다.
- 검색은 추가 Git 실행 없이 메모리에서 수행하고, 선택한 commit이 결과에서 사라지면 첫 결과로 이동한다.
- 결과가 없으면 History 읽기 실패와 다른 빈 상태를 표시하고 같은 화면에서 검색을 지울 수 있다.
- 이 단계는 조회 전용이다. commit 그래프, 모든 branch/ref, 파일별 drill-down과 branch 이동·생성은 이후 수직 슬라이스로 남긴다.

### 3A-3 · 최근 commit의 ref 표시 — 완료

- 현재 History에 보이는 commit에 닿은 local branch, remote-tracking branch와 tag 이름을 행에 표시한다.
- annotated tag는 peeled commit에 연결하고 remote의 symbolic HEAD는 표시하지 않는다.
- 한 commit에 ref가 많아도 행에는 두 개까지만 보이고 나머지 수를 표시하며, VoiceOver 이름에는 모든 ref를 포함한다.
- ref 이름을 기존 메시지·작성자·SHA 검색 대상에도 포함한다.
- 이 단계는 조회 전용이다. commit graph, 파일별 drill-down과 branch 이동·생성은 이후 수직 슬라이스로 남긴다.

### 3A-4 · 현재 HEAD의 commit graph — 완료

- 최근 commit을 topology 순서로 읽고 기존 parent SHA로 lane과 merge 연결을 계산한다.
- 목록 왼쪽에서 일반 commit의 연속 관계와 merge의 분기·합류를 선과 점으로 표시한다.
- 검색 중에는 숨겨진 commit 사이를 잘못 잇지 않고 결과별 commit 점만 표시한다.
- VoiceOver 이름은 root commit과 parent가 여러 개인 merge commit을 텍스트로 구분한다.
- 이 단계는 조회 전용이다. 모든 ref를 함께 걷는 graph, 파일별 drill-down과 branch 이동·생성은 이후 수직 슬라이스로 남긴다.

### 3A-5 · Repository ref의 commit graph — 완료

- 현재 HEAD, local branch, remote-tracking branch와 tag에서 도달 가능한 최신 commit을 합쳐 최대 100개까지 topology 순서로 읽는다.
- stash와 notes는 범위에서 제외하고, detached HEAD처럼 branch ref가 없는 현재 commit도 명시적인 HEAD revision으로 포함한다.
- 다른 ref의 commit이 목록 앞에 와도 정확한 HEAD commit을 표시하고 처음 선택한다.
- 이 단계는 조회 전용이다. 파일별 drill-down과 branch 이동·생성은 이후 수직 슬라이스로 남긴다.

### 3A-6 · commit 변경 파일 drill-down — 완료

- 선택한 commit을 first parent와 비교한 변경 파일 목록을 상태와 함께 읽고 첫 파일을 선택한다. root commit은 빈 tree와 비교한다.
- rename은 원래 경로를 함께 표시하고, merge commit은 기존 상세와 같은 first-parent 기준을 유지한다.
- 선택한 파일의 patch만 읽으며 기본 2MB, 사용자 요청 시 16MB까지 확장한다. binary·UTF-8 아님·과대한 patch와 파일이 없는 commit을 구분한다.
- 파일 목록과 patch는 각각 로딩·실패·재시도 상태를 제공하고 키보드 선택과 VoiceOver 이름을 지원한다.
- 이 단계는 조회 전용이다. branch 이동·생성은 이후 수직 슬라이스로 남긴다.

### 3A-7 · 기존 local branch 전환 — 완료

- Repository 헤더의 현재 branch를 누르면 기존 local branch를 읽고 이름으로 즉시 검색한다.
- 현재 branch를 표시하며 detached HEAD에서도 local branch를 선택할 수 있다.
- 연결된 Worktree가 없는 branch는 `Switch`, Return 또는 행 이중 클릭으로 같은 전환 동작을 실행한다.
- 전환은 force·merge 옵션 없이 실행한다. local 변경과 충돌하면 기존 branch·index·working tree를 유지하고 오류를 표시한다.
- 성공하면 Repository snapshot, Changes와 History를 다시 읽고 새 HEAD를 선택한다.
- branch 생성, remote-tracking branch 전환과 stash 보조 동작은 이후 수직 슬라이스로 남긴다.

### 3A-8 · 현재 HEAD에서 local branch 생성 — 완료

- 기존 branch 선택기에서 `New Branch…`를 열고 현재 HEAD를 시작점으로 이름을 입력한다.
- Create 또는 Return으로 branch를 만들고 바로 전환한다. detached HEAD와 unborn branch도 같은 흐름을 지원한다.
- 빈 이름, 유효하지 않은 이름이나 이미 존재하는 branch는 만들지 않고 현재 branch·index·working tree와 입력값을 유지한다.
- 성공하면 Repository snapshot, Changes와 History를 다시 읽고 새 HEAD를 선택한다.
- 임의의 시작점 선택과 force-create는 포함하지 않으며, remote 게시와 upstream 설정은 branch 생성 뒤 4A-4 Publish에서 별도로 수행한다.

### 3A-9 · 연결된 Worktree 열기 — 완료

- branch 선택기는 `git worktree list --porcelain -z`로 existing Worktree와 local branch의 관계를 읽고, 다른 Worktree에서 체크아웃된 branch를 폴더 배지로 구분한다. 폴더명이 branch와 다르면 행 높이를 늘리지 않고 실제 폴더명을 표시하며, 긴 이름은 말줄임하고 전체 경로를 도움말과 VoiceOver로 제공한다.
- 해당 branch의 기본 동작은 현재 Repository의 HEAD·index·working tree를 바꾸는 Switch 대신 `Open Worktree`, Return 또는 행 이중 클릭으로 연결된 폴더를 같은 창의 Repository Workspace로 여는 것이다.
- 연결된 Worktree가 없는 branch는 기존의 안전한 Switch를 유지하고, detached·bare·prunable Worktree는 열기 대상으로 사용하지 않는다.
- `--ignore-other-worktrees` 같은 강제 전환과 Worktree 생성·삭제는 포함하지 않는다.
- 공백과 한글이 있는 경로를 포함한 실제 임시 linked Worktree 통합 테스트로 branch·폴더 관계를 확인한다.

### 4A-1 · 기본 remote Fetch — 완료

- Repository Workspace 상단에서 인자 없는 Fetch를 실행해 현재 Git 설정이 고르는 기본 remote의 remote-tracking ref를 갱신한다.
- 기존 credential helper와 SSH 환경을 사용하되 `GIT_TERMINAL_PROMPT=0`으로 표시할 수 없는 터미널 입력을 기다리지 않는다.
- 작업은 UI를 막지 않고 진행 상태와 Cancel을 표시하며 Escape로도 취소할 수 있다.
- 성공하면 Repository snapshot, upstream ahead/behind, Changes와 History를 다시 읽는다. HEAD·index·working tree는 바꾸지 않는다.
- remote가 없거나 Fetch가 실패하면 기존 Workspace를 유지하고 오류를 표시한다.
- Fetch 대상 선택은 4A-12, 명시적인 prune은 4A-13, 사용자가 켜는 자동 Fetch는 4A-14에서 잇는다.

### 4A-2 · configured upstream fast-forward Pull — 완료

- Repository Workspace 상단에서 인자 없는 Pull을 `--ff-only`로 실행해 현재 branch의 configured upstream으로 fast-forward한다.
- merge commit을 만들거나 local commit을 rebase하지 않는다. remote 변경과 겹치지 않는 local working tree 수정은 보존한다.
- 기존 credential helper와 SSH 환경을 사용하되 `GIT_TERMINAL_PROMPT=0`으로 표시할 수 없는 터미널 입력을 기다리지 않는다.
- 작업은 UI를 막지 않고 Fetch와 공유하는 remote operation 상태에서 진행·Cancel·Escape를 제공한다.
- 성공하면 Repository snapshot, upstream ahead/behind, Changes와 History를 다시 읽는다.
- upstream 없음, divergent history, local 변경 충돌이나 인증·네트워크 실패 시 현재 HEAD·index·working tree를 유지한다. Pull의 Fetch 단계에서 remote-tracking ref가 바뀌었으면 Repository를 다시 읽어 최신 divergence를 표시한다.
- merge/rebase 방식 선택, remote 선택, 강제 갱신과 자동 Pull은 이후 수직 슬라이스로 남긴다.

### 4A-3 · configured default destination Push — 완료

- Repository Workspace 상단에서 인자 없는 Push를 실행해 upstream이 설정된 현재 branch를 Git 설정이 고르는 기본 push 목적지에 보낸다.
- 기존 `push.default`와 remote 설정, credential helper와 SSH 환경을 사용하되 `GIT_TERMINAL_PROMPT=0`으로 표시할 수 없는 터미널 입력을 기다리지 않는다.
- force, refspec과 upstream 생성 옵션을 사용하지 않는다. non-fast-forward와 remote 거부는 Git 오류로 표시하고 기존 Repository 상태를 유지한다.
- 작업은 Fetch/Pull과 공유하는 remote operation 상태에서 진행·Cancel·Escape를 제공한다.
- 성공하면 Repository snapshot, upstream ahead/behind, Changes와 History를 다시 읽는다. HEAD·index·working tree와 local 수정은 바꾸지 않는다.
- Push 자체에는 `--set-upstream`을 사용하지 않는다. force·force-with-lease, tag·여러 ref 게시와 remote branch 삭제도 이후 범위로 남긴다.

### 4A-4 · upstream 없는 branch Publish — 완료

- upstream 없는 local branch에서는 Workspace 상단의 Push 자리를 Publish로 바꿔 표시한다. detached HEAD와 아직 commit이 없는 branch에서는 실행하지 않는다.
- remote가 정확히 하나일 때 현재 branch와 같은 이름의 remote branch 하나만 명시적으로 게시하고 `--set-upstream`으로 추적 관계를 만든다.
- force, tag·여러 ref 게시와 remote branch 삭제는 수행하지 않는다. remote가 없으면 4A-5에서 추가하고, 여러 개면 4A-6에서 목적지를 고른다.
- 작업은 기존 remote operation 상태에서 진행·Cancel·Escape를 제공한다.
- 성공하면 Repository snapshot, upstream ahead/behind, Changes와 History를 다시 읽는다. HEAD·index·working tree와 local 수정은 바꾸지 않는다.

### 4A-5 · Remote 추가 후 Publish — 완료

- Publish 대상 Repository에 remote가 하나도 없으면 Add Remote sheet를 열고 이름과 HTTPS·SSH URL 또는 local Repository 경로를 받는다. remote 이름은 `origin`을 기본값으로 둔다.
- 빈 입력은 실행하지 않으며 Cancel 또는 Escape는 Repository를 바꾸지 않는다. Add & Publish는 `git remote add` 뒤 4A-4와 같은 명시적 branch refspec과 `--set-upstream`으로 현재 branch 하나만 게시한다.
- 작업은 기존 remote operation 상태에서 진행·Cancel·Escape를 제공한다. remote 등록 뒤 Publish가 실패하거나 취소되면 등록된 remote는 유지해 다음 Publish에서 재사용한다.
- 성공하면 Repository snapshot, Tracking ahead/behind, Changes와 History를 다시 읽는다. HEAD·index·working tree와 local 수정은 바꾸지 않는다.
- 실제 bare remote를 사용한 통합 테스트로 remote 설정, 같은 이름의 remote branch, Tracking 관계와 local 상태 보존을 확인한다.

### 4A-6 · 여러 Remote Publish 목적지 선택 — 완료

- upstream 없는 branch에 configured remote가 둘 이상이면 정렬된 remote 이름을 sheet에 보여 주고 하나를 고르게 한다.
- Cancel 또는 Escape는 Repository를 바꾸지 않는다. Publish는 선택한 remote에 현재 branch와 같은 이름의 branch 하나만 명시적으로 게시하고 `--set-upstream`으로 Tracking 관계를 만든다.
- force하지 않으며 선택하지 않은 remote와 현재 HEAD·index·working tree·local 수정은 바꾸지 않는다.
- 실제 bare remote 두 개를 사용한 통합 테스트로 선택한 remote만 갱신되고 다른 remote와 local 상태는 그대로인지 확인한다.

### 4A-7 · configured Remote 조회 — 완료

- Repository Workspace 상단의 Remotes에서 정렬된 remote 이름과 Git이 해석한 Fetch·Push URL을 조회하고 선택해 복사할 수 있다.
- 로딩, remote 없음과 실패·재시도를 같은 sheet에서 구분한다.
- 이 단계는 조회 전용이며 HEAD·index·working tree와 ref를 바꾸지 않는다.
- Fetch와 Push URL이 다른 실제 임시 Repository 통합 테스트로 값과 local 상태 보존을 확인한다.

### 4A-8 · configured Remote URL 편집 — 완료

- Remotes 목록의 Edit에서 기존 remote 이름은 유지하고 Fetch·Push URL을 각각 편집한다.
- 두 URL은 현재 값으로 시작하며 빈 입력이나 바뀌지 않은 값은 저장하지 않는다. Cancel 또는 Escape는 Git 설정을 바꾸지 않는다.
- Save는 Git 설정의 첫 Fetch URL과 첫 Push URL만 바꾸고 remote에 연결하지 않는다. 실패하면 입력을 유지하고 다시 시도할 수 있다.
- 실제 임시 Repository 통합 테스트로 변경된 URL과 HEAD·index·working tree·ref 보존을 확인한다.

### 4A-9 · configured Remote 제거 — 완료

- Remotes 목록의 Remove에서 대상 remote를 고르고 macOS 확인 대화상자를 거쳐 제거한다.
- 확인 문구는 선택한 remote 설정과 연결된 local remote-tracking branch가 사라지며 remote Repository와 local branch·commit·작업 파일은 삭제되지 않는다고 설명한다.
- 성공하면 Repository snapshot, Remotes와 History를 다시 읽는다. 제거한 remote를 현재 branch가 Tracking 중이었다면 Tracking이 사라지고 Publish 상태로 바뀐다.
- 실제 bare remote 두 개를 사용한 임시 Repository 통합 테스트로 선택한 remote 설정·추적 ref만 사라지고 다른 remote, remote Repository와 HEAD·index·working tree·local branch·commit이 유지되는지 확인한다.

### 4A-10 · configured Remote Fetch 연결 시험 — 완료

- Remotes 목록에서 대상 remote의 configured Fetch URL을 `git ls-remote --quiet <remote> HEAD`로 읽어 연결 가능 여부를 확인한다. Push URL과 쓰기 권한은 시험하지 않는다.
- 기존 credential helper와 SSH 환경을 사용하되 `GIT_TERMINAL_PROMPT=0`으로 표시할 수 없는 터미널 인증 입력을 기다리지 않는다.
- 진행 상태와 Cancel을 표시하며 Escape로도 Git 프로세스를 중단한다. 성공하면 `Reachable`, 실패하면 Git 오류와 재시도 경로를 표시한다.
- `--exit-code`를 사용하지 않아 아직 ref가 없는 빈 Remote도 연결 성공으로 처리한다. 시험 전후 Remote 설정·local ref와 object·HEAD·index·working tree는 바꾸지 않는다.
- 실제 빈 bare Remote와 유효하지 않은 Fetch 경로를 사용한 임시 Repository 통합 테스트로 성공·실패, Push URL 비접촉과 local 상태 보존을 확인한다.

### 4A-11 · configured Remote 이름 변경 — 완료

- Edit Remote에서 기존 이름과 Fetch·Push URL을 함께 편집한다. 빈 이름이나 바뀌지 않은 값만으로는 저장하지 않는다.
- 이름이 바뀌면 `git remote rename <old> <new>`를 사용해 관련 Remote 설정과 local remote-tracking branch를 새 이름으로 옮긴다. 현재 branch의 Tracking 설정도 Git이 함께 갱신한다.
- Git이 허용하지 않는 이름, 이미 존재하는 이름이나 사라진 Remote는 저장하지 않고 입력을 유지하며 오류를 표시한다.
- 이름 변경 뒤 Fetch·Push URL도 같은 Save에서 적용한다. 후속 URL 저장이 실패하면 가능한 범위에서 기존 URL과 Remote 이름으로 되돌린다.
- 성공하면 Repository snapshot과 Remotes를 갱신한다. HEAD·index·working tree·local branch·commit과 remote Repository는 바꾸지 않으며 Remote에 연결하지 않는다.
- 실제 bare Remote를 사용한 임시 Repository 통합 테스트로 Tracking 설정과 remote-tracking ref 이동, staged·working tree·remote Repository 보존을 확인한다.

### 4A-12 · Fetch 대상 Remote 선택 — 완료

- Repository Workspace 상단에서 Fetch를 누르면 configured Remote가 하나일 때는 바로 가져오고, 둘 이상이면 정렬된 이름을 sheet에 보여 주고 하나를 고르게 한다.
- 선택한 Remote 이름을 명시해 해당 Remote의 configured refspec과 remote-tracking ref만 갱신한다. 선택하지 않은 Remote ref는 바꾸지 않는다.
- Cancel 또는 Escape는 Repository를 바꾸지 않는다. 진행 상태와 Cancel은 기존 Fetch 흐름을 그대로 사용한다.
- 성공하면 Repository snapshot, Tracking ahead/behind, Changes와 History를 다시 읽는다. HEAD·index·working tree와 local 수정은 바꾸지 않는다.
- 실제 bare Remote 두 개를 사용한 임시 Repository 통합 테스트로 선택한 Remote만 갱신되고 다른 Remote와 local 상태가 유지되는지 확인한다.
- 명시적인 prune은 4A-13, 자동 Fetch는 4A-14에서 잇는다.

### 4A-13 · 선택한 Remote Fetch & Prune — 완료

- Repository Workspace 상단의 Fetch는 기존 기본 동작을 유지하고, 메뉴에서만 `Fetch & Prune`을 명시적으로 제공한다.
- Remote가 하나면 바로 실행하고 둘 이상이면 기존 선택 sheet에서 하나를 고른다. Cancel 또는 Escape는 실행하지 않고 Repository를 그대로 둔다.
- 선택한 Remote 이름과 `--prune`을 명시해 configured refspec을 가져오고 Remote에서 사라진 local tracking ref를 정리한다. 선택하지 않은 Remote ref는 바꾸지 않는다.
- 성공하면 Repository snapshot, Tracking ahead/behind, Changes와 History를 다시 읽는다. local branch·HEAD·index·working tree와 local 수정은 바꾸지 않는다.
- 기본 Fetch에는 `--prune`을 강제하지 않고 기존 Git 설정을 따른다.
- 실제 bare Remote에서 branch를 삭제한 임시 Repository 통합 테스트로 기본 Fetch와 명시적 prune의 차이, local 상태 보존을 확인한다.

### 4A-14 · 자동 Fetch — 완료

- Repository Workspace의 Fetch 메뉴에서 `Fetch Automatically`를 켜거나 끈다. 기본값은 꺼짐이며 선택을 저장한다.
- 켜져 있으면 Gallae와 Workspace가 활성인 동안 5분마다 인자 없는 Fetch를 실행해 현재 branch와 Git 설정이 고르는 기본 Remote를 갱신한다. 여러 Remote를 임의로 순회하지 않는다.
- 다른 Repository 작업이 진행 중인 주기는 건너뛴다. 자동 Fetch는 `--prune`을 강제하지 않고 사용자의 Git 설정을 따른다.
- 진행 상태와 Cancel·Escape를 제공한다. Cancel은 현재 Fetch만 중단하고 다음 주기는 유지한다.
- 성공하면 Repository snapshot, Tracking ahead/behind, Changes와 History를 다시 읽는다. 실패하면 자동 Fetch를 끄고 오류를 한 번 표시한다.
- 실제 bare Remote를 사용한 임시 Repository 통합 테스트로 설정 저장, configured default Fetch와 local HEAD·index·working tree 보존을 확인한다.

### 5A-1 · Stash 목록과 patch 조회 — 완료

- Repository 헤더의 `Stashes`에서 최신 Stash를 최대 100개까지 최신순으로 보여 준다.
- Stash를 선택하면 함께 저장된 tracked·untracked 파일을 읽고, 선택한 파일 하나의 patch를 표시한다.
- 목록·파일·patch 로딩, 빈 상태, 오류와 재시도를 구분하며 List 선택으로 키보드와 VoiceOver 경로를 제공한다.
- patch는 History와 같은 2MB 기본·16MB 확장 미리보기와 binary·UTF-8 아님 상태를 사용한다.
- 이 슬라이스는 조회 전용이며 Stash 생성·적용·삭제와 Repository 상태 변경은 포함하지 않는다.
- 실제 임시 Repository에서 tracked·untracked 변경을 포함한 Stash를 만들어 최신순 목록, 특수문자 경로와 선택 파일 patch를 통합 테스트한다.

### 5A-2 · 새 Stash 생성 — 완료

- Stashes 헤더의 `New Stash`에서 선택적인 메시지를 입력하고 새 Stash를 만든다.
- staged·unstaged tracked 변경은 항상 저장한다. `Include Untracked Files`는 기본으로 끄며 사용자가 켠 경우에만 untracked 파일을 함께 저장하고 ignored 파일은 포함하지 않는다.
- 아직 첫 commit이 없거나 충돌이 있거나 선택한 옵션으로 저장할 변경이 없으면 이유를 보여 주고 실행하지 않는다.
- 생성 전 Cancel 또는 Escape는 Repository를 바꾸지 않는다. 실행 중에는 진행 상태를 표시하고 sheet를 닫지 않으며, 실패하면 메시지와 옵션을 유지해 다시 시도할 수 있다.
- 성공하면 HEAD와 commit을 유지하고 index와 tracked working tree를 HEAD 상태로 되돌린 뒤 Repository와 Stash 목록을 다시 읽어 새 항목을 선택한다.
- 실제 임시 Repository 통합 테스트로 기본 생성은 untracked 파일을 남기고, 옵션 생성은 tracked·untracked 변경을 함께 저장하는지 확인한다.
- Stash 삭제는 `5A-4`에서 다룬다.

### 5A-3 · 선택한 Stash 적용 — 완료

- 선택한 Stash 상세에서 `Apply`를 실행해 저장된 변경을 현재 Repository에 복원한다.
- 안정적인 Stash commit ID로 `git stash apply --index`를 실행해 staged·unstaged 상태와 함께 저장된 untracked 파일을 복원하며, 성공해도 Stash 항목은 남긴다.
- force, pop이나 drop은 사용하지 않으며 HEAD와 commit은 바꾸지 않는다.
- 현재 변경과 겹치거나 새 HEAD와 충돌해 적용이 실패하면 Repository를 다시 읽어 기존 변경이나 conflict 상태를 즉시 표시하고 Stash를 유지한다.
- 실행 중 진행 상태를 표시하고 중복 실행을 막으며, `Apply` 버튼과 VoiceOver 설명으로 키보드·보조 기술 경로를 제공한다.
- 실제 임시 Repository 통합 테스트로 staged·unstaged·untracked 복원, dirty working tree 실패와 conflict 상태 보존을 확인한다.
- Stash 삭제는 `5A-4`에서 다룬다.

### 5A-4 · 선택한 Stash 삭제 — 완료

- 선택한 Stash 상세의 `Delete…`는 macOS 확인 대화상자를 거친 뒤 한 항목만 영구 삭제한다.
- 확인 문구는 저장된 변경을 적용하지 않고 Gallae에서 실행 취소할 수 없으며 HEAD·index·working tree는 바뀌지 않는다고 설명한다.
- 삭제 직전에 안정적인 Stash commit ID를 현재 목록에서 다시 찾아 최신 reflog reference로 삭제한다. 번호가 바뀌었거나 선택한 항목이 사라졌을 때 다른 Stash를 대신 삭제하지 않는다.
- 성공하면 Repository와 Stash 목록을 다시 읽어 남은 첫 항목을 선택한다. 실패하면 현재 상태를 다시 읽고 오류를 표시한다.
- 실행 중 중복 입력을 막고 `Delete…`의 destructive role, 확인·Cancel과 VoiceOver 설명으로 위험도와 키보드·보조 기술 경로를 제공한다.
- 실제 임시 Repository 통합 테스트로 선택 뒤 번호가 바뀐 Stash만 삭제되고 다른 Stash, HEAD·index·working tree와 untracked 파일이 유지되는지 확인한다.

### 5B-1 · 선택한 일반 commit Revert — 완료

- History 상세의 `Revert`는 선택한 commit의 변경을 반대로 적용한 새 commit을 현재 HEAD 위에 만든다. 기존 commit과 이후 History는 다시 쓰지 않는다.
- 실행 직전에 Repository를 다시 읽어 변경이 없는 attached local branch인지 확인하고, 선택한 commit이 현재 HEAD의 ancestor인지 안정적인 전체 SHA로 검증한다.
- merge commit은 mainline 선택이 필요하므로 이 슬라이스에서 비활성화하고 `5B-2`로 분리한다.
- `git revert --no-edit`로 Git의 기본 메시지를 사용한다. 성공하면 Repository와 History를 다시 읽고 새 HEAD를 표시한다.
- 충돌이나 실패가 발생하면 `git revert --abort`를 실행하고 기존 HEAD와 깨끗한 index·working tree가 복원됐는지 확인한다. 복원이 완전하지 않으면 실제 상태를 다시 읽고 오류를 표시한다.
- 실행 중 중복 입력을 막고, 비활성화 이유를 도움말과 VoiceOver 설명으로 제공한다.
- 실제 임시 Repository 통합 테스트로 선택한 변경만 반대로 적용한 새 commit이 생기고 이후 commit, 기존 History와 깨끗한 working tree가 유지되는지 확인한다.

### 5B-2 · merge commit mainline 선택 Revert — 완료

- merge commit 상세의 `Revert`는 parent 번호와, 읽은 History에 있는 경우 각 parent의 commit 제목·축약 SHA를 sheet에 보여 준다.
- 사용자가 mainline parent를 직접 고르기 전에는 실행하지 않는다. Cancel 또는 Escape는 Repository를 바꾸지 않는다.
- 선택한 번호를 `git revert --mainline <번호> --no-edit <전체 SHA>`로 전달해 merge가 그 parent에 가져온 tree 변경을 반대로 적용한 새 commit을 만든다.
- 기존 merge commit과 History는 유지하며, clean attached local branch·현재 HEAD ancestor 검증과 실패 시 자동 abort·복원 확인은 일반 commit Revert와 같다.
- parent 선택은 radio group과 텍스트 번호·제목·SHA로 키보드와 VoiceOver에서도 식별할 수 있다.
- 실제 임시 Repository 통합 테스트로 parent 1을 mainline으로 선택하면 그 parent의 변경은 유지되고 merge가 가져온 다른 parent의 변경만 반대로 적용되는지 확인한다.

### 5C-1 · 선택한 과거 commit으로 mixed Reset — 완료

- History 상세의 `Reset…`은 변경이 없는 attached local branch에서 현재 HEAD의 ancestor인 과거 commit에만 제공한다. 현재 HEAD, 다른 branch의 commit, detached HEAD와 unborn branch에는 실행하지 않는다.
- Reset sheet는 현재 branch, 대상 commit 제목·축약 SHA, 이후 commit이 이 local branch에서 빠진다는 점과 working tree·Remote branch는 유지된다는 점을 설명하고 mixed mode를 기본으로 제시한다. Cancel 또는 Escape는 Repository를 바꾸지 않는다.
- `git reset --mixed <전체 SHA>`로 local branch와 index를 대상 commit에 맞추고 working tree 파일은 그대로 둔다. 되돌린 commit의 파일은 unstaged 또는 untracked 변경으로 즉시 표시한다.
- 실패하면 실행 전 HEAD로 mixed Reset을 시도하고 깨끗한 Repository가 복원됐는지 확인한다. 복원이 완전하지 않으면 실제 상태를 다시 읽고 명확히 경고한다.
- 성공하면 Repository와 History를 다시 읽어 선택한 commit을 새 HEAD로 표시한다. 다른 ref가 이후 commit을 가리키면 전체 History에는 계속 나타날 수 있다.
- Reset 자체에는 다른 branch로의 이동과 Reflog 지점 복구를 포함하지 않으며, 복구 branch 생성은 `5D-2`에서 제공한다.
- 실제 임시 Repository 통합 테스트로 branch 이동, index 초기화, working tree 파일 내용 보존과 unstaged·untracked 상태를 확인한다.

### 5C-2 · staged 상태를 보존하는 soft Reset — 완료

- 같은 Reset sheet에서 soft mode를 고르면 `git reset --soft <전체 SHA>`로 현재 local branch만 대상 commit으로 옮기고 index와 working tree는 그대로 둔다.
- 되돌린 commit의 변경은 staged 상태로 즉시 표시한다. mixed mode는 계속 기본값이며 unstaged·untracked 상태를 만드는 기존 동작을 유지한다.
- clean attached local branch, 현재 HEAD의 과거 ancestor commit 검증과 실패 시 실행 전 HEAD·깨끗한 상태 복원 확인은 mixed Reset과 같다.
- mode 선택은 radio group과 설명 텍스트로 키보드와 VoiceOver에서도 차이를 식별할 수 있다. Cancel 또는 Escape는 Repository를 바꾸지 않는다.
- 성공하면 Repository와 History를 다시 읽어 대상 commit을 새 HEAD로 표시한다. Remote branch는 바꾸지 않는다.
- 실제 임시 Repository 통합 테스트로 branch 이동, index·working tree 내용 보존과 staged 상태를 확인한다.
- Reflog 지점의 복구 branch 생성은 `5D-2`에서 제공한다.

### 5C-3 · working tree를 폐기하는 hard Reset — 완료

- 같은 Reset sheet에서 hard mode를 고르면 `git reset --hard <전체 SHA>`로 현재 local branch, index와 working tree를 대상 commit에 맞춘다. mixed mode는 계속 기본값이다.
- 이후 commit에서 추가된 tracked 파일은 제거되고 파일 내용은 대상 commit으로 교체된다. 대상 파일을 막는 untracked 파일이나 폴더도 Git에 의해 삭제될 수 있음을 설명한다.
- Hard는 Gallae에서 실행 취소할 수 없으므로 mode 선택 뒤 별도의 파괴적 확인을 한 번 더 거친다. 확인을 취소하면 Reset sheet로 돌아가며 Repository는 바뀌지 않는다.
- clean attached local branch, 현재 HEAD의 과거 ancestor commit 검증과 실패 시 실행 전 HEAD·tracked 상태 복원 확인은 기존 Reset과 같다. Remote branch는 바꾸지 않는다.
- 성공하면 Repository와 History를 다시 읽어 대상 commit을 새 HEAD로 표시하고 변경이 없는 working tree를 보여 준다.
- mode와 위험 설명, 확인 버튼은 키보드와 VoiceOver로 식별할 수 있다.
- 실제 임시 Repository 통합 테스트로 branch·index·working tree 이동, 대상 파일 내용 복원과 이후 추가된 tracked 파일 제거를 확인한다.

### 5D-1 · Reflog 복구 지점 조회 — 완료

- Repository 헤더의 `Reflog`에서 현재 Repository의 HEAD 이동 기록을 최대 100개까지 최신순으로 보여 준다.
- 각 항목은 순서 기반 selector, 전체 commit SHA, 기록자, 시각과 Git action을 표시한다. branch 전환과 Reset처럼 HEAD를 옮긴 작업도 같은 목록에서 확인한다.
- Reflog가 비었거나 읽기에 실패하면 별도 상태와 재시도를 제공하며, 목록 선택은 Repository·HEAD·index·working tree를 바꾸지 않는다.
- Git 유지 관리에 따라 오래된 항목이 만료될 수 있음을 상세에 알린다. 선택한 지점의 복구 branch 생성은 `5D-2`에서 제공한다.
- 실제 임시 Repository에서 commit, branch 전환과 hard Reset을 만든 뒤 최신순 selector·SHA·action을 읽고 Repository 상태가 유지되는지 통합 테스트한다.

### 5D-2 · Reflog 지점에서 복구 branch 생성 — 완료

- 선택한 Reflog 상세에서 `Create Recovery Branch…`를 열고 이름을 입력해 전체 commit SHA를 시작점으로 새 local branch를 만든 뒤 전환한다.
- 기존 local branch ref를 강제로 옮기거나 재생성하지 않는다. Cancel 또는 Escape는 Repository를 바꾸지 않는다.
- 빈 이름은 실행하지 않으며 유효하지 않거나 이미 존재하는 이름, checkout을 막는 local 변경이 있으면 Git의 오류를 보여 주고 branch·index·working tree와 입력을 유지한다.
- 성공하면 Repository, Changes, History와 Reflog를 새 HEAD 기준으로 다시 읽는다. 이름 입력, 기본 동작과 취소는 키보드와 VoiceOver로 식별할 수 있다.
- 실제 임시 Repository에서 Reset 전 commit을 Reflog로 찾은 뒤 복구 branch가 그 commit을 가리키고 기존 branch는 그대로인지 확인한다. 충돌 시 새 branch를 남기지 않고 local 파일을 보존하는지도 검증한다.

### 5E-1 · 다른 local branch fast-forward Merge — 완료

- Repository 상단의 `Merge`에서 현재 branch를 제외한 local branch 하나를 선택하고 현재 branch를 `git merge --ff-only`로 fast-forward한다.
- detached HEAD와 unborn branch에서는 진입을 비활성화한다. 다른 branch가 없으면 빈 상태, 목록 읽기 실패에는 같은 sheet의 재시도를 제공한다.
- Merge 또는 Return으로 실행하고 Cancel 또는 Escape는 Repository를 바꾸지 않는다. 선택과 동작은 키보드와 VoiceOver로 식별할 수 있다.
- divergent history, local 변경 충돌이나 Git 실패에는 merge commit·rebase·force를 사용하지 않고 기존 HEAD·index·working tree를 유지한다. 겹치지 않는 local 변경과 source branch도 그대로 둔다.
- 성공하면 Repository, Changes, History와 Reflog를 새 HEAD 기준으로 다시 읽는다.
- 실제 임시 Repository 통합 테스트로 fast-forward 뒤 현재 branch가 source commit을 가리키고 겹치지 않는 local 변경이 보존되는지 확인한다. divergent branch는 거부하고 HEAD와 local 파일을 유지하는지도 검증한다.

### 5E-2 · divergent local branch Merge commit 생성 — 완료

- 기존 Merge sheet에서 source local branch를 고른 뒤 `Fast-Forward` 또는 `Create Merge Commit`을 명시적으로 선택한다. Fast-Forward가 기본 동작이며 Return도 이를 실행한다.
- Merge commit은 변경이 없는 attached local branch에서만 활성화한다. 실행 직전에 branch 상태와 양방향 ancestor 관계를 다시 읽고, 실제 divergent history가 아니면 Fast-Forward를 사용하도록 안내한다.
- `git merge --no-ff --no-edit`로 Git의 기본 merge message와 사용자의 identity·hook·서명 설정을 따른다. source branch와 Remote branch는 바꾸지 않는다.
- 충돌이나 Git 실패에는 `git merge --abort`를 실행하고 필요하면 실행 전 HEAD에 `git reset --merge`로 복구한 뒤 original HEAD와 깨끗한 상태를 확인한다. 복원이 끝나지 않으면 실제 Repository 상태를 다시 읽어 경고와 함께 보여 준다.
- 성공하면 Repository, Changes, History와 Reflog를 새 merge commit 기준으로 다시 읽는다. branch 선택과 두 동작, 취소는 키보드와 VoiceOver로 식별할 수 있다.
- 실제 임시 Repository 통합 테스트로 merge commit의 두 parent와 source branch 보존을 확인한다. 충돌 fixture에서는 자동 중단 뒤 original HEAD·깨끗한 working tree·source branch가 유지되는지 검증한다.

### 5F-1 · 현재 branch를 다른 local branch 위로 Rebase — 완료

- Repository 상단의 `Integrate`는 기존 Fast-Forward·Merge Commit과 함께 `Rebase Current Branch`를 제공하고 같은 local branch 목록을 사용한다. Fast-Forward와 Return은 기존 기본 동작을 유지한다.
- Rebase는 변경이 없는 attached local branch에서만 활성화한다. 현재 branch의 고유 commit ID를 다시 쓰며 Gallae는 force-push하지 않는다는 점을 실행 전에 표시한다.
- 실행 직전에 Repository와 local branch 목록을 다시 읽고 `git rebase --no-update-refs <선택한 branch>`로 현재 branch만 선택한 branch tip 위에 다시 적용한다. 선택한 branch와 다른 local·Remote branch는 바꾸지 않는다.
- 충돌이나 Git 실패에는 `git rebase --abort`를 실행한 뒤 original branch·HEAD와 깨끗한 상태가 복원됐는지 확인한다. 복원이 끝나지 않으면 실제 Repository 상태를 다시 읽어 경고와 함께 보여 준다.
- 성공하면 Repository, Changes, History와 Reflog를 다시 읽는다. branch 선택과 세 동작, 취소는 키보드와 VoiceOver로 식별할 수 있다.
- 실제 임시 Repository 통합 테스트로 현재 branch commit이 선택한 branch 위에서 새 commit으로 바뀌고 선택한 branch ref가 유지되는지 확인한다. 충돌 fixture에서는 자동 중단 뒤 original branch·HEAD·파일과 깨끗한 working tree가 복원되는지 검증한다.

### 6A-1 · 충돌 파일의 3-way 내용 검사 — 완료

- Changes에서 충돌 파일을 선택하면 `git ls-files --stage -z`로 Git index의 stage 1·2·3 object를 찾고 Base·Ours·Theirs 순서의 같은 너비 열로 보여 준다.
- 각 열은 역할과 stage 번호, 행 번호를 표시하며 텍스트 선택과 독립 스크롤을 지원한다. 해당 stage가 없는 add/add 충돌과 빈 파일, binary, 지원하지 않는 인코딩, 큰 파일도 서로 다른 상태로 설명한다.
- 기존 diff 로딩·오류·재시도와 선택 전환 취소 흐름을 재사용하고, 충돌 파일 선택과 세 열의 의미를 키보드·VoiceOver에서 식별할 수 있게 한다.
- 이 검사는 `cat-file blob`으로 object 내용만 읽고 HEAD·index·working tree를 바꾸지 않는다.
- 실제 임시 Repository 통합 테스트로 일반 content 충돌의 Base·Ours·Theirs 내용과 add/add 충돌의 누락된 Base를 확인하며, 검사 전후 Repository 상태와 working tree 파일이 같은지도 검증한다.

### 6A-2 · 충돌 파일을 Ours 또는 Theirs로 해결 — 완료

- 충돌 비교 헤더에서 `Use Ours…` 또는 `Use Theirs…`를 고르고 파일 교체와 stage 결과를 확인한 뒤 실행한다. 선택한 쪽에 해당 stage가 없으면 파일 삭제를 해결 결과로 명확히 알린다.
- 실행 직전에 `git ls-files --stage -z`로 해당 경로가 여전히 unmerged인지 다시 확인한다. 선택한 stage가 있으면 `git checkout --ours|--theirs`와 `git add`로, 없으면 `git rm`으로 working tree와 index를 함께 해결한다.
- 성공하면 Repository와 diff를 다시 읽고 HEAD는 유지한다. 실패하면 실제 Repository를 다시 읽어 부분적으로 바뀐 상태도 숨기지 않고 오류를 표시한다.
- Ours·Theirs 선택과 확인·취소는 키보드와 VoiceOver로 식별할 수 있으며, binary나 지원하지 않는 인코딩도 blob 전체 버전으로 해결할 수 있다.
- 실제 임시 Repository 통합 테스트로 Ours·Theirs 내용 적용, index의 unmerged entry 제거, HEAD 보존과 선택한 쪽에 파일이 없는 modify/delete 충돌의 staged 삭제를 검증한다.

### 6A-3 · 현재 working tree 내용으로 충돌 해결 — 완료

- 충돌 비교 헤더의 `Mark Resolved…`는 현재 working tree 상태를 index에 기록한다. 파일이 없으면 staged 삭제로 해결하며 Ours·Theirs 중 하나로 working tree를 교체하지 않는다.
- 확인 대화상자는 현재 디스크 상태와 삭제 가능성, Gallae가 충돌 marker를 검사하지 않는다는 점을 실행 전에 설명한다. Cancel 또는 Escape는 Repository를 바꾸지 않는다.
- 실행 직전에 `git ls-files --stage -z`로 해당 경로가 여전히 unmerged인지 다시 확인하고, 선택한 literal pathspec 하나만 `git add --all`로 stage한다.
- 성공하면 Repository와 diff를 다시 읽고 HEAD와 다른 충돌 파일은 유지한다. 실패하면 실제 Repository 상태를 다시 읽어 부분적으로 바뀐 상태도 숨기지 않는다.
- 실행과 확인은 키보드와 VoiceOver로 식별할 수 있다.
- 실제 임시 Repository 통합 테스트로 외부에서 합친 현재 파일 내용이 staged 해결 결과가 되고 unmerged entry가 사라지며 HEAD가 유지되는지 확인한다.

### 6A-4 · 진행 중인 Merge·Rebase 상태 검사 — 완료

- `git rev-parse --path-format=absolute --git-path`로 현재 worktree의 `MERGE_HEAD`, `rebase-merge`와 `rebase-apply`를 찾아 linked worktree에서도 진행 중인 Merge·Rebase를 구분한다.
- Repository snapshot에 남은 unmerged 파일 수와 Continue 가능 여부를 포함하고, 충돌 해결 뒤 작업 표식이 유지되는 동안 즉시 `Ready to Continue`로 갱신한다.
- Workspace 상단에서 작업 종류, 남은 충돌 수와 Continue·Abort 경로를 색 외의 텍스트로 표시한다. 이 단계는 조회 전용이며 HEAD·index·working tree를 바꾸지 않는다.
- 실제 충돌 Merge와 Rebase를 중단하지 않은 임시 Repository 통합 테스트로 해결 전후 상태를 확인한다.

### 6A-5 · 진행 중인 Merge·Rebase Continue·Abort — 완료

- Workspace 상태 영역에서 Continue와 Abort를 직접 실행한다. Continue는 충돌이 모두 해결됐을 때만 활성화하고, Abort는 해결 중 만든 변경이 사라질 수 있음을 확인한다.
- 실행 직전에 실제 작업 상태를 다시 검사하고 별도 편집기 없이 Git의 기본 메시지로 `merge --continue` 또는 `rebase --continue`를 실행한다. Abort는 해당 Git 작업의 `--abort`를 사용한다.
- 성공·실패 뒤 실제 Repository 상태를 다시 읽어 다음 Rebase 충돌이나 부분적으로 바뀐 결과도 숨기지 않는다. Rebase Skip은 포함하지 않는다.
- 실제 충돌 Merge와 Rebase 임시 Repository 통합 테스트로 Abort의 원래 상태 복원과 Continue의 최종 commit 관계를 확인한다.
- Continue·Abort, 확인과 취소는 키보드와 VoiceOver에서 서로 다른 동작으로 식별할 수 있다.

### 6B-1 · Interactive Rebase 대상 commit 계획 검사 — 완료

- History에서 고른 현재 branch ancestor commit부터 현재 HEAD까지를 오래된 순서의 기본 `pick` 계획으로 미리 본다. 각 행은 동작, 제목과 축약 SHA를 함께 보여 준다.
- Git의 기본 선형 Interactive Rebase와 맞춰 merge commit은 계획에서 제외하고 그 사실을 화면에 표시한다. root commit부터의 범위도 읽을 수 있다.
- attached local branch에 진행 중인 Git 작업이 없을 때만 계획을 만들며, 실행 직전에 선택한 commit이 실제 현재 HEAD의 ancestor인지 다시 확인한다.
- 계획 조회는 HEAD·index·working tree를 바꾸지 않는다. 로딩·빈 결과·오류와 다시 시도, 닫기·Escape와 VoiceOver 경로를 제공한다.
- 실제 임시 Repository 통합 테스트로 선택한 commit부터 HEAD까지의 순서와 기본 `pick` 대상을 확인하고 검사 전후 Repository snapshot이 같은지 검증한다.

### 6B-2 · Interactive Rebase 계획 순서·동작 편집 — 완료

- 기본 계획의 각 행에서 `pick`, `reword`, `squash`, `fixup`, `drop`을 고르고 drag 또는 위·아래 버튼으로 순서를 바꾼다.
- `squash`·`fixup` 앞에 유지되는 commit이 없거나 모든 commit을 `drop`한 계획은 이유를 표시하고 검토 단계로 넘기지 않는다.
- 유효한 계획은 읽기 전용 검토 단계에서 최종 순서·동작·제목·SHA를 다시 확인한다. Back은 편집 상태를 유지하고 Close 또는 Escape는 Repository를 바꾸지 않는다.
- 동작 메뉴, 순서 버튼, 오류, 검토·Back·Close는 키보드와 VoiceOver로 식별할 수 있다. 실제 Rebase와 `reword` 메시지 입력은 실행하지 않는다.
- 실제 임시 Repository에서 만든 기본 계획을 편집·재정렬해 유효·무효 규칙과 검사 전후 Repository snapshot 보존을 통합 테스트한다.

### 6B-3 · 편집한 Interactive Rebase 계획 실행 — 완료

- 검토 단계에서 `reword` 메시지를 입력하고 commit ID가 바뀌는 위험과 강제 Push를 실행하지 않는다는 점을 확인한 뒤 현재 local branch에 계획을 적용한다.
- 실행 직전에 attached branch·깨끗한 working tree·진행 중인 작업 없음·대상 commit 범위와 계획을 다시 검사한다. 다른 local ref는 이동시키지 않는다.
- 성공·실패 뒤 실제 Repository 상태를 다시 읽는다. 충돌은 자동으로 숨기거나 중단하지 않고 기존 Rebase 충돌 해결·Continue·Abort 흐름으로 넘긴다.
- 실행 중 Cancel은 Rebase를 Abort하고 원래 branch·HEAD와 깨끗한 working tree가 복원됐는지 확인한다. 복원 실패는 별도 오류로 구분한다.
- 실제 임시 Repository 통합 테스트로 재정렬·`reword`·`squash`·`drop`, 다른 branch ref 보존과 충돌 뒤 Abort 원복을 확인한다.

### 6C-1 · Integrate 방향 선택과 checkout 없는 reverse Fast-Forward — 완료

- Integrate 시트에 `Update <현재 branch>`·`Update another branch` 방향 선택기를 두고, 두 방향이 같은 branch 목록·divergence 표시를 공유한다. 보내기 방향(`Update another branch`)은 현재 branch가 이미 포함한 branch를 checkout 없이 현재 HEAD로 fast-forward한다.
- 실행 버튼은 위치 프레임의 `Fast-Forward <이동하는 branch> to <도착 branch>`로 표기하고, 보내기 방향은 dirty working tree에서도 실행할 수 있고 ref 외에는 아무것도 바꾸지 않는다는 캡션을 보여 준다.
- 실행 직전 대상이 현재 HEAD의 ancestor인지 `merge-base --is-ancestor`로 재확인하고, `git fetch . <현재>:<대상>` 실행 뒤 결과 ref가 HEAD와 일치하는지 검증한다. fetch는 non-fast-forward 거부를 종료 코드 0으로 보고하므로 결과 검증이 필수다.
- merge commit·rebase·force는 보내기 방향에 제공하지 않는다. 이동은 대상 branch reflog에 남는다.
- 실제 임시 Repository 통합 테스트로 checkout 없는 갱신과 dirty 파일 보존, diverged 거부와 ref 불변을 확인한다.

### 6C-2 · Worktree에 체크아웃된 branch의 Fast-Forward — 완료

- 보내기 방향 대상이 다른 Worktree에 체크아웃된 경우 ref만 옮기지 않고 해당 Worktree 폴더에서 `merge --ff-only`를 실행해 branch와 그 working tree를 함께 전진시킨다.
- 대상 행과 캡션에 branch picker와 같은 폴더 배지·경로를 표시하고, 실행 직전 그 Worktree가 여전히 대상 branch를 체크아웃 중인지 재확인한다.
- 겹치는 local 수정이나 진행 중인 작업으로 git이 거부하면 덮어쓰지 않고 원인을 표시한다. 해당 Worktree를 열지는 않는다.
- 실제 임시 linked Worktree 통합 테스트로 branch·Worktree 파일 동시 전진과, 체크아웃된 branch에 대한 ref-only 경로의 거부를 확인한다.

### 6C-3 · History ref 배지 Fast-Forward 진입점 — 완료

- History 행의 local branch ref 배지를 우클릭하면, 그 commit이 현재 HEAD에서 도달 가능하고 HEAD가 아니며 현재 branch가 아닐 때 `Fast-Forward <branch> to <현재 branch>`를 제공한다.
- 도달 가능성은 읽어 둔 commit의 parent 관계로 판정하고, 실행은 6C-1·6C-2와 같은 검사·실행 경로를 재사용한다. remote-tracking branch·tag 배지와 detached HEAD에는 제공하지 않는다.
- 같은 동작을 VoiceOver 사용자 지정 액션으로도 제공하며, 키보드로는 같은 명령 모델의 Integrate 시트를 사용한다.

### 6D-1 · checkout 없는 merge commit과 충돌 예측 — 완료

- 보내기 방향의 갈라진 대상에 `Create Merge Commit on <대상>`을 제공하고, `merge-tree --write-tree`로 계산한 in-memory 예측을 divergence 캡션에 먼저 보여 준다. 충돌 파일이 있으면 수·목록을 표시하고 ref-only 경로는 비활성화한다.
- 실행은 예측된 tree로 대상·현재를 부모로 하는 commit을 만들고 `update-ref`를 이전 값 검증과 함께 실행한다. 모든 object 생성이 ref 이동보다 먼저 끝나므로 서명 실패를 포함한 어떤 실패에서도 ref는 바뀌지 않는다.
- `commit-tree`는 `commit.gpgsign`을 스스로 읽지 않을 수 있어 설정을 확인해 `-S`를 명시한다. merge hook이 실행되지 않는다는 점은 실행 전 캡션으로 알린다.
- `update-ref`는 Worktree 체크아웃 보호를 우회하므로 실행 직전에 체크아웃 여부와 divergence를 재확인한다.
- 실제 임시 Repository 통합 테스트로 부모·메시지·dirty 파일 보존, 충돌 예측과 거부, 비divergence 거부, 체크아웃된 대상 거부와 ref 불변을 확인한다.

### 6D-2 · Worktree에서의 merge와 충돌 해결 연결 — 완료

- 갈라진 대상이 다른 Worktree에 체크아웃된 경우 그 폴더에서 `merge --no-ff --no-edit`를 실행한다. 이 경로는 일반 merge라 identity·hook·서명 설정이 그대로 동작한다.
- 실행 직전 그 Worktree가 여전히 대상 branch를 체크아웃 중인지 재확인한다. 충돌하면 `MERGE_HEAD`로 진행 중 상태를 판별해 사용자가 고른다. Worktree를 같은 창의 Workspace로 열어 기존 충돌 해결·Continue·Abort로 잇거나, 즉시 Abort해 복원한다.
- 실제 임시 linked Worktree 통합 테스트로 깨끗한 merge의 branch·파일 동시 갱신과, 충돌 시 해결 가능한 상태·Abort 복원을 확인한다.

### 6D-3 · 임시 Worktree 경유 충돌 해결 — 완료

- 어디에도 체크아웃되지 않은 대상이 충돌을 예측하면 `Merge in Temporary Worktree…`로 임시 linked Worktree를 만들어 merge하고, 충돌 상태의 Worktree를 Recent에 남기지 않고 같은 창의 Workspace로 연다. Workspace 헤더에 Temporary Worktree 표시를 둔다.
- 충돌 없이 끝나면 임시 Worktree를 바로 제거하고, Continue·Abort로 작업이 끝나면 확인을 거쳐 제거한다. 변경이 남아 있으면 `worktree remove`가 거부하므로 강제로 지우지 않는다.
- 임시 추적은 세션 안에서만 유지하며, 앱 재실행 뒤 남은 임시 Worktree는 일반 Worktree로 취급해 기존 branch picker·Worktree 흐름에서 다룬다.
- 실제 임시 Repository 통합 테스트로 생성·체크아웃 branch, dirty 상태의 제거 거부와 정리 뒤 제거를 확인한다.

### 6E-1 · History commit 행 메뉴와 branch·Worktree 정리 — 완료

- History commit 행 우클릭 메뉴는 그 commit에 닿은 모든 local branch를 branch 이름 섹션으로 나눠 보여 주고, 행 배지로 표시되지 않은 숨은 ref도 포함한다. 각 섹션은 Switch 또는 Open Worktree, 가능하면 Fast-Forward를 제공한다.
- 다른 Worktree에 체크아웃된 branch에는 `Remove Worktree…`를 제공한다. 확인 문구는 삭제되는 폴더 경로와 branch·commit 유지를 설명하고, 변경이나 진행 중인 작업이 남아 있으면 git이 거부한다. 주 working tree는 git이 제거를 거부한다.
- 체크아웃되지 않은 branch에는 `Remove Branch…`를 제공한다. 안전한 삭제만 사용해 합쳐지지 않은 branch는 거부하고, 현재 branch와 remote branch 삭제·강제 삭제는 제공하지 않는다.
- 같은 동작을 VoiceOver 사용자 지정 액션으로 제공하고, 성공하면 Repository와 History·ref 표시를 다시 읽는다.
- 같은 정리 동작을 branch 선택기의 행 우클릭 메뉴에서도 같은 확인·규칙으로 제공하고, 실행 뒤 Repository revision을 따라 branch 목록을 다시 읽는다.
- 실제 임시 Repository 통합 테스트로 합쳐진 branch 삭제, 합쳐지지 않은 branch·현재 branch 거부와 ref 유지를 확인한다.

### 6F-1 · 설정의 GPG commit 서명 키 선택 — 완료

- 설정의 `Commit Signing`은 `gpg.openpgp.program`·`gpg.program` 설정과 표준 설치 경로에서 GPG를 찾아 secret key 목록을 키 ID·사용자 정보로 보여 준다.
- 키 선택은 global Git 설정의 `user.signingkey`·`commit.gpgsign`만 바꾸고, `No Signing Key`는 `commit.gpgsign`만 끄고 기존 키 값은 남긴다. 적용 실패는 이전 선택으로 되돌리고 오류를 표시한다.
- `gpg.format=ssh`는 SSH 서명 안내만 하고 바꾸지 않는다. GPG 없음·목록 실패·키 없음을 각각 구분해 안내하며 키 생성·가져오기는 하지 않는다.
- colon 출력 파싱과 설정값(짧은 ID·긴 ID·fingerprint) 매칭은 단위 테스트로 검증한다.

### 6G-1 · commit 서명 상태 표시와 History의 양방향 Fast-Forward — 완료

- History에서 commit을 선택하면 그 commit 하나만 `%G?`로 검증해 상세에 서명 배지를 표시한다. 유효(서명자·키 ID), 신뢰 미확인, 무효, 검증 불가를 구분하고 서명 없는 commit에는 배지를 두지 않는다. 상태 매핑은 단위 테스트, 서명 없는 commit은 임시 Repository 통합 테스트로 확인한다.
- History 행 메뉴는 그 commit이 현재 HEAD의 descendant이고 local branch가 닿아 있으면 현재 branch를 당긴다. 두 방향 모두 위치 프레임의 `Fast-Forward <이동하는 branch> to <도착>` 한 꼴로 표기하고, 실행은 기존 Integrate fast-forward(`merge --ff-only`) 경로를 재사용하며 VoiceOver 액션으로도 제공한다.
- Commit Signing 설정 캡션은 이 화면이 앱 고유 상태 없는 global Git 설정의 뷰이며 탭을 열 때마다 다시 읽는다는 점을 명시한다.

### 6H-1 · remote branch 삭제와 Worktree 연쇄 정리 — 완료

- History의 remote-tracking 배지 우클릭에 `Delete on Remote…`와 `Remove Tracking Reference…`를 제공한다. 원격 삭제는 force 없는 삭제 push 하나만 보내고 기존 remote 작업의 진행·Cancel·Escape를 쓰며, 확인 문구가 다른 사용자 영향·local 유지·보호 branch 거부 가능성을 설명한다. tracking ref 정리는 local ref만 제거하고 Fetch로 되살릴 수 있음을 알린다.
- remote 이름은 configured remote 목록과 가장 긴 접두사 일치로 해석해 `/`가 든 branch 이름도 정확히 나눈다.
- `Remove Worktree…` 확인은 정리 범위를 함께 고른다. Worktree만, branch 안전 삭제까지, Tracking remote branch가 있으면 원격 삭제까지. 각 단계는 기존 규칙과 안전장치를 재사용하고, 뒤 단계가 실패해도 완료된 앞 단계는 되돌리지 않으며 다시 읽은 화면이 실제 상태를 보여 준다.
- 실제 bare remote 통합 테스트로 원격 branch 삭제와 tracking ref 동반 제거, tracking ref 단독 제거의 원격 불변, upstream 조회를 검증한다.

### 7A-1 · Workspace Navigator와 한 줄 문맥 바 — 완료

- Repository Workspace는 `NavigationSplitView`의 Navigator · 목록 · 내용 3열이다. Navigator는 Workspace(Changes·History)와 Recovery(Stashes·Reflog) 목적지, local branch 목록, configured Remote 목록을 보여 준다. 목적지 선택은 기존 ⌘1~⌘4·View 메뉴와 같은 상태를 쓰고, Changes 행에는 변경 파일 수가 붙는다.
- Branches 행은 이 슬라이스에서는 동작 대상만이었고 7A-3에서 선택 대상이 됐다. 현재 branch에는 HEAD, 다른 Worktree에 체크아웃된 branch에는 폴더 표시가 붙고, 이중 클릭 또는 문맥 메뉴로 Switch·Open Worktree·Remove Worktree…·Remove Branch…를 실행한다. 섹션 헤더의 `+`가 New Branch 시트를 열고, Navigator 하단의 필터가 목록을 좁힌다. 목록은 다시 읽는 동안 마지막 결과를 유지한다.
- Remotes 행은 이름과 Fetch URL(도움말)을 보이고, 이 슬라이스에서는 이중 클릭·문맥 메뉴·섹션 헤더 버튼이 기존 Remotes 시트를 열었다(7A-3에서 remote 화면으로 대체). Repository 메뉴에 `Remotes…`(7A-3에서 제거)와 `Integrate…`를 추가했다.
- 헤더는 저장소 이름·경로·segmented control 대신 한 줄 문맥 바다. 현재 branch가 메뉴 버튼이 되어 `Switch To`·`New Branch…`·`Integrate…`를 제공하고, Tracking·ahead/behind·unborn·새로고침 실패·임시 Worktree 표시는 같은 줄에 남는다. 진행 중인 Merge·Rebase 배너는 그대로다.
- 툴바에서 Remotes·Integrate를 뺐다. 왼쪽은 Navigator 토글과 Library, 오른쪽은 Fetch·Pull·Push/Publish·Refresh다. 자동 사이드바 토글은 제거하고 View 메뉴의 `Hide/Show Navigator`(⌃⌘S)와 툴바 버튼이 같은 상태를 바꾼다.
- 창 폭이 Navigator 이상 폭 220·Changes 목록 320·diff 400과 분할선을 합한 948pt보다 좁으면 Navigator를 먼저 접고, 다시 넓어지면 편다. 사용자가 좁은 창에서 직접 연 Navigator는 다음 크기 변경까지 유지한다. detail 열에 명시적 ideal 폭을 두어 분할 뷰가 diff의 자연 폭으로 창을 넘치지 않게 했다.
- 접근성 API로 툴바 배치(960·720pt에서 동기화 세 동사 직접 노출, 960에서 오버플로 없음), Navigator 행과 선택, ⌘1·⌘2, ⌃⌘S, 자동 접힘·복원을 확인했고 `xcodebuild test` 107개가 통과했다.

### 7A-2 · 진행 표시 모델과 동기화 잠금 분리 — 완료

- 원격 작업은 화면 가운데 진행 박스 대신 세 곳에서 보인다. 누른 툴바 버튼(Fetch·Pull·Push/Publish)의 아이콘이 진행 표시로 바뀌고, 창 제목 아래 subtitle에 작업 이름이 뜨며, 우하단 캡슐이 같은 이름과 Cancel(Escape)을 보여 준다. 자동 Fetch도 같은 캡슐을 쓴다.
- 잠금을 원격/로컬로 나눴다. Fetch·Push·Publish·remote branch 삭제는 index와 working tree를 건드리지 않으므로 `isLoading`을 올리지 않고, `isSyncing`으로 동기화 세 동사와 branch 전환·생성·Integrate만 막는다. Stage·Unstage·Commit·Discard·조회·Refresh는 계속된다. Pull만 working tree를 쓰므로 기존처럼 전역 잠금을 쓴다.
- 동시 실행의 일관성은 inspection generation으로 지킨다. 원격 작업이 끝났을 때 그 사이 다른 읽기가 없었으면 결과 스냅샷을 그대로 적용하고, 있었으면 한 번 더 읽어 두 결과를 함께 반영한다. 로컬 작업이 아직 진행 중이면 그 작업의 읽기에 맡긴다. 작업 식별자로 정리 시점을 판단해 뒤늦게 끝난 작업이 새 작업의 상태를 지우지 않는다.
- 사용자가 시작한 원격 작업은 실행 중인 자동 Fetch를 취소하고 이어받는다. 자동 Fetch는 어떤 버튼도 잠그지 않는다.
- 성공하면 캡슐이 결과를 2.5초 보이고 사라진다. Fetch는 `Fetched (from <remote>)`, Pull은 작업 전 behind 수로 `Pulled N commits`, Push는 ahead 수로 `Pushed N commits`, Publish는 목적지, remote branch 삭제는 대상 ref다. 실패는 기존대로 작업 이름을 제목으로 한 alert다.
- 짧은 로컬 작업은 300ms가 지나면 같은 subtitle과 캡슐(Cancel 없음)로 `Updating`·`Reading Repository…`를 보여 준다.
- 응답 없는 원격 주소를 가진 임시 Repository로 실행 중 상태를 접근성 API로 확인했다. 제목 subtitle, Fetch 아이콘 교체와 Fetch·Pull·Push 비활성, Refresh·Stage·Discard 활성, 캡슐의 Cancel과 취소 뒤 복귀, 로컬 bare remote로 `Fetched` 결과 캡슐 표시와 소멸을 확인했고 `xcodebuild test`가 통과했다.

### 7A-3 · Navigator 선택 문맥 — 완료

- Navigator 선택은 목적지(Changes·History·Stashes·Reflog) 또는 Git 객체(branch·remote·tag) 하나다. 목적지는 종전처럼 `@SceneStorage`와 ⌘1~⌘4·View 메뉴를 쓰고, 객체가 선택된 동안 View 메뉴의 목적지 항목에는 체크가 없다. 저장소를 바꾸면 이전 저장소의 객체 선택을 버리고 기억한 목적지로 돌아가고, 선택한 branch·remote·tag가 다시 읽은 목록에서 사라지면 History로 돌아간다.
- branch·tag를 고르면 History 화면이 그 ref 하나의 log로 좁혀진다. `RepositoryHistoryRequest`에 fully qualified ref(`refs/heads/…`·`refs/tags/…`)가 붙어 같은 이름의 branch와 tag가 서로를 가리키지 않고, 선택이 바뀌면 그 ref의 끝 commit이 먼저 선택된다. 헤더는 ref 이름과 종류(Local branch·HEAD·Worktree 위치·Tag)를 보이고, branch 화면에는 `Switch` 또는 `Open Worktree`와 그 branch를 미리 고른 `Integrate…`가, tag 화면에는 그 tag에서 시작하는 `New Branch…`가 산다. Stashes·Reflog 요청은 ref와 무관하게 유지해 branch를 고를 때 다시 읽지 않는다.
- remote를 고르면 본문이 remote 화면으로 바뀐다. 왼쪽은 그 remote의 remote-tracking branch 목록(문맥 메뉴로 `Delete on Remote…`·`Remove Tracking Reference…`, History 행과 같은 확인 문구를 공용 modifier로 공유), 오른쪽은 이름·Fetch URL·Push URL과 `Fetch`·`Fetch & Prune`·`Test Connection`(진행·Reachable·Cancel Test)·`Edit…`·`Remove…`다. Remotes 시트와 Repository 메뉴의 `Remotes…`는 제거했고, Navigator remote 행의 문맥 메뉴가 `Fetch`·`Fetch & Prune`을 준다.
- Navigator에 Tags 섹션을 추가했다. Inspector가 `for-each-ref`로 tag(최근 생성 순)와 remote별 remote-tracking branch를 읽되, `refname:short`는 branch와 같은 이름의 tag를 `tags/<name>`으로, remote의 `HEAD` 별칭을 remote 이름으로 바꿔 내놓으므로 전체 refname에서 접두어를 직접 뗀다. Stashes 행에는 개수 배지가 붙고, Navigator 필터는 branch·remote·tag 모두에 적용된다.
- Navigator branch 행의 문맥 메뉴에 `Integrate…`를 추가했고 Integrate 시트는 그 branch를 미리 고른 채 열린다. 현재 branch 행은 메뉴가 없다.
- 임시 Repository(branch 2·remote 1·tag 2)에서 접근성 API로 branch 화면의 헤더·Switch·Integrate…와 2개 commit, remote 화면의 URL·버튼·remote branch 행, tag 화면의 `New Branch…`와 도달 commit 수, ⌘2로 History 복귀, 우클릭 메뉴(branch: Switch·Integrate…·Remove Branch…, remote: Fetch·Fetch & Prune, 현재 branch: 없음), View 메뉴 체크 없음, Integrate 시트의 미리 선택을 확인했다. Inspector 테스트가 같은 이름의 branch·tag 분리와 `origin/HEAD` 제외를 검증한다.

### 7A-4 · 재질·접근성 응답, Appearance 설정, Split diff — 완료

- 테마는 하나이고 `GallaeTheme.resolve(response:compactRows:)`가 Material Response와 밀도에 맞는 Semantic 값을 돌려준다. 응답은 `GallaeMaterialResponse.resolve`가 시스템의 투명도 줄이기·대비 증가와 설정의 Translucent 값으로 정하며(대비 증가 > 투명도 줄이기 또는 Translucent 끔 > 기본), `AppView` 루트가 `accessibilityReduceTransparency`·`colorSchemeContrast`·`@AppStorage`를 읽어 한 번 해석하고 `gallaeTheme` 환경으로 내려보낸다.
- Standard는 시스템 재질 그대로다. Reduced Transparency는 Navigator 목록의 배경을 숨기고 창 배경색으로 칠하며 창 툴바 배경을 `visible`로 둔다. Increased Contrast는 그 위에 배지·diff 추가/삭제/hunk 배경 농도를 올리고, diff 글자를 11pt로 줄이고, 추가·삭제 행 왼쪽에 3pt 컬러 바를 붙이고, diff 메타데이터를 secondary 대신 primary로 그린다. 선택 색과 구분선은 시스템 컨트롤이 대비 증가에 스스로 응답하므로 따로 그리지 않는다.
- 설정에 Appearance 탭을 추가했다. Appearance(System·Light·Dark)는 `NSApp.appearance`로 모든 창에 적용되고 실행 시 저장값을 복원한다. Translucent Sidebar and Toolbar(기본 켬)는 시스템 투명도 줄이기가 켜져 있으면 비활성이며 설명이 그 이유를 말한다. Compact Rows(기본 끔)는 Changes·History·Stashes·Reflog 행의 세로 여백을 7에서 3으로 줄인다. 테마 선택 UI는 없고, 설정 하단 문구가 대비 증가는 시스템 설정을 따른다고 알린다.
- diff 헤더(작업 트리 diff, commit·stash patch)에 Unified·Split segmented 토글을 두고 마지막 선택을 `@AppStorage`로 기억한다. Split은 `RepositoryDiffSplitRow.rows`가 문맥 행을 양쪽에, 삭제 묶음과 뒤따르는 추가 묶음을 순서대로 짝지어 old·new 두 열로 그리고, 짝이 없는 쪽은 빈 셀이다. metadata·hunk 행과 Stage/Unstage Hunk 버튼은 전체 폭이다. Split은 세로 스크롤만 쓰고 긴 줄을 줄바꿈하며, Unified는 종전처럼 가로 스크롤을 유지한다. 두 렌더러는 `RepositoryDiffLinesView` 하나를 공유한다.
- 접근성 API로 diff 헤더의 Unified·Split 라디오, Split에서 추가 행이 오른쪽 열(패널 폭의 절반 위치)에 놓이고 hunk 헤더가 전체 폭인 것, 설정 Appearance 탭의 세 라디오와 두 토글, Compact Rows 켜고 끌 때 History 행 높이 63→55→63, Translucent 토글 끄고 켠 뒤 Navigator 유지, Dark→System 전환을 확인했다. 시스템 재질과 불투명 전환의 실제 모습은 화면 캡처 권한이 없어 눈으로 확인하지 못했다. 단위 테스트가 응답 해석과 Split 짝짓기(삭제 2·추가 1, 추가 뒤 삭제, 고유 id)를 검증한다.

### 7A-5 · 좁은 창의 Navigator — 완료

- 창이 948pt보다 좁으면 사이드바 열은 열리지 않고 창도 커지지 않는다. 대신 `GallaeAppearanceSettings.NarrowNavigator`(floatingPanel·toolbarMenu·locationMenu)가 접힌 Navigator에 닿는 길을 정하며, Workspace의 세 지점(툴바 버튼, 문맥 바, detail 오버레이)만 이 값으로 switch 한다. 새 안은 case 하나와 뷰 하나로 추가한다.
- Floating Navigator(기본)는 툴바 버튼과 ⌃⌘S가 같은 `RepositoryNavigatorView`를 detail 위에 220pt 패널로 띄운다. 재질 응답을 따르고(시스템 재질 또는 불투명 창 배경), 항목 선택·바깥 클릭·Escape·창이 948pt 이상으로 넓어질 때·설정 변경·저장소 변경에 닫힌다.
- Toolbar Menu는 툴바 버튼이 메뉴가 된다. Workspace·Recovery 목적지(개수는 제목에 괄호로), Branches 하위 메뉴, Remotes, Tags를 `Toggle`로 두어 현재 위치에 체크가 붙는다.
- Location Menu는 문맥 바의 branch 메뉴 뒤에 `›`와 위치 칸을 둔다. 위치 칸은 `RepositoryNavigatorSelection.locationTitle`(History, feature · Local branch, origin · Remote, v0.1 · Tag)을 읽어 주고, 같은 메뉴에서 branch만 뺀 항목을 연다. 툴바 버튼은 비활성이고 도움말이 이유를 말한다.
- branch 메뉴에 Show History ▸를 추가해 어느 폭에서든 다른 branch의 History 화면으로 갈 수 있다. View 메뉴의 Navigator 항목은 `NavigatorToggleCommand`(제목·활성·동작)를 Workspace가 FocusedValue로 내려보내 폭과 설정에 맞게 바뀐다.
- 임시 Repository로 900pt 창에서 접근성 API로 확인했다. 세 방식 모두 창 폭이 900으로 유지되고, 오버레이는 열림·Reflog 선택 뒤 자동 닫힘·버튼 재클릭 닫힘, 툴바 메뉴와 위치 메뉴는 항목(Workspace·Changes (1)·History ✓·Recovery·Stashes·Reflog·(Branches)·Remotes·origin·Tags·v0.2·v0.1)과 Reflog 선택 뒤 헤더 전환, 위치 라벨이 History → Reflog → v0.1 · Tag로 바뀌는 것을 확인했다. Location Menu에서 툴바 버튼이 비활성인 것도 확인했다. branch 메뉴의 Show History ▸는 접근성 API가 borderless 메뉴를 열지 못해 눈으로 확인해야 한다. 테스트가 위치 라벨과 설정값 폴백을 검증한다.

### 7A-6 · detail 열 최소폭 제거와 SwiftUI 분할 — 완료

- 원인은 macOS `NavigationSplitView`가 detail 열의 최소폭에 사이드바 폭을 두 번 세는 것이다. detail에 최소폭만 주면 사이드바를 열 때 창이 커지고, 최소·ideal 폭을 함께 주면 사이드바가 (창 폭 − detail 최소폭)의 절반을 넘는 만큼 오른쪽이 빈다. Gallae 코드가 없는 40줄 앱에서 그대로 재현했다(1456pt 창, 최소폭 721: 사이드바 400→33pt, 500→133pt 빈 띠. 최소폭 201: 600까지 0).
- detail 열에서 최소·ideal 폭을 없앴다. 여섯 곳의 `HSplitView`(Changes, History, Remote, Stashes, Reflog, commit 파일 목록)는 `ResizableHSplit`로 바꿨다. `GeometryReader` 기반이라 최소폭이 없고, 좁아지면 앞 pane이 자기 최소폭까지 먼저 양보하고 그 아래서는 둘이 최소폭 비율로 줄어든다. 구분선 드래그 폭은 `@SceneStorage`에 남는다.
- Navigator 접힘은 창 폭 변화에서만 일어난다. 구분선 드래그 중 열을 뒤집던 `foldOverwideNavigator`는 뺐다. 드래그 중 AppKit 분할 뷰와 상태가 어긋나 사이드바 내용이 왼쪽으로 밀리고 detail이 오른쪽으로 넘치던 원인이었다. 저장된 사이드바 폭을 ideal로 쓸 때는 320으로 캡한다.
- 사이드바 최대폭 320은 `navigationSplitViewColumnWidth(max:)`가 마우스 드래그와 AppKit이 복원한 프레임에는 적용하지 않는다. SwiftUI는 NSSplitViewItem의 maximumThickness를 비워 두고 갱신 때마다 비운다. 그래서 `SidebarWidthClamp`(사이드바 배경의 NSView)가 그 값을 KVO로 지켜보다 비워질 때마다 320으로 되돌려 두고(AppKit 분할 뷰 컨트롤러가 드래그를 거기서 멈춘다), 시작 시 복원된 넓은 프레임은 붙는 순간 320으로 되돌린다. 분할 뷰의 delegate를 바꾸는 길은 NSSplitViewController가 assertion으로 막는다. 복원 폭 600 → 320, 드래그 +500은 드래그 중에도 320, −100은 220, 900pt 창에서 접힘과 1456 복귀를 확인했다.
- 접근성 API로 확인했다. 1456pt 창에서 사이드바 300·500·554 모두 diff 오른쪽 끝이 창 끝과 같고, 1000·800·720으로 줄이면 창이 그 폭을 지키며 사이드바가 접히고 1456에서 돌아온다. 테스트 112개가 통과하고 분할 폭 규칙 테스트를 더했다. 안쪽 구분선 드래그는 합성 드래그가 먹지 않아 눈으로 확인한다.

### 7A-7 · 다섯 과업 판정과 Fetch 진행 제목 — 완료

- PRODUCT.md의 판정 방법대로 다섯 과업을 1180pt와 720pt에서 접근성 트리로 확인하고 표를 남겼다. History 맨 위의 Working Tree 행은 두지 않는다. 720pt에서 dirty 개수 하나가 가려지는 것은 Floating Navigator가 화면을 옮기지 않고 보여 주고, 행은 History 화면에서만 그것을 돕는 대신 HEAD commit을 둘째 행으로 밀어 잘못 고를 위험을 더한다.
- 720pt 툴바는 제목이 짧은 저장소에서 Navigator·Library·Fetch·Pull·Publish·↻가 모두 보이고 오버플로가 없었다.
- remote를 정하지 않은 Fetch의 진행 제목을 "Reading Fetch Remotes…"에서 "Fetching Remote Changes…"로, Prune은 "Fetching & Pruning…"으로 바꿨다. Pull의 "Pulling Remote Changes…"와 같은 꼴이다.

### 7A-8 · 시안 마무리와 문맥 바 — 완료

- 커밋 칸은 staged가 없으면 한 줄 바(Commit … · Stage All)로 접히고, staged가 생기거나 Commit …을 누르면 펼쳐진다. 커밋이 끝나면 다시 접힌다. Stage All은 conflict가 아닌 unstaged·untracked 전부를 올리며 펼친 상태의 "N staged" 옆에도 있다.
- 문맥 바에 둘을 더했다. Tracking 뒤의 working tree 표시("4 changes · 1 staged", 깨끗하면 숨김)는 누르면 Changes로 가고, 오른쪽 끝의 "Last fetch just now · Auto"는 이 세션에서 Fetch·자동 Fetch·Pull이 성공한 시각을 1분 단위로 갱신한다. 시각은 저장하지 않는다.
- 시스템의 항상 보이는 스크롤바(마우스 연결 시 자동)에서 목록 헤더의 오른쪽 내용이 행보다 스크롤바 폭만큼 바깥에 있던 것을 맞췄다. 여섯 목록 헤더가 `listHeaderInset`으로 그 폭만큼 들어가고, 목록은 `legacyScrollerAware`로 스크롤바를 항상 보여 짧은 목록에서도 같은 자리를 지킨다. 오버레이 스크롤바에서는 둘 다 0이다.
- 접근성 트리로 확인했다. staged 0에서 "Commit, nothing staged"와 Stage All, Stage All 뒤 "4 staged"와 펼쳐진 칸, 문맥 바 "4 changes" → "4 changes · 4 staged", Fetch 뒤 "Last fetch just now".

### 7B · Navigator의 두 축 — 완료

- 선택 모델을 둘로 나눴다. 화면 축은 `RepositoryWorkspaceSection`(`@SceneStorage`, ⌘1~⌘4와 같은 값), 범위 축은 `RepositoryHistoryScope`(branch·remote·remoteBranch·tag). 범위를 고르면 화면이 History가 되고 `AppModel.historyReference`가 그 범위의 ref가 된다. 화면을 고르면(화면 목록, ⌘1~⌘4, 메뉴, 문맥 바) 범위가 풀려 두 선택이 서로 다른 것을 가리키지 않는다. remote 범위는 `--remotes=<name>/`로 그 remote의 branch 전부를 읽는다. 좁은 창의 위치 라벨은 `RepositoryNavigatorLocation(screen:scope:)`이 만든다.
- Navigator는 위의 화면 목록(네 행짜리 스택, 포커스를 스스로 받아 강조색·회색을 가른다)과 아래의 범위 목록(`List(selection:)`)으로 나뉜다. remote 행은 DisclosureGroup으로 열려 remote branch가 범위가 되고, 우클릭 메뉴에 Fetch·Fetch & Prune·Edit…·Remove…가, remote branch 행에는 Delete on Remote…·Remove Tracking Reference…가 있다. HEAD branch는 굵은 글씨다. 두 번 클릭 전환은 화면을 바꾸지 않는다.
- Remote 화면(`RepositoryRemoteView`)은 없앴다. History 헤더가 remote 범위에서 Fetch·Fetch & Prune·Edit…를, remote branch·tag 범위에서 New Branch…를 보여 준다. `EditRemoteSheet`가 Test Connection(아래 왼쪽)과 Remove…(오른쪽 위, 확인 대화상자)를 품는다.
- 테스트는 위치 라벨과 범위 ref를 검증한다.

### 7C-1 · 줄 단위 staging의 부분 패치 — 완료

- `RepositoryDiff.Section.partialHunk(id:keeping:direction:)`이 hunk 하나를 고른 추가·삭제 줄만 남긴 `Hunk`로 줄인다. `.apply`(stage, index는 아직 old 쪽)는 안 고른 삭제를 문맥으로 바꾸고 안 고른 추가를 뺀다. `.revert`(unstage·discard, new 쪽에 거꾸로 적용)는 반대다. 문맥은 그대로, 헤더의 줄 수는 다시 세고 시작 줄은 유지하며, `\ No newline at end of file` 표식은 바로 앞 줄과 운명을 같이한다. 고른 줄이 없으면 nil.
- 기존 `inspector.stage/unstage(hunk…)`(`git apply --cached [--reverse]`)가 그대로 부분 패치를 받는다. 새 git 경로는 없다.
- 테스트 둘. 손으로 만든 hunk로 두 방향의 패치 문자열(문맥 전환·드롭·표식·헤더 수)을 검증하고, 임시 저장소에서 한 hunk의 두 수정 중 하나만 stage 했다가 되돌리는 왕복을 git으로 검증한다.

### 7C-2 · Unified diff의 거터 체크박스 — 완료

- Changes 화면의 Working Tree·Staged 섹션이 Unified 배치일 때 추가·삭제 줄마다 거터 체크박스가 붙는다. hunk 헤더의 체크박스는 그 hunk의 줄 전부를 켜고 끈다. Shift 클릭은 마지막으로 만진 줄과의 사이를 한꺼번에 켜거나 끈다. 문맥 줄은 자리만 지켜 줄 번호가 흔들리지 않는다.
- hunk 버튼이 체크박스를 흡수한다. 아무것도 안 골랐으면 지금처럼 "Stage Hunk"·"Unstage Hunk"로 hunk 전체, 골랐으면 "Stage 2 Lines"처럼 고른 줄만 `partialHunk`로 만든 패치를 기존 `updateHunk` 경로로 적용한다. Split 배치는 체크박스 없이 hunk 전체를 유지한다. diff가 바뀌면 고른 줄은 비워진다.
- 접근성 이름은 "Choose deleted line 2"·"Choose added line 2"·"Choose every line in this hunk". 시험 저장소에서 한 hunk의 두 수정 중 line 2의 삭제·추가만 골라 "Stage 2 Lines"를 눌러 index에 그 둘만, working tree에 나머지가 남는 것을 git으로 확인했다.
- 남은 것: 줄 단위 discard(working tree에 `--reverse`, 확인 대화상자), Split 배치의 체크박스, untracked 파일(intent-to-add).

### 7C-3 · 줄 단위 discard, Split 체크박스, untracked 줄 단위 stage — 완료

- Working Tree 섹션의 hunk 헤더에 두 번째 버튼 "Discard Hunk…"가 붙고, 줄을 골랐으면 "Discard 2 Lines…"가 된다. 누르면 확인 대화상자를 거쳐 `inspector.discard(hunk…)`가 `git apply --reverse`로 working tree만 고쳐 쓴다. index는 건드리지 않는다.
- Split 배치도 거터 체크박스를 갖는다. 왼쪽(삭제)과 오른쪽(추가) 각자 자기 체크박스이고 hunk 헤더와 버튼은 Unified와 같다.
- untracked 파일은 diff가 새 파일 패치라 부분 패치를 `git apply --cached`에 그대로 넣으면 고른 줄만으로 index 항목이 생긴다(status `AM`). intent-to-add 없이 된다. `canStageSelectedHunks`가 untracked를 포함하고, `updateIndexSynchronously`가 `.untracked` 범위의 정방향 적용을 받는다.
- 테스트 둘을 더했다. untracked 세 줄 중 한 줄만 stage 하면 staged는 `added`·unstaged는 `modified`이고 index diff에 그 줄만 있는 것, 두 수정 중 하나만 discard 하면 디스크 파일에 그 수정만 사라지는 것.

## 각 단계의 검증

모든 단계는 실행 가능한 앱과 `xcodebuild test` 성공으로 끝낸다. Git parser와 탐색처럼 분기나 반복이 있는 로직은 임시 디렉터리와 임시 Repository를 사용한 작은 통합 테스트를 남긴다. 경쟁 앱의 코드, 에셋, 문구, 정확한 수치와 동작을 fixture나 기준값으로 사용하지 않는다.

## 아직 남은 결정

- 조직 팀의 canonical App ID 등록 시점
- 공개 배포에 사용할 Developer ID Application 인증서와 배포 채널
