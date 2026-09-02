# UC-22 · configured Remote Fetch 연결 시험

> 우선순위: P1

| 항목 | 내용 |
| --- | --- |
| 사용자 목표 | 동기화 전에 Git이 configured Remote의 Fetch URL을 읽을 수 있는지 확인한다. |
| 시작 조건 | 하나 이상의 configured Remote가 있는 Repository Workspace가 열려 있다. |
| 진입점 | Navigator Remotes 섹션에서 remote 선택 → remote 화면의 `Test Connection` |
| 완료 상태 | 성공하면 `Reachable`이 표시되고 Repository의 local 상태는 유지된다. |

## 정상 흐름

1. 사용자가 Navigator에서 remote를 선택하고 remote 화면의 `Test Connection`을 누른다.
2. Gallae가 기존 Git 인증 환경으로 configured Fetch URL의 `HEAD`를 읽는다.
3. 성공하면 해당 Remote에 `Reachable`을 표시한다.

## 대안 흐름

- Cancel 또는 Escape를 누르면 진행 중인 Git 프로세스를 중단하고 오류를 표시하지 않는다.
- Remote가 비어 있어 `HEAD`가 없어도 URL을 읽을 수 있으면 성공으로 처리한다.
- 인증·네트워크·경로 오류가 나면 원인을 표시하고 다시 시도할 수 있다.

## 완료 확인

- Test Connection, 진행 상태, Cancel과 결과는 키보드와 VoiceOver로 식별하고 실행할 수 있다.
- 시험 전후 Remote 설정·local ref와 object·HEAD·index·working tree는 바뀌지 않는다.
- 표시할 수 없는 터미널 인증 입력은 기다리지 않는다.
- Push URL과 쓰기 권한은 시험하지 않는다. Remote 이름 변경은 같은 remote 화면의 `Edit…`에서 제공한다.

[사용자 흐름 문서로 돌아가기](../README.md)
