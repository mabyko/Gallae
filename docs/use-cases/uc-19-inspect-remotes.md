# UC-19 · configured Remote 조회

> 우선순위: P1

| 항목 | 내용 |
| --- | --- |
| 사용자 목표 | 현재 Repository에 설정된 remote 이름, 실제 Fetch·Push 목적지와 그 remote가 내놓은 branch를 확인한다. |
| 시작 조건 | 유효한 Repository Workspace가 열려 있다. |
| 진입점 | Navigator Remotes 섹션에서 remote 선택 |
| 완료 상태 | 선택한 remote의 Fetch·Push URL과 remote-tracking branch 목록을 본문에서 읽고 필요한 값을 복사할 수 있다. |

## 정상 흐름

1. 사용자가 Navigator의 Remotes 섹션에서 remote 이름을 보고 하나를 선택한다.
2. Gallae가 본문을 remote 화면으로 바꾼다. 왼쪽 목록은 그 remote의 remote-tracking branch(`origin/` 접두어 없이, 전체 이름은 도움말)이고, 오른쪽은 이름·Fetch URL·Push URL과 `Fetch`·`Fetch & Prune`·`Test Connection`·`Edit…`·`Remove…`다.
3. 사용자가 URL을 선택해 복사한다.
4. Navigator에서 `History`(⌘2) 같은 목적지나 다른 객체를 고르면 본문이 그쪽으로 바뀐다.

## 대안 흐름

- remote가 없으면 Navigator에 `No Remotes`를 표시하고 선택할 행이 없다.
- Git이 remote를 읽지 못하면 Navigator에 원인을 도움말로 보이고, Refresh가 다시 읽는다.
- remote가 branch를 내놓지 않았거나 아직 Fetch하지 않았으면 목록에 `No Remote Branches`와 Fetch 안내를 보인다.
- remote-tracking branch 행의 문맥 메뉴는 History 행과 같은 `Delete on Remote…`·`Remove Tracking Reference…`를 같은 확인 문구로 제공한다.

## 완료 확인

- 로딩, 없음과 실패를 구분한다.
- 조회 전후 HEAD·index·working tree와 ref가 바뀌지 않는다.
- Remote 이름·URL 편집, 제거, Fetch 연결 시험과 그 remote만의 Fetch는 같은 remote 화면에서 제공한다.

[사용자 흐름 문서로 돌아가기](../README.md)
