# Gallae 제품 기준

> 제품명: **Gallae** · 공개 표기: **Gallae for Git**
> 상태: 개발 중 · 현재 기준 2026-09-05 · [MIT License](LICENSE)

## 한 문장 정의

Gallae는 로컬 저장소의 상태와 변경 이유를 빠르게 읽고, 안전하게 Git 작업을 끝낼 수 있게 해 주는 무료·오픈소스 macOS Git GUI다.

## 제품 방향

주 사용자는 터미널 Git을 이해하지만 저장소 상태를 더 빨리 읽고 실수를 줄이고 싶은 macOS 개발자다.

- 높은 정보 밀도와 빠른 반응을 유지하면서 macOS의 메뉴·단축키·포커스·선택 관례를 따른다.
- 기본 흐름은 마우스로 이해할 수 있고, 반복 작업은 키보드로 끝낼 수 있어야 한다.
- 현재 저장소·브랜치·선택 항목과 실행할 Git 동작을 화면에서 구분한다.
- 긴 작업은 UI를 막지 않고 진행 상태와 취소 가능 여부를 보여 준다.

## 클린룸 원칙

구현의 근거는 공개된 Git 동작과 문서, Apple 공개 API와 Human Interface Guidelines다. 경쟁 앱은 사용자 문제와 기능 범위를 이해하기 위한 참고 자료일 뿐이다.

다음 항목은 가져오거나 재현하지 않는다.

- 경쟁 앱의 코드, 비공개 동작, 에셋, 스크린샷
- 정확한 레이아웃 수치, 아이콘 구성, 문구, 색 조합, 모션
- 제품을 혼동하게 만드는 이름, 시각 자산, 화면 복제

기능은 같은 Git 개념을 다룰 수 있지만, 정보 구조와 표현은 Gallae의 원칙에서 다시 설계한다.

## 현재 기능 범위

| 작업 | 제공 기능 |
| --- | --- |
| 저장소 탐색 | Repository 직접 열기, Library Folder 등록·탐색, 최근 항목, 마지막 Workspace 복원 |
| 변경 검토·커밋 | 텍스트 diff, 파일·hunk·줄 단위 Stage/Unstage, Commit·Amend, 확인을 거치는 Discard |
| History | 커밋 목록·그래프·검색, branch·tag 범위 조회, 파일별 patch, Revert·Reset |
| 동기화 | Fetch·Fetch & Prune·자동 Fetch, fast-forward Pull, Push·Publish, Remote 관리 |
| 복구 | Stash 조회·생성·적용·삭제, Reflog 조회·복구 branch 생성 |
| 분기 작업 | branch 생성·전환, Merge·Rebase, 충돌 버전 비교·해결, Continue·Abort, Interactive Rebase 계획·실행 |

각 작업의 진입점, 정상·예외 상태와 완료 조건은 [사용자 흐름 문서](docs/README.md)를 따른다. 용어는 [CONTEXT.md](CONTEXT.md)에서 관리한다.

## 저장소 라이브러리

- Repository Library에서 Repository를 선택하면 열고, 일반 폴더를 선택하면 Library Folder로 등록한다.
- 사용자가 허용한 Library Folder 안에서만 하위 Repository를 탐색한다. 디스크 전체를 임의로 검색하지 않는다.
- 직접 연 Repository는 Library Folder 밖에 있어도 최근 항목에 나타난다. 최근 항목 제거는 디스크의 Repository를 바꾸지 않는다.
- Repository를 열면 같은 메인 윈도우가 Repository Workspace로 전환된다. 경로를 전달받으면 해당 Repository를 바로 열고, 복원할 Workspace가 없으면 Library를 보여 준다.
- 설정의 Command Line Tool에서 `gallae [path]` 명령을 설치한다. 경로 기본값은 현재 디렉터리이며, Release 앱이 없으면 Dev 빌드를 연다. 설치는 쓰기 가능한 표준 bin 디렉터리를 사용하고 관리자 권한을 요구하지 않는다.

