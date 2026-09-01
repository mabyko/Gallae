# UC-19 · configured Remote 조회

> 우선순위: P1

| 항목 | 내용 |
| --- | --- |
| 사용자 목표 | 현재 Repository에 설정된 remote 이름과 실제 Fetch·Push 목적지를 확인한다. |
| 시작 조건 | 유효한 Repository Workspace가 열려 있다. |
| 진입점 | Repository Workspace 상단의 Remotes |
| 완료 상태 | configured remote 이름과 Fetch·Push URL을 조회하고 필요한 값을 복사할 수 있다. |

## 정상 흐름

1. 사용자가 Remotes를 누른다.
2. Gallae가 configured remote 이름을 정렬해 읽고 각 remote의 Fetch·Push URL을 조회한다.
3. 사용자가 URL을 선택해 복사한다.
4. Close 또는 Escape로 Repository Workspace로 돌아간다.

## 대안 흐름

- remote가 없으면 설정된 Remote가 없다는 빈 상태를 표시한다.
- Git이 remote를 읽지 못하면 원인을 표시하고 같은 sheet에서 다시 시도할 수 있다.

## 완료 확인

- 로딩, 없음과 실패·재시도를 구분한다.
- 조회 전후 HEAD·index·working tree와 ref가 바뀌지 않는다.
- Remote 이름·URL 편집, 제거와 Fetch 연결 시험은 같은 Remotes 목록에서 제공한다.

[사용자 흐름 문서로 돌아가기](../README.md)
