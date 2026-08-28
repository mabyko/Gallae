# Gallae 첫 공개 버전 구현 계획

> 상태: 첫 공개 범위 구현 완료 · 공개 결정 대기 · 2026-08-27
> 범위: 조회 전용 Open & Inspect

## 사용자 결과

첫 공개 버전은 사용자가 Repository를 찾고, 열고, 현재 브랜치와 작업 트리 변경을 읽는 데까지 제공한다. 구현은 작게 검증하기 위해 두 단계로 나눈다.

- **1A · 열기와 검사**: Repository 직접 열기 → HEAD와 상태 표시 → 파일 선택 → 텍스트 diff
- **1B · Library와 복원**: Library Folder 등록 → 점진적 탐색 → Repository 열기 → 재실행 복원

1A와 1B는 같은 Repository Workspace를 사용한다. 첫 공개 버전에는 둘 다 포함하지만 반드시 1A를 먼저 동작하게 만든다.

## 앱 진입 흐름

```text
앱 실행
├─ Repository 경로와 함께 실행
│  ├─ 유효함 → Repository Workspace / Changes
│  └─ 열 수 없음 → 원인과 복구 경로
├─ 복원 가능한 Active Repository 있음 → Workspace 복원 후 새로고침
└─ 복원할 항목 없음 → Repository Library
   ├─ Repository 직접 열기
   └─ Library Folder 등록 → 점진적 탐색 → Repository 선택 → 열기
```

Library에서 선택은 요약만 바꾸고, 명시적인 Open 명령이 Workspace를 연다.

## 반드시 표현할 상태

| 상태 | 보여 줄 정보 | 다음 행동 |
| --- | --- | --- |
| Library가 비어 있음 | 등록된 위치와 최근 Repository가 없음 | 폴더 등록 또는 Repository 직접 열기 |
| 탐색 중 | 탐색 범위, 진행 여부, 발견 수 | 발견한 Repository 열기 또는 탐색 취소 |
| 탐색 결과 없음 | 탐색은 끝났지만 Repository가 없음 | 다른 폴더 선택 또는 재탐색 |
| 위치 접근 불가 | 읽을 수 없는 위치와 원인 | 위치 다시 선택 또는 Library에서 제거 |
| Git 사용 불가 | Git 또는 Command Line Tools 문제 | 설치·복구 후 다시 시도 |
| Git Repository가 아님 | 선택한 경로와 판정 | 다른 폴더 선택 |
| bare Repository | 지원하지 않는 Repository 유형 | 다른 Repository 선택 |
| Clean | 변경 파일이 없음 | Finder에서 열기 또는 이후 History로 이동 |
| detached HEAD | 브랜치 대신 현재 commit | 이후 브랜치 선택 |
| unborn branch | 브랜치 이름과 아직 commit이 없다는 상태 | 현재 상태 계속 검사 |
| upstream 없음 | 로컬 브랜치와 upstream 미설정 상태 | 이후 Remote 설정 |
| 충돌 있음 | 충돌 파일과 읽을 수 있는 내용 | 이후 충돌 해결 기능 |
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
- 첫 버전의 모든 Git 기능은 조회 전용
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
   └─ GallaeTheme