## UX 원칙

### 정보 구조

- Library는 Library Folder 탐색·Repository 목록·선택 요약으로 구성한다. Workspace는 Navigator·목록·내용의 역할을 구분한다.
- Navigator의 Changes·History·Stashes·Reflog는 목적지이며, branch·remote·tag는 History의 조회 범위다. branch 한 번 클릭은 조회, 두 번 클릭은 전환이다. HEAD는 조회 선택과 별도로 표시한다.
- History의 기본 배치는 **Top and Bottom**이다. 상단에 커밋 목록, 하단에 커밋 머리·파일 목록·diff를 둔다. Appearance → History Layout에서 기존 **Side by Side**도 선택할 수 있고 저장된 선택은 유지한다.
- Expand Review는 History 목록을 가려 검토 영역을 넓힌다. Show History로 복귀하며 선택한 커밋·파일을 유지한다. 현재 범위와 순번을 표시하고 앞뒤 커밋 이동은 현재 검색·조회 범위 안으로 제한한다.
- 상하 배치의 커밋 머리에는 제목, 아바타·작성자·이메일·시각, SHA·서명 상태가 보인다. 본문 미리보기는 공백·줄바꿈을 접어 가용 폭 안에서 두 줄로 보여 준다. Details…는 원문의 줄바꿈을 보존한 전체 메시지·메타데이터·커밋 작업을 제공한다.
- 좁은 창에서는 Navigator부터 접고 창을 강제로 키우지 않는다. 접힌 Navigator에 닿는 방식은 Appearance의 Floating Navigator(기본)·Toolbar Menu·Location Menu 중에서 고른다.
- 현재 branch와 조회 범위를 구분한다. Git의 upstream 관계는 화면에서 Tracking으로 표시하며, 축약된 이름의 전체 값은 도움말과 접근성 이름에 남긴다.
- 작업 트리가 깨끗한 Repository를 열면 History를 먼저 보여 준다. 사용자가 Changes로 이동하면 다음 편집 안내와 Show History를 제공한다.

### 변경 검토와 선택

- 같은 Repository를 새로 읽을 때 History·Stashes의 선택한 revision과 파일을 유지한다. 대상이 사라지면 유효한 항목으로 이동하고, 다른 revision이나 Repository를 고르면 이전 파일 선택을 초기화한다.
- diff의 Unified·Split은 헤더에서 선택하며 취향을 기억한다. 비교할 반대편이 없는 새 파일·삭제 파일 등은 한 칸으로 표시하되 저장된 취향을 바꾸지 않는다. 선택기와 본문은 같은 레이아웃 판단을 쓴다.
- 한 파일에 Staged와 Working Tree 변경이 함께 있으면 세그먼트로 검토 대상을 고르고 반대편 상태를 요약한다. Stage/Unstage 결과로 한쪽이 비어도 자동으로 검토 구획을 바꾸지 않는다.
- 파일 상태 배지는 고정 너비 한 글자(M·A·D·R·C·T·?·!)로 표시한다. 전체 상태명과 Staged/Working 구분은 툴팁·접근성 이름으로 제공한다.
- diff 머리는 파일명·폴더·현재 구획의 추가/삭제 줄 수를 보여 준다. 문맥·패치 헤더는 줄 수 집계에서 제외한다. 전체 상대 경로는 도움말과 Copy Relative Path로 제공한다.
- 파일 식별과 조작이 한 줄에 들어가지 않으면 조작 줄을 아래로 내린다. Stage File·Unstage File은 파일 전체 동작이며 Discard Unstaged Changes는 파일 메뉴에서 기존 확인을 거친다.
- History·Stashes의 저장된 변경 칸이 560pt보다 좁으면 파일 목록을 경로 선택 메뉴로 바꾼다. 넓어지면 같은 선택으로 목록을 복원한다.
- 좌우 배치와 Details의 긴 커밋 본문은 Show Full Message로 펼쳐 스크롤하고 Show Less로 접는다. 다른 커밋을 고르면 다시 접힌다.

