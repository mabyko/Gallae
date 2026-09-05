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
- Navigator의 Changes·History·Stashes·Reflog는 목적지다. branch·remote branch·tag 한 번 클릭은 History의 해당 commit으로 이동하며 전체 그래프를 좁히지 않는다. branch 두 번 클릭은 전환이다. HEAD는 탐색 선택과 별도로 표시한다.
- 별도 Worktree가 있는 branch의 전환은 해당 폴더를 여는 동작이다. 브랜치 더블클릭·Open Worktree·상단 브랜치 메뉴·History 행 메뉴 모두 이동 전의 History 조회 범위를 유지한다. 일반적인 다른 Repository 열기는 범위를 초기화한다. 이동 성공 후 대상 HEAD를 선택한다. 작업 위치는 Working on, 명시적으로 좁힌 조회 범위는 Filter로 구분하며 좁은 창의 작업 위치는 브랜치 이름으로 줄인다.
- 연결된 Worktree가 있으면 Branches 위에 접을 수 있는 Worktrees 목록을 표시한다. 접기 화살표는 Worktrees 제목 바로 오른쪽에 항상 표시하며, 맨 오른쪽의 작업 메뉴와 분리한다. 접힌 상태에서도 두 조작은 유지한다. 기본 폴더와 연결된 폴더를 나란히 나열하고 branch 또는 Detached HEAD, 현재 폴더, 잠금·누락 상태를 구분한다. 한 번 선택하면 History에서 해당 HEAD를 확인하고, 더블클릭·Return·Open Worktree는 폴더를 연다. CLI나 다른 앱에서 만든 Worktree도 같은 목록에 표시한다.
- Branches·Worktrees의 메뉴와 상단 branch 메뉴에서 New Worktree를 만든다. 새 branch와 시작 commit 또는 사용 중이 아닌 기존 branch를 고르고, 생성할 위치와 새 폴더 이름을 지정한다. 생성 후 열기는 기본으로 켜져 있다. 기존 경로를 덮어쓰지 않으며 현재 폴더의 변경은 유지한다. 제거는 기본·현재·잠긴·누락된 Worktree를 보호하고 Git의 안전한 제거를 사용한다.
- Branches·Remotes·Tags 헤더는 같은 스타일의 작업 메뉴를 제공하며 목록이 비어 있어도 표시한다. Remotes → Add Remote는 이름과 URL만 등록하고 Fetch·Publish하지 않는다. 기존 Publish에서 여는 Add & Publish 흐름은 유지한다. Tags → New Tag는 이름과 대상 commit(기본 HEAD)을 입력받아 로컬 lightweight tag를 생성한다. 기존 tag를 덮어쓰거나 checkout·working tree를 바꾸지 않으며 자동 push하지 않는다. commit이 없는 저장소에서는 태그 생성을 비활성화한다.
- History의 기본 배치는 **Top and Bottom**이다. 상단에 커밋 목록, 하단에 커밋 머리·파일 목록·diff를 둔다. Appearance → History Layout에서 기존 **Side by Side**도 선택할 수 있고 저장된 선택은 유지한다.
- Expand Review는 History 목록을 가려 검토 영역을 넓힌다. Show History로 복귀하며 선택한 커밋·파일을 유지한다. 현재 범위와 순번을 표시하고 앞뒤 커밋 이동은 현재 검색·조회 범위 안으로 제한한다.
- History는 전체 branch·tag 이력이 기본이며, 머리 메뉴의 명시적 필터로 특정 ref의 이력만 볼 수 있다. 필터는 Clear Filter로 해제하며, 필터 밖의 ref를 선택하면 전체 History에서 보는 동작을 안내한다. 브랜치 탐색 시 텍스트 검색은 해제한다. 최초 100개를 읽고 Load Older Commits 또는 오래된 ref 탐색으로 범위를 확장한다. 로컬 branch 칩의 기본색은 파랑, 원격 branch는 청록, tag는 보라다. Appearance → History Colors의 색상표에서 그래프 시작색과 세 종류의 배지색을 각각 바꾸고 초기화할 수 있다. 배지는 아이콘 영역과 이름 사이에 옅은 세로선을 둔다. 이름은 기본 글자색으로 읽기 쉽게 표시하고 종류별 색상은 아이콘·배경·테두리에만 적용한다. HEAD 칩 대신 현재 체크아웃한 커밋의 제목과 branch·tag 칩을 굵게 표시하고, 다른 커밋의 칩은 보통 굵기로 표시한다. 현재 위치 정보는 도움말·접근성 설명에 유지한다.
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

