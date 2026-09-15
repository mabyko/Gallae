# UC-18 · upstream 없는 local branch Publish

> 우선순위: P1

| 항목 | 내용 |
| --- | --- |
| 사용자 목표 | 새 local branch를 선택한 remote와 branch 이름으로 안전하게 처음 게시한다. |
| 시작 조건 | commit이 있고 upstream이 없는 local branch의 Repository Workspace가 열려 있다. |
| 진입점 | Repository Workspace 상단의 Publish |
| 완료 상태 | 지정한 이름의 remote branch가 생기고 현재 local branch의 upstream으로 설정된다. local branch 이름은 유지한다. |

## 정상 흐름

1. 사용자가 Publish를 누른다.
2. remote가 하나도 없으면 Gallae가 Publish Branch sheet에서 기본 remote 이름 `origin`과 Repository URL 또는 경로를 받는다. 하나 이상이면 항상 확인 sheet를 열고 `origin`이 있으면 우선 선택한다. remote가 하나면 선택 메뉴 대신 이름을 표시한다. 설정된 remote의 Push URL도 함께 표시한다.
3. 두 sheet 모두 출발점인 Local Branch와 목적지를 구분하고 게시할 이름을 미리 채운다. 사용자가 이름을 수정하면 Publish to 요약도 갱신된다. 목적지와 이름을 확인하고 Add & Publish 또는 Publish Branch를 눌러야 branch 하나를 비강제로 게시한다.
4. 성공한 branch에 upstream을 설정하고 Repository, Changes와 History를 다시 읽는다.
5. 최신 Tracking ahead/behind를 표시하며 현재 HEAD·index·working tree와 local 수정은 유지한다.

## 대안 흐름

- Navigator의 Remotes → Add Remote…는 원격 주소만 등록하는 별도 진입점이다. 이 경로에서는 Fetch·Publish하지 않으며, 등록 후 Publish를 따로 실행할 수 있다.

- Add Remote 입력 중 Cancel 또는 Escape를 누르면 remote를 등록하지 않는다.
- Publish 목적지 선택 중 Cancel 또는 Escape를 누르면 아무 remote에도 게시하지 않는다.
- 실행 중 Cancel 또는 Escape를 누르면 Publish를 중단한다. remote 등록 뒤 취소되었다면 추가한 remote는 유지한다.
- detached HEAD 또는 아직 commit이 없는 branch에서는 Publish를 실행하지 않는다.
- 빈 이름은 제출할 수 없다. 잘못된 Git branch 이름은 remote 추가·게시 전에 거부하고 입력칸 아래에 오류를 표시한다. 확인창과 입력값을 유지하고 이름 입력칸으로 포커스를 돌려 바로 수정할 수 있게 한다.
- non-fast-forward, remote hook 거부, 인증 또는 네트워크 오류가 발생하면 force하지 않고 Git의 원인을 표시한다.
- remote 등록 뒤 게시가 실패하면 추가한 remote는 유지하고 오류를 표시해 다시 Publish할 수 있게 한다.
- 터미널 입력은 기다리지 않으며 기존 credential helper와 SSH 환경은 그대로 사용한다.

## 완료 확인

- Remote 이름·URL 입력, 목적지 선택, Publish와 Cancel은 키보드와 VoiceOver로 식별하고 실행할 수 있다.
- 지정한 이름의 remote branch 하나만 게시하며 local branch 이름과 다른 ref, local 수정은 바꾸지 않는다.
- 이름이 다른 upstream도 다음 Push·Pull에서 사용할 수 있다. Push 설정 처리 기준은 [UC-17](uc-17-push-current-branch.md)을 따른다.
- configured remote URL 조회·편집·제거와 Fetch 연결 시험은 Workspace 상단의 Remotes에서 제공한다. force, tag·여러 ref 게시와 remote branch 삭제는 포함하지 않는다.

[사용자 흐름 문서로 돌아가기](../README.md)