```

- `AppModel`은 화면 전환, 선택과 비동기 작업 취소만 맡는다.
- `RepositoryInspector`는 Git 실행과 출력을 숨기고 불변 snapshot과 file diff를 돌려준다.
- `RepositoryScanner`는 허용된 Library Folder 안에서만 후보를 찾고 결과를 점진적으로 전달한다.
- `LibraryStore`는 URL bookmark, 최근 Repository와 마지막 Workspace를 저장한다.
- 구현체가 하나뿐인 protocol, DI container, coordinator, database layer는 만들지 않는다.

## 단계별 완료 조건

### 0 · 프로젝트와 Git 실행 — 완료

- macOS 15 대상 Xcode 프로젝트가 빌드되고 테스트 명령이 동작한다.
- 추적 설정은 `forked.gallae.local`을 사용하며 개인 ID와 서명 팀은 로컬 xcconfig에만 존재한다.
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
- 상단에서 Repository, 경로, branch와 로컬 upstream 기준을 확인할 수 있다.
- 파일 목록과 선택한 텍스트 diff를 2열로 표시한다.
- 같은 경로에 staged와 unstaged 변경이 함께 있으면 범위를 나눠 표시한다.
- binary, 지원하지 않는 인코딩과 과대한 diff를 빈 상태와 구분한다.
- 텍스트 diff는 처음 2MB까지 읽고, 사용자가 요청하면 16MB까지 확장한다. 그보다 크거나 표시할 수 없는 파일은 외부에서 열 수 있다.
- 실행·복원·앱 활성화와 Refresh 명령에서 새로 읽는다.
- 취소된 작업과 늦게 끝난 이전 결과가 최신 화면을 덮어쓰지 않는다.

### 1B-1 · Repository Library — 완료

- 사용자가 허용한 Library Folder 밖은 탐색하지 않는다.
- symlink를 따라가지 않고 package·숨김 디렉터리와 `.git` 내부를 건너뛴다.
- 유효한 Repository를 찾으면 그 하위 탐색을 멈춘다.
- 발견 결과를 즉시 보여 주고 탐색을 취소할 수 있다.
- 일부 경로의 실패가 전체 결과를 지우지 않는다.
- 선택은 요약만 바꾸며 Return, 이중 클릭 또는 Open 명령이 같은 윈도우를 Workspace로 전환한다.
- 목록은 이름과 경로부터 보여 준다. 브랜치와 변경 상태는 보이는 행부터 읽고, commit 수와 최근 활동은 선택한 Repository에서만 계산한다.

### 1B-2 · 복원 — 완료

- Library Folder, 최근 Repository와 마지막으로 성공한 Workspace 하나를 저장한다.
- 복원한 Workspace의 Git 데이터는 새로 읽는다.
- 삭제·이동·읽기 실패로 복원에 실패하면 Library에서 다시 연결하거나 제거할 수 있다.
- 실패한 위치를 사용자의 조치 없이 매 실행마다 반복해서 열지 않는다.
- Library Folder는 실행 시 다시 탐색하며, 일부 저장 위치가 실패해도 다른 Folder와 최근 Repository는 유지한다.

### 공개 전 점검 — 예정

- 키보드만으로 열기, 선택, diff 이동과 새로고침을 마칠 수 있다.
- VoiceOver 이름과 포커스 순서가 명확하다.
- System, Light, Dark와 Reduce Motion을 확인한다.
- 많은 Repository, 많은 변경 파일과 큰 diff fixture에서 창 조작이 멈추지 않는다.
- 스테이징, 커밋, 원격 통신, 그래프, 여러 창과 지속적인 파일 감시는 포함하지 않는다.
- 첫 화면에서 Repository와 HEAD를 바로 식별할 수 있다.
- 탐색이 끝나기 전에도 발견한 Repository를 열 수 있다.
- Repository, 파일과 diff를 키보드로 선택할 수 있다.
- Clean, detached HEAD, 충돌과 오류를 색 없이도 구분할 수 있다.
- 마지막 성공 상태와 현재 상태를 혼동하지 않는다.
- 모든 실패 상태에 사용자가 실행할 수 있는 다음 행동이 있다.
- 조회 동작이 Git 상태를 바꾸지 않는다.

빈 Repository Library와 깨끗한 Repository Workspace의 세로 확장 결함은 수정했고, 변경이 있는 Workspace를 포함해 기본·최소·확대 창의 접근성 frame을 확인했다. 실제 키 입력과 macOS 접근성 트리로 ⌘O·Esc, Return·이중 클릭, 방향키로 파일과 diff 전환, ⌘R 새로고침을 확인했고 Repository·경로·HEAD와 목록 행의 이름은 의미를 포함하며 중복해 읽히지 않는다. Finder가 전달한 폴더는 앱 실행 전과 실행 중 모두 같은 메인 윈도우에서 열리고, 유효하지 않은 폴더는 오류를 표시하면서 기존 Workspace를 유지하는 것을 확인했다. 탐색 중 취소 뒤 발견 결과 유지, 접근 불가 Library Folder의 재시도·재연결·제거, Recent Activity 실패의 재시도, 새로고침 실패 뒤 이전 Workspace 유지와 복구도 실제 상태로 확인했다. Light·Dark의 기본·최소 창은 실제 픽셀 캡처로 Library 세 열의 상단 정렬, 좁은 창의 빈 상태와 동작 노출, Changes 목록보다 diff에 더 넓은 면적을 두는 2열 균형을 확인했다. System은 현재 macOS Dark 설정을 그대로 따르며, 사용자 지정 애니메이션이 없어 Reduce Motion용 별도 분기 없이 표준 SwiftUI 동작을 따르는 것을 확인했다. 두 환경은 배포 전 최종 검수에서 다시 확인한다. 대량 경로는 임시 Library의 Repository 32개, 변경 파일 501개와 12,000행 diff fixture로 검증한다.

공식 Git 저장소 `f78ce2f7b6`의 4,850개 파일에 500 commit 전 tree를 적용한 실제 fixture에서는 tracked 1,335개와 untracked 47개를 합쳐 변경 1,382개가 나왔다. 전체 diff는 약 7.1MB, 가장 큰 단일 파일 diff는 약 283KB였고 `RepositoryInspector`가 모든 파일을 19.8초에 읽는 동안 2MB 기본 한계에 걸린 파일은 없었다. 기본 2MB와 사용자 요청 시 16MB 확장 한계를 유지한다.

## 각 단계의 검증

모든 단계는 실행 가능한 앱과 `xcodebuild test` 성공으로 끝낸다. Git parser와 탐색처럼 분기나 반복이 있는 로직은 임시 디렉터리와 임시 Repository를 사용한 작은 통합 테스트를 남긴다. 경쟁 앱의 코드, 에셋, 문구, 정확한 수치와 동작을 fixture나 기준값으로 사용하지 않는다.

## 아직 남은 결정

- 조직 팀의 canonical App ID 등록 시점
- 공개 배포에 사용할 Developer ID Application 인증서와 배포 채널
