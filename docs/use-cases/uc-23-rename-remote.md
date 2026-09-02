# UC-23 · configured Remote 이름 변경

> 우선순위: P1

| 항목 | 내용 |
| --- | --- |
| 사용자 목표 | configured Remote의 이름을 local Tracking 관계를 잃지 않고 바꾼다. |
| 시작 조건 | 하나 이상의 configured Remote가 있는 Repository Workspace가 열려 있다. |
| 진입점 | Navigator 범위 목록에서 remote 선택 → History 헤더의 `Edit…`, 또는 remote 행 우클릭 메뉴의 `Edit…` |
| 완료 상태 | Remote와 관련 Tracking 정보가 새 이름으로 표시되고 local 작업은 유지된다. |

## 정상 흐름

1. 사용자가 Navigator에서 remote를 선택하고 History 헤더의 `Edit…`을 누른다.
2. Name을 바꾸고 필요하면 Fetch·Push URL도 함께 편집한 뒤 Save를 누른다.
3. Gallae가 Remote 설정과 local remote-tracking branch를 새 이름으로 옮긴다.
4. Repository snapshot과 Remotes를 갱신해 새 Tracking 이름을 표시하고, Navigator 선택은 History로 돌아간다.

## 대안 흐름

- 이름이 비어 있거나 바뀐 값이 없으면 Save를 실행하지 않는다.
- Git이 허용하지 않는 이름, 이미 존재하는 이름이나 사라진 Remote이면 입력을 유지하고 원인을 표시한다.
- Cancel 또는 Escape를 누르면 Remote 설정과 ref를 바꾸지 않는다.

## 완료 확인

- Name, Save와 Cancel은 키보드와 VoiceOver로 식별하고 실행할 수 있다.
- 기존 remote-tracking branch와 현재 branch의 Tracking 관계는 새 Remote 이름으로 이동한다.
- HEAD·index·working tree·local branch·commit과 remote Repository는 바뀌지 않는다.
- Save는 Remote에 연결하지 않는다.

[사용자 흐름 문서로 돌아가기](../README.md)