### 시각 언어와 조작

- 시스템 글꼴·색상·SF Symbols·표준 macOS 컨트롤을 우선한다. 재질·대비·밀도는 [DESIGN_SYSTEM.md](DESIGN_SYSTEM.md)의 역할을 따른다.
- 사이드바·툴바에는 시스템 재질을 사용하고 콘텐츠 패널은 불투명하게 둔다. System·Light·Dark, 반투명 여부, Compact Rows를 지원하며 시스템 접근성 설정에 응답한다.
- 상태를 색만으로 전달하지 않는다. 라이트·다크 모드, 명확한 키보드 포커스, 충분한 대비와 Reduce Motion을 고려한다.
- 메뉴·단축키·화면 버튼은 같은 명령을 실행한다. 주요 동작은 macOS 메뉴에서 찾을 수 있어야 한다.
- Git 쓰기 동작의 대상과 영향을 밝히고, 되돌릴 수 없는 작업은 확인을 거친다. 조회나 화면 배치 전환으로 Repository를 바꾸지 않는다.
- 진행 표시는 작업 공간을 가리지 않으며 필요한 동작만 잠근다. 실패한 작업 이름과 오류 원인을 알린다.
- 분할선은 드래그 외에 키보드 화살표와 접근성 증감 동작으로 조절한다. 시간은 목록에서 상대 표기, 상세에서 절대 시각으로 보여 준다.

## Fast-forward 표기 프레임

`Fast-Forward <이동하는 branch> to <도착 branch>`로 표기한다. 첫 branch의 ref가 `to` 뒤의 위치로 이동한다. 같은 동작은 Integrate 시트와 History 메뉴에서 같은 라벨을 쓴다.

Integrate 방향은 `Update <현재 branch>` · `Update another branch`로 갱신 대상을 밝힌다.

## 구현 기준

- Swift 6 언어 모드와 macOS 15 이상을 기준으로 한다. SwiftUI를 기본으로 사용하고 실제 품질 요구가 확인된 지점에서 AppKit으로 보완한다.
- Git은 사용자의 시스템 Git을 별도 프로세스로 실행하고 공개된 porcelain 출력을 우선 사용한다. patch 형식 고정과 파일 내용 설정의 경계는 [Git 설정 안내](docs/git-configuration.md)를 따른다.
- 화면은 디자인 시스템의 Semantic·Component 역할을 사용한다. 화면별 임의 색·간격 규칙을 만들지 않는다.
- 하나의 메인 윈도우에서 Library와 Workspace를 전환한다. 여러 창은 실제 병렬 작업 요구가 확인될 때 검토한다.
- 첫 배포는 Sandbox를 사용하지 않는 직접 배포를 기준으로 하며 Hardened Runtime을 유지하고 Developer ID 서명·공증을 준비한다. 공개 배포판은 아직 없다.

### 번들 ID 가드레일

- 공개 canonical ID는 `com.mabyko.gallae`다. 조직 팀에서 등록하기 전에는 빌드·서명 설정에 넣지 않는다.
- 개인 개발 ID와 서명 팀은 gitignore된 `Config/Local.xcconfig`에만 둔다. 추적되는 기본 빌드는 `forked.gallae.local`을 사용한다.
- Debug는 `Gallae for Git Dev`와 별도 아이콘으로 Release 앱과 구분한다.

## 문서 관리

현재 제품 기준·도메인 용어·디자인 시스템·사용자 흐름은 코드와 함께 관리한다. 설계 시안 비교, 단계별 구현 이력과 조사 기록은 팀 위키에서 관리하며 공개 문서를 읽거나 기여하기 위해 위키 접근 권한을 요구하지 않는다.
