# UC-15 · 기본 remote Fetch

> 우선순위: P1

| 항목 | 내용 |
| --- | --- |
| 사용자 목표 | 현재 작업을 바꾸지 않고 remote의 최신 ref를 가져온다. |
| 시작 조건 | remote가 설정된 Repository Workspace가 열려 있다. |
| 진입점 | Repository Workspace 상단의 Fetch |
| 완료 상태 | 최신 remote-tracking ref와 upstream ahead/behind가 같은 Workspace에 표시된다. |

## 정상 흐름

1. 사용자가 Fetch를 누른다.
2. Gallae가 현재 Git 설정이 고르는 기본 remote에서 변경을 가져온다. 진행 상태는 툴바 Fetch 아이콘, 창 제목 아래 subtitle, 우하단 캡슐(Cancel 포함)로 보이고, Fetch·Pull·Push와 branch 전환만 기다린다. Stage·Commit·조회·Refresh는 그동안 계속 쓸 수 있다.
3. Fetch가 끝나면 Gallae가 Repository, Changes와 History를 다시 읽는다.
4. 현재 HEAD·index·working tree와 local 수정은 그대로 유지된다.

## 대안 흐름

- 사용자가 Cancel 또는 Escape를 누르면 실행 중인 Fetch를 중단하고 기존 Workspace를 유지한다.
- 성공하면 캡슐이 `Fetched` 또는 `Fetched from <remote>`를 잠깐 보이고 사라진다.
- Fetch 중 다른 Repository를 열면 이전 Repository의 완료 결과·오류·선택 화면이 새 Workspace를 덮지 않는다. 같은 Repository에서 Stage·Commit을 완료한 경우에는 두 작업의 최신 상태를 함께 읽는다.
- remote가 없으면 설정되지 않았다는 오류를 표시한다.
- 인증 또는 네트워크 오류가 발생하면 Git의 원인을 표시하고 같은 Workspace에서 다시 시도할 수 있다.
- 터미널 입력은 기다리지 않으며 기존 credential helper와 SSH 환경은 그대로 사용한다.

## 완료 확인

- Fetch와 Cancel은 키보드와 VoiceOver로 식별하고 실행할 수 있다.
- Fetch는 remote 변경을 현재 local branch에 merge 또는 rebase하지 않는다.
- Remote가 둘 이상일 때의 대상 선택은 [UC-24](uc-24-choose-fetch-remote.md), 명시적인 prune은 [UC-25](uc-25-fetch-and-prune.md), 사용자가 켜는 주기 실행은 [UC-26](uc-26-fetch-automatically.md)으로 이어진다. 기본 Fetch는 `--prune`을 강제하지 않고 기존 Git 설정을 따른다.

[사용자 흐름 문서로 돌아가기](../README.md)