### 충돌과 외부 병합 도구

- 현재 branch의 Create Merge Commit은 충돌이 나면 Merge 상태를 유지하고 Changes의 충돌 파일을 보여 준다. 충돌 외의 실행 실패는 기존 자동 중단·복원 검사를 유지한다. 해결 후 Continue로 완료하거나 Abort로 중단한다. Pull은 fast-forward 전용이다.
- Settings → General → Merge Tool은 Use Git Configuration·VS Code·Sublime Merge를 제공한다. Zed는 Open in 에디터로만 제공한다. Git 설정은 merge.guitool, merge.tool 순서로 선택하며 추측으로 다른 도구를 실행하지 않는다. Git 설정을 바꾸지 않으며 터미널 입력이 필요한 도구는 터미널에서 실행하도록 안내한다.
- 충돌 파일의 Open in Merge Tool은 양쪽에 있는 일반 파일을 대상으로 한다. 직접 연동은 UTF-8 텍스트의 Base·Ours·Theirs를 임시로 내보내고 결과는 실제 working tree 파일에 저장한다. 앱에 포함된 CLI를 인자 배열로 실행하고 편집 화면을 닫을 때까지 기다린다. 임시 버전은 실행 종료 후 정리한다.
- VS Code·Sublime Merge 직접 실행은 index·HEAD를 바꾸지 않으며 사용자가 결과를 검토하고 Mark Resolved를 실행한다. Git 설정 사용은 git mergetool의 스테이징 동작을 따르고 종료 후 실제 상태를 다시 읽는다. 도구 실행만으로 병합을 Continue하지 않는다. 삭제·심볼릭 링크·서브모듈 등은 기존 파일 해결 동작이나 터미널을 안내한다.

### 시각 언어와 조작

- branch 우클릭과 상단 작업 위치 메뉴의 Open in에서 Finder 또는 기본 터미널로 폴더를 열고, Copy Path로 경로를 복사한다. 현재 branch는 현재 폴더, 다른 Worktree에서 체크아웃한 branch는 해당 폴더를 대상으로 하며, 체크아웃된 폴더가 없는 branch에서는 비활성화한다. checkout은 바뀌지 않는다. Settings → General → Terminal Application에서 설치된 Terminal·Ghostty·Warp·iTerm2·cmux·Kaku·WezTerm·kitty·Alacritty·Rio 중 선택하며 기본값은 Terminal이다. Other…로 다른 앱을 선택할 수 있고, 사용자 지정 앱은 폴더 열기를 지원해야 한다. 선택은 재실행 후에도 유지한다. 앱이 사라졌거나 실행에 실패하면 오류를 표시한다.
- 같은 Open in 메뉴에서 기본 에디터로도 폴더를 연다. Settings → General → Editor Application은 설치된 VS Code·Zed와 Other…를 제공하며 터미널 설정과 별도로 저장한다. 처음에는 VS Code, 없으면 Zed를 선택한다. 둘 다 없으면 VS Code를 미설치 상태로 표시하고 Other…로 지정할 수 있다. 폴더 열기는 macOS에 직접 요청하므로 에디터 CLI나 셸 명령이 필요하지 않다.
- Appearance → Accent Color에서 앱 선택·컨트롤의 강조색을 고른다. 기본값은 macOS 강조색을 따르는 System이며, 색상표에서 고른 값은 재실행 후에도 유지된다. History 그래프·배지 색과 diff의 추가·삭제 색은 별도로 유지한다.
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
