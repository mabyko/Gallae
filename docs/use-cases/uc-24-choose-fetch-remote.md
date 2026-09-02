# UC-24 · Fetch 대상 Remote 선택

> 우선순위: P1

| 항목 | 내용 |
| --- | --- |
| 사용자 목표 | 여러 Remote 중 가져올 대상을 직접 고른다. |
| 시작 조건 | Remote가 둘 이상 설정된 Repository Workspace가 열려 있다. |
| 진입점 | Repository Workspace 상단의 Fetch, 또는 Navigator remote 행의 문맥 메뉴·remote 범위 History 헤더의 `Fetch`(선택 없이 그 remote에서 바로) |
| 완료 상태 | 선택한 Remote의 최신 remote-tracking ref와 Repository 상태가 같은 Workspace에 표시된다. |

## 정상 흐름

1. 사용자가 Fetch를 누른다.
2. Gallae가 configured Remote 이름을 정렬해 선택 sheet에 표시한다.
3. 사용자가 Remote 하나를 고르고 Fetch를 실행한다.
4. Gallae가 선택한 Remote 이름을 명시해 변경을 가져오며 진행 상태를 표시한다.
5. 성공하면 Repository, Changes와 History를 다시 읽는다.

## 대안 흐름

- Remote가 하나뿐이면 선택 단계를 건너뛰고 바로 Fetch한다.
- Cancel 또는 Escape는 Fetch를 시작하지 않고 Repository를 그대로 둔다.
- 선택한 Remote가 사라졌거나 Fetch에 실패하면 Git 오류를 표시하고 기존 Workspace를 유지한다.
- 실행 중 Cancel 또는 Escape는 Fetch를 중단하고 같은 Workspace로 돌아간다.

## 완료 확인

- Remote Picker, Fetch와 Cancel은 키보드와 VoiceOver로 식별하고 실행할 수 있다.
- 선택한 Remote의 configured refspec과 remote-tracking ref만 갱신한다.
- 선택하지 않은 Remote ref와 HEAD·index·working tree·local 수정은 바꾸지 않는다.
- 명시적인 prune은 [UC-25](uc-25-fetch-and-prune.md), Git 설정이 고르는 Remote의 주기 실행은 [UC-26](uc-26-fetch-automatically.md)으로 이어진다.

[사용자 흐름 문서로 돌아가기](../README.md)
