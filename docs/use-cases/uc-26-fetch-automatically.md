# UC-26 · 자동 Fetch

> 우선순위: P1

| 항목 | 내용 |
| --- | --- |
| 사용자 목표 | 작업을 바꾸지 않고 활성 Workspace의 Remote 상태를 주기적으로 갱신한다. |
| 시작 조건 | Remote가 설정된 Repository Workspace가 열려 있다. |
| 진입점 | Repository Workspace 상단 Fetch 메뉴의 Fetch Automatically |
| 완료 상태 | Git이 고른 기본 Remote의 최신 tracking ref와 Repository 상태가 같은 Workspace에 표시된다. |

## 정상 흐름

1. 사용자가 Fetch 메뉴에서 Fetch Automatically를 켠다.
2. Gallae와 현재 Workspace가 활성인 동안 5분이 지나면 Gallae가 인자 없는 Fetch를 실행한다.
3. Git이 현재 branch와 설정을 기준으로 기본 Remote를 고른다.
4. 성공하면 Gallae가 Repository, Changes와 History를 다시 읽는다.
5. 사용자가 기능을 끄기 전까지 같은 주기를 반복하며 선택은 앱 재실행 뒤에도 유지된다.

## 대안 흐름

- 앱이 비활성이거나 Library가 보이는 동안에는 주기를 실행하지 않는다.
- 다른 Repository 작업이 진행 중이면 그 주기를 건너뛰고 다음 주기를 기다린다.
- 실행 중 Cancel 또는 Escape는 현재 Fetch만 중단하며 자동 Fetch 설정은 유지한다.
- Remote가 없거나 인증·네트워크 오류가 발생하면 자동 Fetch를 끄고 원인을 한 번 표시한다.
- 기능을 끄면 이후 주기를 실행하지 않는다.

## 완료 확인

- Fetch Automatically와 실행 중 Cancel은 키보드와 VoiceOver로 식별하고 실행할 수 있다.
- 여러 Remote를 순회하지 않고 인자 없는 Fetch로 Git이 고르는 기본 Remote만 사용한다.
- `--prune`을 강제하지 않고 사용자의 기존 Git 설정을 따른다.
- local branch·HEAD·index·working tree와 local 수정은 바꾸지 않는다.

[사용자 흐름 문서로 돌아가기](../README.md)
