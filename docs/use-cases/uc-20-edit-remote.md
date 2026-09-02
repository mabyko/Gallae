# UC-20 · configured Remote URL 편집

> 우선순위: P1

| 항목 | 내용 |
| --- | --- |
| 사용자 목표 | 기존 remote의 Fetch·Push 목적지를 안전하게 바꾼다. |
| 시작 조건 | 하나 이상의 configured remote가 있는 Repository Workspace가 열려 있다. |
| 진입점 | Navigator 범위 목록에서 remote 선택 → History 헤더의 `Edit…`, 또는 remote 행 우클릭 메뉴의 `Edit…` |
| 완료 상태 | remote 이름은 유지되고 첫 Fetch·Push URL이 입력한 값으로 바뀐다. |

## 정상 흐름

1. 사용자가 Navigator에서 remote를 선택하고 History 헤더의 `Edit…`을 누른다(remote 행의 우클릭 메뉴도 같다).
2. Gallae가 현재 Fetch·Push URL을 각각 입력란에 표시한다.
3. 사용자가 URL을 수정하고 Save를 누른다.
4. Gallae가 Git 설정만 갱신하고 최신 URL을 History 헤더의 부제와 다음 Edit… 시트에 표시한다.

## 대안 흐름

- URL이 비어 있거나 두 값이 모두 그대로면 Save를 실행하지 않는다.
- Cancel 또는 Escape를 누르면 Git 설정을 바꾸지 않는다.
- 대상 remote가 사라졌거나 Git이 갱신하지 못하면 입력을 유지하고 원인을 표시한다.

## 완료 확인

- 편집과 저장은 키보드와 VoiceOver로 식별하고 실행할 수 있다.
- Save는 remote에 연결하지 않으며 HEAD·index·working tree와 ref를 바꾸지 않는다.
- Remote 이름 변경, 제거(시트 오른쪽 위의 `Remove…`), Fetch 연결 시험(시트 아래의 `Test Connection`)은 모두 같은 Edit… 시트에서 제공한다.

[사용자 흐름 문서로 돌아가기](../README.md)
