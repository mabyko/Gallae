# Gallae 구현 계획

> 상태: 1 · Open & Inspect 완료 · 2 · Commit 완료 · 3 · History 완료 · 4 · Sync 완료 · 5 · Recovery 완료 · 6 · Advanced 완료 · 2026-09-01
> 현재 범위: 6D checkout 없는 merge commit·충돌 예측·임시 Worktree 완료 · 다음 범위 결정 대기

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

- `AppModel`은 화면 전환, 선택과 비동기 작업 취소만 맡는다.
- `RepositoryInspector`는 Git 실행과 출력을 숨기고 불변 snapshot과 진행 중인 Merge·Rebase 상태·Continue·Abort, Interactive Rebase 계획·실행, file diff, commit history/patch와 Revert, Stash 목록·파일·patch·생성·적용·삭제, HEAD Reflog, local branch 목록·생성·전환·Merge·Rebase, configured Remote와 Fetch/Pull/Push 결과를 돌려준다.
- `RepositoryScanner`는 허용된 Library Folder 안에서만 후보를 찾고 결과를 점진적으로 전달한다.
- `LibraryStore`는 URL bookmark, 최근 Repository, 마지막 Workspace와 자동 Fetch 선택을 저장한다.
- 구현체가 하나뿐인 protocol, DI container, coordinator, database layer는 만들지 않는다.

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

## 각 단계의 검증

모든 단계는 실행 가능한 앱과 `xcodebuild test` 성공으로 끝낸다. Git parser와 탐색처럼 분기나 반복이 있는 로직은 임시 디렉터리와 임시 Repository를 사용한 작은 통합 테스트를 남긴다. 경쟁 앱의 코드, 에셋, 문구, 정확한 수치와 동작을 fixture나 기준값으로 사용하지 않는다.

## 아직 남은 결정

- 조직 팀의 canonical App ID 등록 시점
- 공개 배포에 사용할 Developer ID Application 인증서와 배포 채널
