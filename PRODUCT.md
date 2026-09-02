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
- Recent에서는 ⌘A·⌘클릭·Shift 클릭으로 여러 항목을 선택해 디스크의 Repository를 바꾸지 않고 목록에서 함께 제거할 수 있다.
- Repository를 선택하면 요약을 확인할 수 있고, 열면 같은 메인 윈도우가 그 저장소의 **Repository Workspace**로 전환된다.
- 경로를 전달받아 실행된 경우에는 해당 Repository를 바로 열고, 복원할 작업공간이 없으면 Repository Library를 보여 준다.
- 설정(⌘,)의 Command Line Tool에서 `gallae` 명령을 설치하고, Help 메뉴의 `Install Command Line Tool…`은 이 설정을 연다. `gallae [path]`는 같은 경로 전달을 터미널에서 실행하고 경로 기본값은 현재 디렉터리이며, Release 앱이 없으면 Dev 빌드를 연다. 설치는 PATH의 쓰기 가능한 표준 bin 디렉터리에 스크립트를 복사하며 관리자 권한을 요구하지 않는다.

## UX 원칙

### 정보 구조

- 화면마다 필요한 역할만 둔다. Repository Library는 **Library Folder 탐색 · Repository 목록 · 선택 요약**의 세 역할로 나눈다.
- 작업 트리가 깨끗한 Repository를 열면 빈 Changes 대신 History를 먼저 보여 준다.
- Repository Workspace는 **Navigator · 목록 · 내용**의 3열이다. Navigator에는 목적지(Changes·History·Stashes·Reflog)와 Git 객체(Branches·Remotes·Tags)만 두고, 아직 구현하지 않은 객체의 빈 섹션은 만들지 않는다. 좁은 창에서는 Navigator부터 접는다. 이 구조는 [디자인 시안 3·4·5](#디자인-시안-345)에서 결정했고, 구현은 그 절의 슬라이스 순서를 따른다.
- 현재 브랜치와 추적 대상 remote branch 대비 ahead/behind 상태는 모든 작업 공간의 상단에서 항상 확인할 수 있어야 한다.
- 메인 윈도우 제목은 Active Repository 이름을 표시하고, macOS 제목 표시줄의 프록시 아이콘으로 Repository 경로를 노출한다.
- Git의 branch upstream 관계는 사용자 화면에서 `Tracking`으로 표시한다. `upstream`은 내부 Git 용어 또는 실제 remote 이름일 때만 그대로 쓴다. Tracking 표기는 remote branch 이름이 현재 branch와 같으면 remote 이름만 보여 줘 긴 이름의 중복 잘림을 줄이고, 전체 이름은 도움말과 VoiceOver로 유지한다.
- 선택은 곧 문맥이다. 선택한 저장소, 파일, 커밋이 바뀌면 나머지 영역이 예측 가능하게 갱신되어야 한다.
- 위험한 동작은 일반 탐색과 시각적으로 구분하고, 되돌릴 수 없는 경우에만 확인을 요구한다.

### 시각 언어

- 디자인 다이얼: 밀도 9/10, 변주 3/10, 모션 2/10.
- 시스템 글꼴, 시스템 색상, SF Symbols와 표준 macOS 컨트롤을 우선한다.
- 사이드바와 툴바는 시스템 재질(반투명)을 그대로 쓰고, 목록·diff 같은 콘텐츠 패널은 불투명하게 둔다. 테마는 하나이며 macOS의 투명도 줄이기와 대비 증가 설정에 응답한다. 규칙은 [Gallae UI 및 테마 시스템](DESIGN_SYSTEM.md)이 관리한다.
- 장식보다 정렬, 간격, 타이포그래피 위계로 밀도를 다룬다.
- 상태 색에는 항상 `수정됨`, `추가됨`, `추적 안 됨`, `충돌` 같은 텍스트나 기호를 함께 둔다.
- 라이트/다크 모드, 충분한 대비, 명확한 키보드 포커스, Reduce Motion을 기본 요구사항으로 둔다.
- 선택 전환은 짧고 미묘하게 처리하며, 작업 결과를 기다리게 하는 장식 애니메이션은 넣지 않는다.

### 조작

- 메뉴와 화면 버튼은 같은 명령 모델을 공유한다.
- 주요 명령은 macOS 메뉴에서 발견할 수 있고 안정적인 단축키를 제공한다. View 메뉴는 ⌘1–⌘4로 Changes·History·Stashes·Reflog를 전환하고 ⇧⌘L로 Repository Library로 돌아간다. Repository 메뉴는 Fetch(⌥⌘F), Fetch & Prune, Pull(⌥⌘↓), Push 또는 Publish(⌥⌘↑), Refresh Repository(⌘R)를 제공한다.
- 진행 표시는 작업 공간을 가리지 않는다. 원격 작업은 누른 툴바 버튼의 아이콘을 진행 표시로 바꾸고, 창 제목 아래 subtitle에 작업 이름을, 우하단 캡슐에 Cancel을 둔다. 잠기는 것은 동기화 묶음(Fetch·Pull·Push)과 branch 전환뿐이며 Stage·Commit·조회는 계속된다. 완료는 캡슐이 결과를 잠깐 보이고 사라지고, 실패는 실패한 작업을 제목으로 한 alert로 알린다. 짧은 로컬 작업은 일정 시간 이상 걸릴 때만 같은 방식으로 표시하며, 자동 Fetch도 이 규칙을 따르되 툴바를 잠그지 않는다.
- 선택 전환과 새로고침은 이전에 읽은 내용을 유지한 채 제자리에서 갱신하고, 로드가 길어질 때만 진행 표시로 바꾼다.
- 오류 알림은 실패한 작업을 제목으로 밝힌다.
- 툴바 버튼은 hover 도움말로 이름과 동작, 있으면 단축키를 설명한다.
- 툴바는 탐색(Library·Navigator 토글) · 동기화(Fetch·Pull·Push 또는 Publish) · 새로고침 묶음만 둔다. Pull·Push에는 behind·ahead 수를 붙이고 동기화 동작은 아이콘과 이름을 함께 표시한다. Remotes는 Navigator의 객체이고 Integrate는 branch 문맥 메뉴와 Repository 메뉴에 둔다. 720pt 최소 폭에서 동기화 세 동사가 직접 보이는 것이 완료 조건이다.
- diff의 Unified·Split은 diff 헤더의 보기 토글이며 마지막 선택을 기억한다. 설정 항목이 아니다.
- 커밋 작성 영역은 staged 변경이 없으면 한 줄 바로 접히고 생기면 펼쳐진다. 사용자가 고르는 옵션이 아니다.
- 설정에는 화면 밀도(Compact Rows)와 반투명 재질 사용 여부만 둔다. 테마 선택은 두지 않는다.
- 시간은 목록에서 단일 단위 상대 표기로, 상세에서 절대 시각으로 보여 준다.
- 상단의 현재 브랜치 버튼 한 번으로 검색 가능한 브랜치 목록을 열며, Navigator가 있는 화면에서는 전체 목록과 현재 항목도 함께 표시한다.
- 커밋 작성은 문맥을 잃는 모달보다 현재 변경사항과 함께 보이는 인라인 영역을 우선한다.
- 작은 창에서는 보조 영역부터 접고, 선택 항목과 핵심 동작은 남긴다.

## Fast-forward 표기 프레임

앱 전체가 하나의 표기 프레임만 쓴다. 두 프레임을 혼용하면 같은 동작이 화면마다 다른 전치사로 읽히는 문제가 실제로 있었다. 어느 프레임을 고르든 전면 적용이 조건이다.

**현재 결정: 위치 프레임.** git 문서와 reflog의 어순으로, ref가 이동한다는 사실을 그대로 표기한다.

- 규칙: `Fast-Forward <이동하는 branch> to <도착 branch>` — 첫 단어가 움직이는 ref, `to` 뒤가 도착 위치.
- 같은 동작은 어느 화면(Integrate 시트, History 행 메뉴)에서든 글자까지 같은 라벨을 쓴다.
- Integrate 방향 선택기는 전치사를 쓰지 않는 `Update <현재 branch>` · `Update another branch`로 갱신되는 쪽만 말한다.

**검토한 대안: 흐름 프레임.** `merge X into Y` · `pull from`처럼 변경의 흐름을 표기하는 GUI 관례다. `to`는 변경을 받는 branch, `from`은 보내는 branch가 된다. 이 프레임으로 전환하려면 다음을 한 변경에서 함께 바꾼다.

1. History 행 메뉴 두 항목: `Fast-Forward <이동> to <도착>` → `Fast-Forward <갱신되는 branch> from <소스 branch>`
2. Integrate 보내기 방향 버튼: `Fast-Forward <이동> to <도착>` → 방향 선택기와 한 문장을 이루는 `Fast-Forward to <대상>`
3. 방향 선택기: `Update <현재>` · `Update another branch` → `Into <현재>` · `From <현재>`
4. 이 절과 Advanced 아홉·열한 번째 수직 슬라이스, 구현 계획의 해당 완료 조건 서술

## 기능 로드맵

| 단계 | 사용자 결과 | 포함 기능 |
| --- | --- | --- |
| 1. Open & Inspect | Repository를 찾고 작업 트리를 빠르게 이해한다 | Repository 직접 열기, Library Folder 탐색, 마지막 Workspace 복원, 현재 브랜치, staged/unstaged/untracked/conflicted 목록, 텍스트 diff |
| 2. Commit | 검토한 변경만 안전하게 기록한다 | 파일·hunk 스테이징, 커밋, amend, 안전한 discard |
| 3. History | 변경의 맥락과 브랜치 관계를 읽는다 | 커밋 목록/그래프, 커밋 상세와 diff, 검색·필터, 브랜치 이동·생성 |
| 4. Sync | 기존 인증 환경으로 원격과 동기화한다 | fetch, pull, push, 진행·오류 표시 |
| 5. Recovery | 실수와 분기 작업에서 복구한다 | stash, revert, reset, merge, rebase, reflog 기반 복구 보조 |
| 6. Advanced | 복잡한 저장소도 앱 안에서 다룬다 | 충돌 해결, interactive rebase, worktree 생성·관리, submodule, LFS, 서명, 이미지 diff, 서비스 연동 |

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

## Commit 첫 수직 슬라이스

검토한 파일 전체를 Stage하거나 Unstage하고, staged 변경이 있으면 한 줄 제목으로 일반 commit을 만든다. Changes의 Status와 Folders 목록에서는 ⌘클릭·Shift 클릭으로 여러 파일을 선택하고 우클릭 메뉴에서 선택한 파일을 함께 Stage하거나 Unstage할 수 있다. Status의 ⌘A는 현재 선택 파일이 속한 그룹만, Folders의 ⌘A는 모든 변경 파일을 선택한다. diff는 마지막으로 선택한 한 파일을 계속 보여 준다. Stage/Unstage는 working tree 파일 내용을 바꾸지 않으며 충돌 파일에는 제공하지 않는다. Commit은 현재 index만 기록하고 unstaged 변경을 자동으로 포함하지 않으며, 성공한 Repository 상태와 diff를 같은 Workspace에서 바로 다시 읽는다.

hunk 단위 Stage, commit 본문, amend, discard와 충돌 해결은 파일 단위 경계와 일반 commit 흐름이 실제 사용에서 검증된 뒤 추가한다.

## Commit 두 번째 수직 슬라이스

수정된 tracked 텍스트 파일은 diff의 각 hunk를 따로 Stage하거나 Unstage할 수 있다. 선택한 hunk만 index에 반영하고 working tree 파일은 바꾸지 않으며, 성공 뒤 staged와 working tree diff를 같은 Workspace에서 다시 읽는다.

추적하지 않는 파일, 추가·삭제·rename, binary와 지원하지 않는 인코딩은 파일 전체 동작을 유지한다. amend, discard와 충돌 해결은 다음 수직 슬라이스로 남긴다.

## Commit 세 번째 수직 슬라이스

Commit 제목은 계속 필수이며, 사용자는 필요할 때 여러 줄 본문을 선택적으로 입력할 수 있다. Gallae는 제목과 본문을 서로 다른 commit 문단으로 기록하고, 기존 Git identity, hook과 서명 설정을 그대로 사용한다.

성공하면 제목과 본문 입력을 함께 비우고 최신 Repository 상태를 다시 읽는다. 실패하면 staged 상태와 두 입력을 유지한다. Amend는 다음 수직 슬라이스로, discard와 충돌 해결은 이후로 남긴다.

## Commit 네 번째 수직 슬라이스

사용자는 명시적인 `Amend last commit` 선택 뒤 현재 staged 변경과 입력한 제목·본문으로 최신 commit을 교체할 수 있다. Amend를 선택했을 때 두 입력이 모두 비어 있으면 최신 commit의 제목과 본문을 미리 채우고, 선택을 해제하면 수정하지 않은 프리필만 지운다. unstaged 변경은 포함하지 않으며, 아직 commit이 없는 Repository에서는 Amend를 제공하지 않는다.

성공하면 commit 수는 늘리지 않고 최신 HEAD와 Repository 상태를 다시 읽으며 입력과 Amend 선택을 비운다. 실패하면 staged 상태와 입력·선택을 유지한다. discard와 충돌 해결은 이후 수직 슬라이스로 남긴다.

## Commit 다섯 번째 수직 슬라이스

사용자는 선택한 tracked 파일의 unstaged 수정·타입 변경·삭제를 명시적인 확인 뒤 discard할 수 있다. 파일에 staged 변경도 있으면 working tree만 index 상태로 되돌려 staged 내용은 보존하고, staged 변경이 없으면 마지막 commit 상태로 되돌린다.

성공하면 Repository 상태와 diff를 같은 Workspace에서 다시 읽는다. 충돌·untracked·rename 파일에는 이 동작을 제공하지 않으며, untracked 파일 삭제와 rename·hunk discard는 이후 수직 슬라이스로 남긴다.

## History 첫 수직 슬라이스

사용자는 Repository 헤더에서 `Changes`와 `History`를 전환한다. History는 현재 HEAD에서 도달 가능한 최신 commit 최대 100개를 최신순으로 보여 주며, 각 행에는 제목·작성자·시간·축약 SHA를 표시한다. commit 상세는 작성자 이름·이메일·시각과 함께 이름 이니셜·이메일 기반 고정 색 배지로 작성자를 구분한다. 설정의 `Load GitHub Avatars`(기본 켬)가 켜져 있으면 GitHub noreply 이메일은 조회 없이 공개 avatar를 직접 불러오고, 그 외 이메일은 GitHub 공개 사용자 검색으로만 해석해 결과를 이메일별로 저장한다. 이메일은 GitHub 외 어디에도 보내지 않으며, 끄거나 실패하거나 공개 계정이 없으면 이니셜 배지를 유지한다. 표시 한도에 도달하면 목록 끝에 더 오래된 commit이 표시되지 않음을 알린다.

commit을 선택하면 제목과 본문, 작성자 이메일, 전체 SHA, parent와 first-parent 기준 전체 patch를 같은 Workspace에서 읽는다. root commit도 표시하며 목록과 patch의 로딩·빈 상태·오류·재시도를 구분한다. 이 단계는 조회 전용이고, commit 그래프, 모든 branch/ref, 검색·필터, 파일별 drill-down과 branch 이동·생성은 이후 수직 슬라이스로 남긴다.

## History 두 번째 수직 슬라이스

사용자는 현재 HEAD에서 읽은 최근 commit을 메시지·작성자·이메일·SHA로 즉시 검색한다. 검색은 추가 Git 실행 없이 이미 읽은 최대 100개 안에서 이루어지며, 여러 검색어는 서로 다른 필드에 있어도 모두 일치하면 결과에 남는다.

결과가 없으면 검색 실패와 History 읽기 실패를 구분하고 바로 검색을 지울 수 있다. commit 그래프, 모든 branch/ref, 파일별 drill-down과 branch 이동·생성은 이후 수직 슬라이스로 남긴다.

## History 세 번째 수직 슬라이스

History가 읽은 최근 commit에 local branch, remote-tracking branch와 tag가 닿아 있으면 해당 행에서 이름과 종류를 함께 표시한다. annotated tag는 tag object가 아니라 실제 commit 위치에 표시하고, remote의 symbolic HEAD는 중복 정보로 노출하지 않는다.

ref 이름도 기존 History 검색 대상에 포함한다. 이 단계는 조회 전용이며 commit graph와 branch 이동·생성은 이후 수직 슬라이스로 남긴다.

## History 네 번째 수직 슬라이스

History 목록 왼쪽에 현재 HEAD에서 도달 가능한 commit의 부모 관계를 graph로 표시한다. 일반 commit은 같은 lane을 이어 가고 merge commit은 여러 부모로 갈라졌다가 공통 조상에서 다시 합쳐진다. lane마다 테마의 graph 색상을 순환해 갈라진 줄기를 색으로도 구분한다.

검색으로 중간 commit이 숨겨지면 잘못된 연결선을 만들지 않고 각 검색 결과의 commit 점만 표시한다. VoiceOver 이름은 root와 merge commit을 색이나 선 없이도 구분하며, 모든 ref를 함께 걷는 graph와 branch 이동·생성은 이후 범위로 남긴다.

## History 다섯 번째 수직 슬라이스

History는 현재 HEAD뿐 아니라 local branch, remote-tracking branch와 tag에서 도달 가능한 최신 commit을 합쳐 최대 100개까지 topology 순서로 보여 준다. stash와 notes처럼 이 화면에서 다루지 않는 ref는 포함하지 않는다.

다른 branch의 commit이 더 최신이어도 현재 HEAD를 정확히 표시하고 처음 선택한다. 이 단계는 조회 전용이며 파일별 drill-down과 branch 이동·생성은 이후 범위로 남긴다.

## History 여섯 번째 수직 슬라이스

commit을 선택하면 first-parent 기준 변경 파일을 상태와 함께 보여 주고 첫 파일을 선택한다. rename은 원래 경로도 표시하며, root commit은 빈 tree와 비교한다.

파일을 선택하면 해당 파일의 patch만 읽는다. patch는 기본 2MB, 사용자 요청 시 16MB까지 확장하고 binary·UTF-8 아님·과대한 내용을 구분한다. 이 단계도 조회 전용이며 branch 이동·생성은 이후 범위로 남긴다.

## History 일곱 번째 수직 슬라이스

사용자는 Repository 헤더의 현재 branch를 눌러 기존 local branch를 검색하고 선택한다. 현재 branch는 목록에서 따로 표시하며 detached HEAD에서도 local branch를 선택할 수 있다.

전환은 일반적인 안전한 Git switch로 실행한다. local 변경과 충돌하면 강제로 덮어쓰지 않고 기존 branch·index·working tree를 유지한 채 오류를 표시한다. 성공하면 Repository, Changes와 History를 다시 읽어 새 HEAD를 선택한다. branch 생성, remote-tracking branch 전환과 force·merge·stash 보조 동작은 이후 범위로 남긴다.

## History 여덟 번째 수직 슬라이스

사용자는 같은 branch 선택기에서 현재 HEAD를 시작점으로 새 local branch를 만들고 바로 전환한다. 이름 입력은 인라인으로 열리며 Create 또는 Return으로 실행한다. detached HEAD와 아직 commit이 없는 branch에서도 같은 흐름을 사용한다.

빈 이름, 유효하지 않은 이름이나 이미 존재하는 branch는 만들지 않고 현재 branch·index·working tree와 입력값을 유지한 채 오류를 표시한다. 임의의 시작점 선택과 기존 branch 강제 재생성은 포함하지 않으며, remote 게시와 upstream 설정은 branch 생성 뒤 Publish에서 별도로 수행한다.

## History 아홉 번째 수직 슬라이스

branch 선택기는 local branch가 다른 기존 Worktree에서 체크아웃된 경우 폴더를 함께 구분한다. 사용자가 해당 branch를 고르면 현재 Repository를 전환하지 않고 연결된 Worktree 폴더를 같은 창의 새 Repository Workspace로 연다.

연결된 Worktree가 없는 branch는 기존의 안전한 Switch를 유지한다. 누락되었거나 정리 가능한 Worktree는 열지 않으며, Worktree 생성·삭제와 branch 강제 전환은 이후 Advanced 범위로 남긴다.

## Sync 첫 수직 슬라이스

사용자는 Repository Workspace 상단의 Fetch로 현재 Git 설정이 고르는 기본 remote의 변경을 가져온다. 기존 credential helper와 SSH 환경을 사용하되 표시할 수 없는 터미널 입력을 기다리지 않는다.

Fetch는 remote-tracking ref만 갱신하고 현재 HEAD·index·working tree를 바꾸거나 remote 변경을 local branch에 합치지 않는다. 진행 중에는 상태와 Cancel을 표시하며 Escape로도 취소할 수 있다. 성공하면 upstream ahead/behind, Changes와 History를 다시 읽는다. remote가 없거나 Fetch가 실패하면 기존 Workspace를 유지하고 원인을 표시한다.

Fetch 대상 선택은 Sync 열두 번째 수직 슬라이스, 명시적인 prune은 열세 번째 수직 슬라이스, 사용자가 켜는 자동 Fetch는 열네 번째 수직 슬라이스에서 잇는다.

## Sync 두 번째 수직 슬라이스

사용자는 Repository Workspace 상단의 Pull로 현재 branch의 configured upstream을 가져와 fast-forward한다. Pull은 `--ff-only`로 실행해 merge commit을 만들거나 local commit을 rebase하지 않는다.

remote 변경과 겹치지 않는 local working tree 수정은 보존한다. upstream이 없으면 Pull을 비활성으로 표시해 실행 전에 상태를 알린다. branch가 갈라졌거나 local 수정 때문에 갱신할 수 없으면 현재 HEAD·index·working tree를 유지하고 원인을 표시한다. Fetch 단계에서 remote-tracking ref가 갱신된 경우에는 최신 ahead/behind를 다시 읽어 보여 준다.

진행 상태와 Cancel을 표시하고 Escape로도 취소할 수 있다. 성공하면 Repository, Changes와 History를 다시 읽는다. merge/rebase 방식 선택, remote 선택, 강제 갱신과 자동 Pull은 이후 수직 슬라이스로 남긴다.

## Sync 세 번째 수직 슬라이스

사용자는 Repository Workspace 상단의 Push로 upstream이 설정된 현재 branch를 Git 설정이 고르는 기본 push 목적지에 보낸다. 보낼 commit이 있으면 그 수를 Push 버튼 제목에 함께 표시한다. 인자 없는 Push로 기존 `push.default`와 remote 설정을 존중하며 force, upstream 생성과 refspec 지정은 사용하지 않는다.

Push는 commit만 전송하고 현재 HEAD·index·working tree와 local 수정을 바꾸지 않는다. non-fast-forward, upstream 없음, remote 거부와 인증·네트워크 실패는 기존 Workspace를 유지한 채 원인을 표시한다.

진행 상태와 Cancel을 표시하고 Escape로도 취소할 수 있다. 성공하면 Repository, Changes와 History를 다시 읽는다. Push 자체에는 `--set-upstream`을 사용하지 않으며, force·force-with-lease, tag·여러 ref 게시와 remote branch 삭제도 포함하지 않는다.

## Sync 네 번째 수직 슬라이스

upstream 없는 local branch에서는 같은 상단 동작을 Publish로 표시한다. remote가 정확히 하나일 때 현재 branch와 같은 이름의 remote branch 하나만 게시하고 upstream을 설정한다.

Publish는 force하지 않고 현재 HEAD·index·working tree와 local 수정을 바꾸지 않는다. detached HEAD, 아직 commit이 없는 branch, remote가 없거나 여러 개인 경우에는 실행하지 않거나 원인을 표시한다.

진행 상태와 Cancel을 표시하고 Escape로도 취소할 수 있다. 성공하면 Repository, Changes와 History를 다시 읽는다. tag·여러 ref 게시와 remote branch 삭제는 이후 범위로 남긴다.

## Sync 다섯 번째 수직 슬라이스

Publish할 branch에 remote가 하나도 없으면 Gallae가 Add Remote sheet를 연다. 사용자는 기본 이름 `origin`을 그대로 쓰거나 바꾸고 HTTPS·SSH URL 또는 local Repository 경로를 입력한 뒤, remote 등록과 현재 branch 게시를 한 동작으로 실행한다.

입력 단계의 Cancel은 Repository를 바꾸지 않는다. remote 등록 뒤 Publish가 실패하거나 취소되면 추가한 remote는 유지해 다시 Publish할 수 있게 하며, HEAD·index·working tree와 local 수정은 바꾸지 않는다.

## Sync 여섯 번째 수직 슬라이스

upstream 없는 branch에 remote가 둘 이상 설정되어 있으면 Gallae가 Publish 목적지 선택 sheet를 연다. 사용자는 remote 이름을 고른 뒤 현재 branch와 같은 이름의 remote branch 하나만 게시하고 그 branch를 Tracking 대상으로 설정한다.

선택 전 Cancel 또는 Escape는 Repository를 바꾸지 않는다. Publish는 force하지 않고 선택하지 않은 remote와 현재 HEAD·index·working tree·local 수정을 그대로 둔다.

## Sync 일곱 번째 수직 슬라이스

사용자는 Repository Workspace 상단의 Remotes에서 configured remote 이름과 Git이 해석한 Fetch·Push URL을 조회하고 선택해 복사할 수 있다.

Remote 조회는 로딩, 없음과 실패·재시도를 구분하며 Repository의 HEAD·index·working tree와 ref를 바꾸지 않는다.

## Sync 여덟 번째 수직 슬라이스

사용자는 Remotes 목록에서 기존 remote를 선택해 Fetch·Push URL을 따로 편집한다. remote 이름은 유지하며 빈 URL은 저장하지 않는다.

Save는 Git 설정의 첫 Fetch URL과 첫 Push URL만 바꾸고 remote에 연결하지 않는다. 실패하면 입력을 유지하며 Repository의 HEAD·index·working tree와 ref는 바꾸지 않는다.

## Sync 아홉 번째 수직 슬라이스

사용자는 Remotes 목록에서 기존 remote를 제거한다. 제거 전 확인에서 해당 Git 설정과 local remote-tracking branch가 사라진다는 점, remote Repository와 local branch·commit·작업 파일은 삭제되지 않는다는 점을 분명히 보여 준다.

확인하면 선택한 remote 설정과 연결된 local remote-tracking ref를 제거하고 Repository, Remotes와 History를 다시 읽는다. 현재 branch가 그 remote를 Tracking 중이었다면 Tracking 표시는 사라지고 다음 전송 동작은 Publish가 된다. 다른 remote와 HEAD·index·working tree·local branch·commit은 유지한다.

## Sync 열 번째 수직 슬라이스

사용자는 Remotes 목록에서 configured Remote의 Fetch 연결을 시험한다. Gallae는 기존 credential helper와 SSH 환경으로 해당 Remote의 Fetch URL에서 `HEAD`를 읽되, 표시할 수 없는 터미널 인증 입력은 기다리지 않는다.

진행 중에는 상태와 Cancel을 표시하고 Escape로도 취소할 수 있다. 성공하면 `Reachable`을 표시하며, 실패하면 Git 오류를 보여 주고 다시 시도할 수 있다. 시험은 Remote 설정·local ref와 object·HEAD·index·working tree를 바꾸지 않으며 비어 있는 Remote도 연결 가능한 대상으로 인정한다. Push URL과 쓰기 권한은 시험하지 않는다.

## Sync 열한 번째 수직 슬라이스

사용자는 Edit Remote에서 configured Remote의 이름과 Fetch·Push URL을 함께 바꿀 수 있다. 이름을 바꾸면 Git의 remote rename 동작으로 관련 설정과 local remote-tracking branch를 새 이름 아래로 옮기고, 현재 branch의 Tracking 관계도 새 Remote 이름을 가리킨다.

빈 이름, Git이 허용하지 않는 이름이나 이미 존재하는 Remote 이름은 저장하지 않고 입력과 기존 Repository 상태를 유지한다. 성공하면 Repository snapshot과 Remotes를 갱신하며 HEAD·index·working tree·local branch·commit과 remote Repository는 바꾸지 않는다. Save는 Remote에 연결하지 않는다.

## Sync 열두 번째 수직 슬라이스

사용자가 Fetch를 눌렀을 때 configured Remote가 하나면 바로 가져오고, 둘 이상이면 대상 선택 sheet를 연다. 선택한 Remote 이름을 명시한 Fetch로 그 Remote의 configured refspec과 remote-tracking ref만 갱신한다.

Cancel 또는 Escape는 Repository를 바꾸지 않는다. 성공하면 Repository, Changes와 History를 다시 읽으며 선택하지 않은 Remote의 tracking ref와 현재 HEAD·index·working tree·local 수정은 그대로 둔다. 명시적인 prune은 다음 수직 슬라이스, 자동 Fetch는 열네 번째 수직 슬라이스에서 잇는다.

## Sync 열세 번째 수직 슬라이스

사용자는 Fetch의 기본 동작을 그대로 실행하거나 메뉴에서 `Fetch & Prune`을 명시적으로 고른다. Remote가 하나면 바로 실행하고 둘 이상이면 기존 Remote 선택 sheet에서 하나를 고른다.

`Fetch & Prune`은 선택한 Remote의 configured refspec을 기준으로 변경을 가져오고 Remote에서 사라진 local tracking ref를 정리한다. 선택하지 않은 Remote와 local branch·HEAD·index·working tree는 바꾸지 않으며 성공하면 Repository, Changes와 History를 다시 읽는다. 기본 Fetch는 `--prune`을 강제하지 않고 기존 Git 설정을 따른다.

## Sync 열네 번째 수직 슬라이스

사용자는 Fetch 메뉴에서 `Fetch Automatically`를 켜거나 끈다. 기본값은 꺼짐이며 선택은 앱 재실행 뒤에도 유지된다. 켜져 있으면 Gallae와 Repository Workspace가 활성인 동안 5분마다 인자 없는 Fetch를 실행해 현재 branch와 Git 설정이 고르는 기본 Remote만 갱신한다.

다른 Repository 작업이 진행 중인 시점은 건너뛰고 다음 주기를 기다린다. 자동 Fetch는 `--prune`을 강제하지 않으며 성공하면 Repository, Changes와 History를 다시 읽는다. 실행 중 Cancel은 그 Fetch만 중단한다. Remote 없음이나 인증·네트워크 실패가 발생하면 자동 Fetch를 끄고 원인을 한 번 표시하며, local branch·HEAD·index·working tree와 local 수정은 바꾸지 않는다.

## Recovery 첫 수직 슬라이스

사용자는 Repository 헤더에서 `Stashes`를 선택해 최신 Stash 최대 100개를 최신순으로 읽는다. Stash를 선택하면 함께 저장된 tracked·untracked 파일 목록과 선택 파일 patch를 같은 Workspace에서 확인한다.

목록·파일·patch는 조회 전용이며 Stash 생성·적용·삭제와 working tree 변경은 포함하지 않는다. 읽기 실패는 해당 영역에서 다시 시도할 수 있고, patch는 History와 같은 2MB 기본·16MB 확장 미리보기와 binary·UTF-8 아님 상태를 사용한다.

## Recovery 두 번째 수직 슬라이스

사용자는 Stashes에서 선택적인 메시지와 함께 현재 staged·unstaged tracked 변경을 새 Stash로 저장한다. `Include Untracked Files`를 직접 켠 경우에만 untracked 파일도 함께 저장하며 ignored 파일은 포함하지 않는다.

생성 전 Cancel 또는 Escape는 Repository를 바꾸지 않는다. 아직 첫 commit이 없거나 충돌이 있거나 선택한 옵션으로 저장할 변경이 없으면 이유를 보여 주고 실행하지 않는다. 성공하면 HEAD와 commit은 유지한 채 index와 tracked working tree를 HEAD 상태로 되돌리고, 새 Stash와 Repository 상태를 다시 읽는다. Stash 삭제는 네 번째 수직 슬라이스에서 다룬다.

## Recovery 세 번째 수직 슬라이스

사용자는 Stashes에서 선택한 Stash를 적용해 저장된 staged·unstaged tracked 변경과 함께 저장된 untracked 파일을 현재 index와 working tree에 복원한다. 적용에는 안정적인 Stash 식별자를 사용하며, 성공해도 Stash 항목은 삭제하지 않는다.

현재 변경과 겹치거나 새 HEAD와 충돌해 Git이 적용을 거부하면 강제로 덮어쓰지 않는다. HEAD와 Stash를 유지하고 Repository를 다시 읽어 기존 변경이나 충돌 상태를 즉시 보여 준다.

## Recovery 네 번째 수직 슬라이스

사용자는 Stashes에서 선택한 Stash를 명시적인 확인 뒤 영구 삭제한다. 확인은 저장된 변경을 적용하지 않고 Gallae에서 실행 취소할 수 없다는 점과 HEAD·index·working tree는 바뀌지 않는다는 점을 설명한다.

삭제 직전에 선택한 Stash의 commit ID를 현재 목록에서 다시 찾아 번호가 바뀌어도 다른 항목을 삭제하지 않는다. 항목이 이미 사라졌거나 Git이 삭제를 거부하면 목록과 Repository를 다시 읽고 오류를 표시한다.

## Recovery 다섯 번째 수직 슬라이스

사용자는 History에서 현재 branch에 포함된 일반 commit 하나를 Revert해 현재 HEAD 위에 그 변경을 반대로 적용한 새 commit을 만든다. 기존 commit과 이후 History는 그대로 유지하고 Git의 기본 Revert 메시지를 사용한다.

Revert는 변경이 없는 attached local branch에서만 실행한다. merge commit은 mainline 선택이 필요하므로 다섯 번째 슬라이스에서 제외하고 다음으로 분리한다. 적용이 충돌하거나 실패하면 자동으로 abort하고 기존 HEAD와 깨끗한 index·working tree가 복원됐는지 확인한다. 자동 복원이 완전하지 않으면 실제 Repository 상태를 다시 읽어 보여 주고 명확히 경고한다.

## Recovery 여섯 번째 수직 슬라이스

사용자는 merge commit을 Revert할 때 parent 번호와 각 parent의 commit 제목·SHA를 보고 mainline 하나를 직접 고른다. 선택 전에는 실행할 수 없으며 Cancel 또는 Escape는 Repository를 바꾸지 않는다.

Gallae는 선택한 parent 번호를 Git의 mainline으로 명시해 merge가 그 parent에 가져온 tree 변경을 반대로 적용한 새 commit을 만든다. 기존 merge commit과 History는 유지한다. 일반 commit Revert와 같은 clean branch·ancestor 검사, 실패 시 자동 abort와 복원 확인을 적용한다.

## Recovery 일곱 번째 수직 슬라이스

사용자는 변경이 없는 attached local branch의 History에서 현재 HEAD보다 앞선 과거 commit을 골라 `Reset…`할 수 있다. Reset sheet는 현재 branch와 대상 commit, 이후 commit이 이 local branch에서 빠진다는 점을 보여 주고 mixed mode를 기본으로 제시한다. Cancel 또는 Escape는 Repository를 바꾸지 않는다.

Gallae는 선택한 commit이 현재 HEAD의 ancestor인지 다시 확인한 뒤 mixed Reset으로 branch와 index를 대상에 맞추고 working tree 파일은 그대로 둔다. 되돌린 commit의 파일 내용은 unstaged 또는 untracked 변경으로 즉시 나타나며 Remote branch는 바꾸지 않는다. Reflog 지점은 현재 branch를 옮기는 대신 별도의 복구 branch로 보존한다.

## Recovery 여덟 번째 수직 슬라이스

사용자는 같은 Reset sheet에서 soft mode를 골라 현재 local branch만 과거 commit으로 옮기고, 실행 전 index와 working tree를 그대로 유지할 수 있다. 되돌린 commit의 변경은 staged 상태로 남아 바로 다시 commit할 수 있다.

soft Reset도 변경이 없는 attached local branch와 현재 HEAD의 과거 ancestor commit에만 제공한다. 성공하면 Repository와 History를 다시 읽고, 실패하면 실행 전 HEAD와 깨끗한 상태로 복원을 확인한다. Remote branch는 바꾸지 않으며 Reflog 지점은 별도의 복구 branch 생성 흐름에서 다룬다.

## Recovery 아홉 번째 수직 슬라이스

사용자는 같은 Reset sheet에서 hard mode를 골라 현재 local branch, index와 working tree를 선택한 과거 commit에 맞출 수 있다. Hard는 이후 commit의 파일과 변경을 폐기하므로 별도의 파괴적 확인을 한 번 더 거치며, Gallae에서 실행 취소할 수 없음을 명시한다.

hard Reset도 변경이 없는 attached local branch와 현재 HEAD의 과거 ancestor commit에만 제공한다. 이후 추가된 tracked 파일은 제거되고 대상 commit의 파일 내용으로 교체되며, 대상 파일을 막는 untracked 파일이나 폴더도 Git에 의해 삭제될 수 있다. Remote branch는 바꾸지 않고 성공 후 Repository와 History를 다시 읽는다.

## Recovery 열 번째 수직 슬라이스

사용자는 Repository 헤더의 `Reflog`에서 현재 Repository의 HEAD 이동 기록을 최대 100개까지 최신순으로 읽는다. 각 항목은 순서 기반 selector, action, 기록자, 시각과 commit SHA를 보여 주므로 branch 전환이나 Reset 전 HEAD도 찾을 수 있다.

목록 선택과 상세 검사는 조회 전용이며 Repository·HEAD·index·working tree를 바꾸지 않는다. 비어 있음과 읽기 실패를 구분하고 같은 화면에서 재시도할 수 있으며, Git 유지 관리에 따라 오래된 기록이 만료될 수 있음을 알린다. 선택한 지점의 복구는 Recovery 열한 번째 수직 슬라이스에서 제공한다.

## Recovery 열한 번째 수직 슬라이스

사용자는 선택한 Reflog 상세에서 `Create Recovery Branch…`를 눌러 이름을 입력하고, 해당 전체 commit SHA에서 새 local branch를 만든 뒤 바로 전환한다. 기존 local branch ref는 옮기거나 강제로 다시 만들지 않는다.

빈 이름은 실행하지 않는다. 유효하지 않거나 이미 존재하는 이름, local 변경과의 checkout 충돌처럼 Git이 전환을 거부하면 새 branch를 남기지 않고 기존 branch·index·working tree와 입력을 유지한다. Cancel 또는 Escape도 Repository를 바꾸지 않으며, 성공하면 Repository·Changes·History와 Reflog를 새 HEAD 기준으로 다시 읽는다.

## Recovery 열두 번째 수직 슬라이스

사용자는 Repository 상단의 `Integrate`에서 현재 branch를 제외한 local branch 하나를 골라 현재 branch를 fast-forward한다. 선택 화면은 현재 branch와 merge commit을 만들지 않는다는 점을 먼저 보여 주며, Fast-Forward 또는 Return으로 실행하고 Cancel 또는 Escape로 닫을 수 있다. 선택한 branch에 대해서는 두 branch의 고유 commit 수를 함께 보여 주고, fast-forward할 수 없거나 가져올 commit이 없는 관계에서는 해당 동작을 비활성으로 표시한다.

Gallae는 `--ff-only`만 사용한다. 두 branch가 갈라졌거나 local 변경과 대상 파일이 겹치면 merge commit, rebase나 강제 덮어쓰기를 하지 않고 기존 HEAD·index·working tree를 유지한다. 겹치지 않는 local 변경과 선택한 source branch는 보존하며, 성공하면 Repository·Changes·History와 Reflog를 다시 읽는다. detached HEAD, unborn branch와 선택할 다른 local branch가 없는 상태는 실행하지 않는다.

## Recovery 열세 번째 수직 슬라이스

사용자는 같은 Integrate 화면에서 서로 갈라진 local branch를 골라 `Create Merge Commit`으로 합칠 수 있다. `Fast-Forward`가 기본 동작이며 Return도 이를 실행한다. Merge commit 생성은 변경이 없는 attached local branch에서만 활성화되고, 두 branch가 실제로 갈라졌는지 실행 직전에 다시 확인한다.

Gallae는 `--no-ff --no-edit`로 Git의 기본 merge message와 사용자의 identity·hook·서명 설정을 따른다. source branch와 Remote branch는 바꾸지 않는다. 충돌이나 실패가 나면 merge를 자동으로 중단하고 실행 전 HEAD와 깨끗한 상태가 복원됐는지 확인한다. 복원이 끝나지 않으면 실제 Repository 상태와 경고를 보여 준다. 충돌 편집기는 이 수직 슬라이스에 포함하지 않는다.

## Recovery 열네 번째 수직 슬라이스

사용자는 같은 Integrate 화면에서 다른 local branch를 고르고 `Rebase Current Branch`로 현재 branch의 고유 commit을 선택한 branch 위에 다시 적용할 수 있다. Rebase가 현재 branch의 commit ID를 바꾸며 Gallae는 이를 force-push하지 않는다는 점을 실행 전에 보여 준다. 변경이 없는 attached local branch에서만 실행하고 선택한 branch와 Remote branch는 바꾸지 않는다.

Gallae는 다른 local branch까지 함께 이동시키는 사용자 설정을 막기 위해 `--no-update-refs`를 명시한다. 충돌이나 실패가 나면 rebase를 자동으로 중단하고 실행 전 branch·HEAD와 깨끗한 상태가 복원됐는지 확인한다. 복원이 끝나지 않으면 실제 Repository 상태와 경고를 보여 준다. 충돌 해결, continue·skip과 interactive rebase는 포함하지 않는다.

## Advanced 첫 수직 슬라이스

사용자는 Changes에서 충돌 파일을 선택해 Git index의 Base·Ours·Theirs 버전을 세 열로 비교할 수 있다. 각 열은 stage 1·2·3의 역할을 함께 표시하며, 해당 stage가 없는 충돌과 빈 파일, binary, 지원하지 않는 인코딩, 큰 파일을 서로 다른 상태로 설명한다.

이 검사는 Repository의 HEAD·index·working tree를 바꾸지 않는다. Ours 또는 Theirs를 선택해 충돌을 해결하는 동작은 다음 수직 슬라이스에서 추가한다.

## Advanced 두 번째 수직 슬라이스

사용자는 충돌 파일의 비교 화면에서 `Use Ours…` 또는 `Use Theirs…`를 골라 해당 전체 버전으로 파일을 해결할 수 있다. Gallae는 파일 교체와 stage 결과를 먼저 확인하며, 선택한 쪽에 파일이 없으면 삭제를 해결 결과로 명확히 알린다.

실행 직전에 해당 경로가 여전히 충돌 중인지 다시 확인한다. 성공하면 선택한 내용을 working tree와 index에 기록하고 Repository를 다시 읽으며 HEAD는 바꾸지 않는다. 직접 편집한 내용을 해결 결과로 표시하는 흐름은 세 번째 수직 슬라이스에서 별도로 제공한다.

## Advanced 세 번째 수직 슬라이스

사용자는 외부 편집기에서 합친 충돌 파일의 현재 working tree 상태를 `Mark Resolved…`로 명시적으로 stage할 수 있다. 파일을 삭제한 상태도 같은 동작으로 staged 삭제가 되며, 실행 전에 현재 디스크 상태와 삭제 가능성, Gallae가 충돌 marker를 검사하지 않는다는 점을 확인한다.

Gallae는 실행 직전에 해당 경로가 여전히 unmerged인지 다시 확인하고 선택한 경로 하나만 index에 기록한다. 성공하면 Repository를 다시 읽으며 HEAD와 다른 충돌 파일은 바꾸지 않는다. 진행 중인 Merge·Rebase 상태 검사는 다음 수직 슬라이스로 남긴다.

## Advanced 네 번째 수직 슬라이스

Repository에서 Merge 또는 Rebase가 진행 중이면 Workspace 상단에 작업 종류와 남은 충돌 수를 표시한다. 충돌이 모두 해결되면 Continue할 준비가 됐음을 보여 주고, 해결 전에는 Continue가 아직 불가능하다는 점과 Abort 경로가 있음을 함께 알린다.

이 검사는 Git이 계산한 worktree별 내부 경로를 사용해 linked worktree에서도 현재 작업을 찾으며 HEAD·index·working tree를 바꾸지 않는다. 실제 Continue·Abort 실행은 다음 수직 슬라이스로 남긴다.

## Advanced 다섯 번째 수직 슬라이스

사용자는 충돌을 모두 해결한 Merge 또는 Rebase를 Workspace 상단에서 Continue하거나, 확인 뒤 Abort할 수 있다. Continue는 unresolved entry가 없을 때만 활성화하며 실행 직전에 실제 작업 상태를 다시 확인한다. Abort는 충돌 해결 중 만든 변경이 사라질 수 있음을 먼저 알린다.

Gallae는 별도 편집기를 열지 않고 Git의 기본 메시지로 작업을 계속한다. 성공·실패 뒤에는 Repository를 다시 읽어 다음 충돌이나 부분적으로 바뀐 상태도 숨기지 않는다. Rebase Skip과 interactive rebase는 이 슬라이스에 포함하지 않는다.

## Advanced 여섯 번째 수직 슬라이스

사용자는 History에서 현재 branch에 포함된 commit을 골라 그 commit부터 현재 HEAD까지의 기본 Interactive Rebase 계획을 실행 전에 읽을 수 있다. 계획은 오래된 commit부터 `pick`, 제목과 축약 SHA를 한 행에 보여 주며, Git의 기본 선형 rebase와 같이 merge commit은 제외한다.

이 미리보기는 attached local branch에 진행 중인 Git 작업이 없을 때만 제공한다. 선택한 commit이 현재 branch의 ancestor인지 실행 직전에 확인하며 HEAD·index·working tree를 바꾸지 않는다. 순서와 동작 편집은 다음 수직 슬라이스, Interactive Rebase 실행은 그다음 수직 슬라이스로 남긴다.

## Advanced 일곱 번째 수직 슬라이스

사용자는 기본 계획의 각 commit을 `pick`, `reword`, `squash`, `fixup`, `drop`으로 바꾸고 drag 또는 위·아래 동작으로 실행 순서를 편집한다. `squash`와 `fixup` 앞에는 유지되는 commit이 있어야 하며 모든 commit을 `drop`한 계획은 검토 단계로 넘기지 않는다.

유효한 계획은 별도의 읽기 전용 검토 단계에서 최종 순서·동작·제목·SHA를 확인할 수 있다. Back은 편집 상태를 그대로 유지하며 Close 또는 Escape는 계획을 버리고 Repository를 바꾸지 않는다. 실제 Interactive Rebase 실행과 `reword` 메시지 입력은 다음 수직 슬라이스로 남긴다.

## Advanced 여덟 번째 수직 슬라이스

사용자는 검토 단계에서 `reword`로 지정한 commit의 새 메시지를 입력하고, 현재 local branch의 commit ID가 바뀐다는 위험을 확인한 뒤 편집한 계획을 실행한다. 실행 직전에 Repository가 깨끗한 attached branch인지, 대상 범위와 계획이 여전히 유효한지 다시 확인한다.

Gallae는 다른 local ref를 함께 이동시키지 않고 강제 Push도 실행하지 않는다. 성공하면 새 History를 다시 읽고, 충돌하면 진행 중인 Rebase와 충돌 파일을 기존 Workspace에 보여 준다. 실패 뒤에는 실제 상태를 다시 읽으며, 사용자가 실행 중 취소하면 Rebase를 Abort하고 원래 branch·HEAD와 깨끗한 상태가 복원됐는지 확인한다.

## Advanced 아홉 번째 수직 슬라이스

사용자는 Integrate에서 통합 방향을 먼저 고른다. 방향 선택기는 갱신되는 branch를 이름으로 말하는 `Update <현재 branch>`와 `Update another branch`로 표기해 전치사 없이 방향을 정한다. `Update <현재 branch>`는 선택한 local branch를 현재 branch로 fast-forward·merge commit·rebase한다. `Update another branch`(이하 보내기 방향)는 현재 branch가 이미 포함한 다른 local branch를 checkout 없이 현재 HEAD로 fast-forward한다. 두 방향은 같은 branch 목록과 divergence 표시를 공유하고, 각 방향에서 성립하지 않는 동작은 이유와 함께 비활성으로 표시한다.

실행 버튼은 git 문서의 위치 프레임대로 `Fast-Forward <이동하는 branch> to <도착 branch>`로 표기해 어느 ref가 어디로 움직이는지 라벨만으로 드러낸다. 보내기 방향은 ref만 이동하므로 현재 working tree가 dirty해도 실행할 수 있으며, HEAD·index·working tree와 remote branch는 바꾸지 않는다. 실행 직전에 대상 branch가 현재 HEAD의 ancestor인지 다시 확인하고, diverged 상태거나 확인이 실패하면 ref를 바꾸지 않고 원인을 표시한다. 이동은 대상 branch의 reflog에 남는다.

보내기 방향의 merge commit과 rebase는 checkout 없이 충돌을 해결할 수 없으므로 제공하지 않고, force 계열 갱신도 제공하지 않는다. 이 슬라이스는 어느 Worktree에도 체크아웃되지 않은 대상 branch만 갱신하며, 다른 Worktree에 체크아웃된 branch는 폴더 배지와 함께 비활성으로 표시하고 다음 수직 슬라이스에서 다룬다.

## Advanced 열 번째 수직 슬라이스

보내기 방향의 대상 branch가 다른 Worktree에 체크아웃된 경우, ref만 옮기면 그 Worktree의 파일과 어긋나므로 Gallae는 대신 해당 Worktree 폴더에서 `--ff-only` merge를 실행해 branch와 그 Worktree의 working tree를 함께 전진시킨다. 대상 행은 branch picker와 같은 폴더 배지로 Worktree를 표시하고, 실행 문구는 어느 폴더가 갱신되는지 밝힌다.

fast-forward와 겹치지 않는 그 Worktree의 local 수정은 보존하고, 겹치거나 진행 중인 Git 작업이 있으면 강제로 덮어쓰지 않고 원인을 표시한다. 누락되었거나 정리 가능한 Worktree는 대상으로 하지 않는다. 성공·실패 뒤에는 현재 Workspace의 Repository와 History를 다시 읽으며, 해당 Worktree를 열지는 않는다. 열기는 기존 branch picker의 Open Worktree를 유지한다.

## Advanced 열한 번째 수직 슬라이스

History 목록에서 commit 행을 우클릭하면 그 commit에 닿은 모든 local branch를 branch 이름 섹션으로 나눠 보여 준다. 행에 배지로 표시되지 않은 숨은 ref도 포함한다. 현재 branch가 아닌 branch에는 branch picker와 같은 `Switch` 또는 `Open Worktree`를 제공하고, 그 branch가 현재 HEAD의 ancestor이면 Integrate의 보내기 방향과 같은 경로로 그 branch를 현재 HEAD로 옮기는 동작을, 반대로 그 commit이 현재 HEAD의 descendant이면 현재 branch를 당기는 동작을 제공한다. 두 방향은 조건상 함께 나타나지 않는다. Fast-forward 표기는 앱 전체가 git 문서의 위치 프레임 하나를 쓴다. 항상 `Fast-Forward <이동하는 branch> to <도착 branch>`로, 첫 단어가 움직이는 ref이고 `to` 뒤가 도착 위치다. 실행 규칙은 아홉·열 번째 수직 슬라이스와 기존 Integrate fast-forward의 검사·실행 경로를 재사용하며, 성공하면 History와 ref 표시를 다시 읽는다.

tag 배지에는 쓰기 동작을 제공하지 않고, remote-tracking 배지의 정리 동작은 열여덟 번째 수직 슬라이스에서 다룬다. 같은 동작은 키보드와 VoiceOver로도 접근할 수 있어야 하며, detached HEAD에서는 제공하지 않는다.

## Advanced 열두 번째 수직 슬라이스

보내기 방향에서 대상 branch가 현재 branch와 갈라져 있으면 fast-forward 대신 `Create Merge Commit on <대상>`을 제공한다. Gallae는 실행 전에 in-memory merge(`merge-tree`)로 결과를 계산해 충돌이 없으면 그대로 실행할 수 있음을, 충돌이 있으면 실행하지 않고 충돌 파일 수와 목록을 미리 보여 준다.

실행은 계산한 tree로 대상과 현재 branch를 부모로 하는 merge commit을 만들고, 이전 값 검증과 함께 대상 ref만 옮긴다. HEAD·index·working tree는 바꾸지 않으므로 현재 working tree가 dirty해도 실행할 수 있고, 이동 사유는 대상 branch의 reflog에 남는다. commit은 Git 기본 merge message 형식과 사용자의 identity·서명 설정을 따르되, worktree 없이 실행되므로 merge hook이 실행되지 않는다는 점을 실행 전에 알린다.

ref 이동은 Git의 Worktree 체크아웃 보호를 우회하므로, 이 경로는 어느 Worktree에도 체크아웃되지 않은 대상에만 제공하고 실행 직전에 체크아웃 여부를 다시 확인한다. 실행 사이에 대상이 움직여 이전 값 검증이 실패하면 ref를 바꾸지 않고 다시 읽는다. rebase와 force 계열은 계속 제공하지 않는다.

## Advanced 열세 번째 수직 슬라이스

보내기 방향의 갈라진 대상 branch가 다른 Worktree에 체크아웃된 경우, 해당 Worktree 폴더에서 `--no-ff --no-edit` merge를 실행해 branch와 그 working tree를 함께 갱신한다. 이 경로는 일반 merge이므로 사용자의 identity·hook·서명 설정이 그대로 실행된다. 실행 전에는 같은 in-memory 예측으로 충돌 여부와 파일을 미리 보여 준다.

실행 직전에 그 Worktree가 여전히 대상 branch를 체크아웃 중인지 다시 확인한다. 그 Worktree에 진행 중인 Git 작업이 있거나 merge 대상과 겹치는 local 변경이 있으면 실행하지 않고 원인을 표시한다. merge가 충돌하면 강제로 덮어쓰지 않고 사용자가 고른다. 그 Worktree를 같은 창의 Workspace로 열어 기존 충돌 해결·Continue·Abort 흐름으로 잇거나, 즉시 Abort해 실행 전 상태 복원을 확인한다. 성공·실패 뒤에는 현재 Workspace의 Repository와 History를 다시 읽는다.

## Advanced 열네 번째 수직 슬라이스

어느 Worktree에도 체크아웃되지 않은 대상과의 merge가 충돌을 예측하면, 사용자가 명시적으로 선택한 경우에만 Gallae가 임시 linked Worktree를 만들어 대상 branch를 체크아웃하고 거기서 merge를 실행한다. 충돌은 그 Worktree를 같은 창의 Workspace로 열어 기존 충돌 해결·Continue·Abort 흐름으로 해결한다.

임시 Worktree는 Workspace에 Gallae가 만든 것임을 표시하고 Recent에 남기지 않는다. 충돌 없이 merge가 끝나면 바로 제거하고, 충돌 해결을 거친 Worktree는 Continue·Abort 뒤 사용자 확인을 거쳐 제거한다. local 변경이나 진행 중인 작업이 남아 있으면 제거하지 않는다. 앱을 다시 실행하면 남은 임시 Worktree는 일반 Worktree로 취급해 기존 branch picker와 Worktree 흐름에서 다룬다. 이 슬라이스는 이 흐름에 필요한 생성·제거만 다루며, 일반적인 Worktree 생성·관리 UI는 이후 범위로 남긴다.

## Advanced 열다섯 번째 수직 슬라이스

History의 commit 행 메뉴는 현재 branch가 아닌 local branch에 정리 동작을 잇는다. 다른 Worktree에 체크아웃된 branch에는 `Remove Worktree…`를 제공해, 삭제되는 폴더 경로와 branch·commit이 유지된다는 점을 확인한 뒤 Worktree 등록과 폴더를 제거한다. local 변경이나 진행 중인 작업이 남아 있으면 git이 거부하며 강제로 지우지 않고, 주 working tree는 제거 대상이 아니다.

어느 Worktree에도 체크아웃되지 않은 branch에는 `Remove Branch…`를 제공한다. 확인 문구는 branch ref가 삭제되고 다른 ref에서 도달 가능한 commit은 유지된다는 점을 설명한다. 실행은 안전한 삭제만 사용해 현재 branch에 합쳐지지 않은 branch는 git이 거부하고 원인을 표시한다. 강제 삭제와 현재 branch 삭제는 제공하지 않으며, remote branch 삭제는 열여덟 번째 수직 슬라이스에서 다룬다. 성공하면 Repository와 History·ref 표시를 다시 읽는다.

같은 정리 동작은 branch 선택기의 행 우클릭 메뉴에서도 같은 확인과 규칙으로 제공하며, 실행 뒤 branch 목록을 다시 읽는다.

## Advanced 열여섯 번째 수직 슬라이스

사용자는 설정의 `Commit Signing`에서 commit 서명에 쓸 GPG 키를 고른다. Gallae는 Git의 `gpg.openpgp.program`·`gpg.program` 설정과 표준 설치 경로에서 GPG를 찾아 secret key 목록을 키 ID와 사용자 정보로 보여 준다. 키를 고르면 global Git 설정의 `user.signingkey`와 `commit.gpgsign`만 바꾸고, `No Signing Key`는 `commit.gpgsign`을 끄되 기존 `user.signingkey` 값은 지우지 않는다.

Repository별 서명 설정은 Git 규칙대로 계속 우선하며, Gallae는 키를 만들거나 가져오지 않는다. `gpg.format`이 `ssh`면 SSH 서명이 설정돼 있음을 알리고 아무것도 바꾸지 않는다. GPG가 없거나 키 목록을 읽지 못하면 원인과 설치 안내를 표시하고, 적용 실패는 이전 선택을 유지한 채 오류를 보여 준다. 이 화면은 앱 고유 상태를 두지 않는 global Git 설정의 뷰이며, 탭을 열 때마다 현재 설정을 다시 읽는다.

## Advanced 열일곱 번째 수직 슬라이스

History에서 commit을 선택하면 그 commit의 서명 상태를 검증해 상세에 표시한다. 유효한 서명은 서명자 또는 키 ID와 함께, 신뢰를 확인하지 못한 서명·무효한 서명·검증할 수 없는 서명은 각각 구분해 보여 주고, 서명 없는 commit에는 배지를 두지 않는다.

검증은 선택한 commit 하나만 수행해 목록 읽기를 느리게 하지 않으며, 조회 전용으로 Repository 상태를 바꾸지 않는다. GPG를 쓸 수 없으면 검증 불가로 표시한다.

## Advanced 열여덟 번째 수직 슬라이스

History의 remote-tracking 배지 우클릭에 정리 동작을 제공한다. `Delete on Remote…`는 확인 뒤 해당 remote branch를 원격 저장소에서 삭제한다. 확인 문구는 그 remote를 쓰는 다른 사용자에게도 영향이 있고, local branch·commit은 유지되며, 서버의 보호 규칙이 삭제를 거부할 수 있다는 점을 설명한다. 실행은 force 없는 삭제 push 하나만 보내고 기존 remote 작업처럼 진행 상태와 Cancel·Escape를 제공하며, 성공하면 local tracking ref도 함께 사라진다.

`Remove Tracking Reference…`는 local tracking ref 하나만 제거하고 원격 저장소는 바꾸지 않는다. 확인 문구는 Fetch가 그 ref를 되살릴 수 있다는 점을 알린다. remote 이름은 configured remote 목록과 가장 길게 일치하는 접두사로 해석해 이름에 `/`가 든 branch도 정확히 다룬다. 두 동작 모두 성공하면 Repository와 History·ref 표시를 다시 읽고, tag 배지는 계속 조회 전용이다.

## Advanced 열아홉 번째 수직 슬라이스

`Remove Worktree…` 확인은 정리 범위를 함께 고르게 한다. `Remove Worktree`는 기존처럼 Worktree만 제거하고, `Remove Worktree and Branch`는 이어서 그 branch를 안전 삭제한다. branch에 Tracking remote branch가 있으면 원격 삭제까지 잇는 세 번째 선택을 함께 보여 준다.

각 단계는 기존 규칙을 그대로 쓴다. dirty Worktree는 git이 제거를 거부하고, 합쳐지지 않은 branch는 안전 삭제가 거부하며, 원격 삭제는 열여덟 번째와 같은 확인 내용·push 경로를 따른다. 뒤 단계가 실패해도 완료된 앞 단계는 되돌리지 않고, 오류와 다시 읽은 화면이 실제 진행 상태를 보여 준다.

## 디자인 시안 2

`Repository Library`, `Changes`, `History`, `Stashes`, `Reflog`는 서로 경쟁하는 시안이 아니라 사용자가 이동하는 제품 상태다. 각 디자인 안은 이 상태를 같은 시각 언어와 탐색 규칙으로 표현한다. 시안은 제품 코드가 아니라 정보 구조를 선택하기 위한 일회용 HTML이다.

### 제품 상태

| 상태 | 진입 시점 | 핵심 목적 | 기본 구성 |
| --- | --- | --- | --- |
| Repository Library | 복원할 저장소가 없거나 사용자가 Library로 이동했을 때 | 등록한 범위에서 저장소를 찾고 연다 | Library Folder 탐색, 저장소 목록, 선택 항목 요약 |
| Changes | Repository를 열었을 때의 기본 상태 | 현재 브랜치와 작업 트리를 파악하고 diff를 읽는다 | 저장소 문맥, 상태별 파일 목록, 선택 파일 diff |
| History | 사용자가 히스토리로 이동했을 때 | 커밋 관계와 선택한 변경의 맥락을 읽고 안전하게 되돌린다 | 참조 탐색, 커밋 그래프/목록, 커밋 상세와 변경 파일, Revert, soft·mixed·hard Reset |
| Stashes | 사용자가 보관된 작업으로 이동했을 때 | 저장된 변경을 읽고 안전하게 복원·정리한다 | Stash 목록, 변경 파일, 선택 파일 patch, Apply, Delete |
| Reflog | 사용자가 이전 HEAD를 찾을 때 | branch 전환·Reset 전 복구 지점을 확인하고 보존한다 | HEAD 이동 목록, action, 기록자·시각, 전체 commit SHA, 복구 branch 생성 |

초기 수직 슬라이스는 Repository Library와 조회 전용 Changes를 먼저 구현했다. 현재는 같은 작업공간 안에 local·remote-tracking branch와 tag를 함께 읽는 History 검색·ref·commit graph, commit별 변경 파일 검사와 기존 local branch 전환·현재 HEAD 기반 생성·연결된 Worktree 열기, Fetch 대상 Remote 선택·Fetch & Prune·자동 Fetch·fast-forward Pull·비강제 Push, upstream 없는 branch Publish와 Remote 추가·선택·조회·URL·이름 편집·제거·Fetch 연결 시험, Stash 검사·생성·적용·삭제, 일반·merge commit Revert, soft·mixed·hard Reset, Reflog 조회·복구 branch 생성, local branch fast-forward Merge·divergent Merge commit·현재 branch Rebase, 충돌 파일의 Base·Ours·Theirs 검사, 한쪽 전체 버전 적용과 현재 working tree 상태의 명시적 해결 표시, 진행 중인 Merge·Rebase 상태 검사·Continue·Abort와 Interactive Rebase 계획 미리보기·편집·검토·실행까지 이어 붙였다.

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

## 디자인 시안 3·4·5

시안 2 이후의 작업공간 구조, 진행 표시, 시각 언어 결정 기록이다. 시안 3·4·5는 일회용 HTML이며 저장소에 넣지 않고 로컬에 둔다. 팀에 공유할 일이 생기면 그때 커밋하거나 링크로 전달한다. 이 절이 결정의 원본이다.

### 검토한 방향

| 시안 | 안 | 확인한 질문 | 결과 |
| --- | --- | --- | --- |
| 3 | A Navigator · B Modes(현재 구조) · C Timeline | refs를 상시 노출할 것인가, Changes를 목적지로 둘 것인가 | C 제외. 그래프 홈은 핵심 작업 1~3에 소음이다 |
| 3 | B1 Compact Modes · A1 Task-derived Navigator | Navigator의 가치가 diff 폭의 비용보다 큰가 | A1 채택. Fork·SourceTree에 익숙한 사용자 기대와 Stashes·Reflog 상시 가시성 |
| 4 | 6 제목 subtitle + 캡슐 · 7 문맥 바 활동 | 원격 작업 진행 표시를 어디에 둘 것인가 | 6 채택. 창 제목 아래는 자리가 바뀌지 않는 유일한 곳이다 |
| 5 | 테마 A 뉴트럴 · B 시스템 재질 · C 고대비 × 밀도 × diff 배치 × staging × 커밋 작성 | 시각 언어와 남은 상호작용 축 | 아래 결정 |

외부 검토로 Codex(gpt-5.6)에 같은 자료로 리뷰를 받았다. Codex는 B1을 권했고 제품 오너는 A1을 택했다. 두 리뷰가 일치한 항목은 그대로 채택했다. 헤더 슬림화, 동기화 전용 툴바, Remotes·Integrate의 자리, 버튼 스피너·subtitle·캡슐, 동기화 묶음만 잠금이다.

### 결정

- **작업공간 구조.** Navigator · 목록 · 내용의 3열. Navigator 맨 위에 목적지(Workspace: Changes·History, Recovery: Stashes·Reflog), 아래에 접을 수 있는 객체(Branches·Remotes·Tags). Stashes는 개수만 표시하고 항목은 본문에 둔다. Navigator에서 branch·remote·tag를 고르면 본문이 그 객체의 목록·상세로 바뀌고, branch 화면에 Switch와 Integrate가, remote 화면에 URL·Fetch·Prune·Test Connection·편집이 산다. 헤더는 한 줄 문맥 바(branch 메뉴 · Tracking · ahead/behind · 마지막 Fetch)다.
- **진행 표시.** 6번. 누른 버튼 스피너, 창 제목 subtitle, 우하단 캡슐과 Cancel. 잠금은 동기화 묶음과 branch 전환뿐. 완료는 캡슐 결과, 실패는 alert.
- **시각 언어.** 시스템 재질(B)이 기본이다. A(불투명 뉴트럴)는 투명도 줄이기에, C(고대비)는 대비 증가에 대한 같은 테마의 응답이며 테마 선택 UI는 없다. 콘텐츠 패널은 항상 불투명이다.
- **설정.** Appearance(System·Light·Dark), Translucent Sidebar and Toolbar(기본 켬, 시스템 투명도 줄이기가 켜지면 강제로 꺼짐), Compact Rows(기본 끔). 그 외 시각 옵션은 두지 않는다.
- **diff 배치.** Unified·Split은 diff 헤더 토글, 마지막 선택 기억.
- **줄 단위 staging.** 거터 체크박스는 줄 단위 staging 기능이 들어올 때의 UI다. 그전까지는 hunk 버튼을 유지하고 둘을 설정으로 고르게 하지 않는다.
- **커밋 작성.** staged가 없으면 한 줄 바(Commit …)로 접히고 생기면 펼쳐진다.
- **보류.** History 맨 위의 Working Tree 행. 아래 다섯 과업 판정에서 결정한다.

판정 방법은 Codex 제안을 따른다. 같은 데이터로 다섯 과업(현재 branch와 dirty 상태 말하기, hunk 하나 stage와 commit, commit의 branch 관계와 파일 찾기, stash 적용, reflog에서 복구 branch 만들기)을 1180pt와 720pt에서 수행하고, 클릭 수 대신 문맥을 잃은 횟수·가려진 핵심 명령·잘못 고를 수 있는 위험 동작·키보드 포커스 이동을 센다.

### 다음 슬라이스

1. Navigator 도입. `NavigationSplitView` 사이드바에 Workspace·Recovery·Branches·Remotes·Tags, segmented와 branch 팝오버 제거, 헤더를 한 줄 문맥 바로, ⌘1~4 유지.
2. 툴바 축소와 진행 표시 모델. Remotes·Integrate 이동, 버튼 스피너·subtitle·캡슐, 잠금을 동기화 묶음으로 축소, 자동 Fetch가 툴바를 잠그지 않게.
3. Navigator 선택 문맥. branch·remote·tag 선택 시 본문, Stashes·Reflog 목적지 화면, branch 우클릭 메뉴.
4. 재질·접근성 응답과 설정(Appearance, Translucent, Compact Rows), diff Split 보기.

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
- Debug는 `Gallae for Git Dev`와 별도 아이콘으로 Release 앱과 구분하며, 개인 Debug ID는 `Config/Local.xcconfig`에서만 정한다.

## 아직 정하지 않은 것

- 조직 Apple Developer Team에서 canonical App ID를 등록할 시점
- 공개 배포에 사용할 Developer ID Application 인증서와 배포 채널

## 공개 근거

- [Apple Human Interface Guidelines: Split views](https://developer.apple.com/design/human-interface-guidelines/split-views)
- [Apple Human Interface Guidelines: Sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars)
- [Apple Human Interface Guidelines: Lists and tables](https://developer.apple.com/design/human-interface-guidelines/lists-and-tables)
- [Apple Human Interface Guidelines: Materials](https://developer.apple.com/design/human-interface-guidelines/materials)
- [Apple Human Interface Guidelines: Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars)
- [SwiftUI Table](https://developer.apple.com/documentation/swiftui/table)
- [SwiftUI HSplitView](https://developer.apple.com/documentation/swiftui/hsplitview)
- [SwiftUI EnvironmentValues](https://developer.apple.com/documentation/swiftui/environmentvalues)
- [Git documentation](https://git-scm.com/docs)
- [Fork public product site](https://git-fork.com/)
- [GitFox public support documentation](https://www.gitfox.app/support)
