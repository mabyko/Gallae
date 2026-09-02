# UC-21 · configured Remote 제거

> 우선순위: P1

| 항목 | 내용 |
| --- | --- |
| 사용자 목표 | 더 이상 쓰지 않는 configured remote를 local Repository에서 안전하게 제거한다. |
| 시작 조건 | 하나 이상의 configured remote가 있는 Repository Workspace가 열려 있다. |
| 진입점 | Navigator remote 행의 우클릭 메뉴 `Remove…`, 또는 Edit… 시트 오른쪽 위의 `Remove…` |
| 완료 상태 | 선택한 remote 설정과 연결된 local remote-tracking branch가 제거되고 나머지 Repository 상태는 유지된다. |

## 정상 흐름

1. 사용자가 Navigator의 remote 행을 우클릭해 `Remove…`를 누르거나, History 헤더의 `Edit…`로 연 시트 오른쪽 위의 `Remove…`를 누른다.
2. Gallae가 제거 범위와 삭제되지 않는 항목을 확인 대화상자에 표시한다.
3. 사용자가 제거를 확인한다.
4. Gallae가 선택한 remote 설정과 연결된 local remote-tracking branch를 제거한다.
5. Repository, Remotes와 History를 다시 읽고, Navigator 선택은 History로 돌아간다. 현재 branch가 제거한 remote를 Tracking 중이었다면 Tracking이 사라지고 Publish가 표시된다.

## 대안 흐름

- Cancel 또는 Escape를 누르면 Git 설정과 ref를 바꾸지 않는다.
- 대상 remote가 이미 사라졌거나 Git이 제거하지 못하면 기존 Workspace를 유지하고 원인을 표시한다.
- 제거 뒤 Remotes를 다시 읽지 못하면 실패·재시도 상태를 표시한다.

## 완료 확인

- Remove, 확인과 Cancel은 키보드와 VoiceOver로 식별하고 실행할 수 있다.
- remote Repository와 local branch·commit·HEAD·index·working tree는 삭제하거나 바꾸지 않는다.
- 선택하지 않은 remote 설정과 remote-tracking branch는 유지한다.
- Remote 이름·URL 편집과 Fetch 연결 시험은 같은 Edit… 시트에서 제공한다. Remove는 Fetch 옆 헤더 도구에 두지 않는다.

[사용자 흐름 문서로 돌아가기](../README.md)
