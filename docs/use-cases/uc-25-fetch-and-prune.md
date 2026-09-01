# UC-25 · 선택한 Remote Fetch & Prune

> 우선순위: P1

| 항목 | 내용 |
| --- | --- |
| 사용자 목표 | Remote의 최신 ref를 가져오면서 더는 존재하지 않는 local tracking ref를 정리한다. |
| 시작 조건 | Remote가 설정된 Repository Workspace가 열려 있다. |
| 진입점 | Repository Workspace 상단 Fetch 메뉴의 Fetch & Prune |
| 완료 상태 | 선택한 Remote의 최신 ref만 남고 Repository 상태가 같은 Workspace에 표시된다. |

## 정상 흐름

1. 사용자가 Fetch 메뉴를 열고 Fetch & Prune을 고른다.
2. Remote가 둘 이상이면 Gallae가 정렬된 이름을 sheet에 표시하고 사용자가 하나를 고른다.
3. Gallae가 선택한 Remote에서 변경을 가져오고 configured refspec 기준의 stale local tracking ref를 정리한다.
4. 성공하면 Repository, Changes와 History를 다시 읽는다.
5. local branch·HEAD·index·working tree와 local 수정은 그대로 유지된다.

## 대안 흐름

- Remote가 하나뿐이면 선택 단계를 건너뛰고 바로 실행한다.
- Remote가 없으면 설정되지 않았다는 오류를 표시한다.
- Remote 선택 sheet의 Cancel 또는 Escape는 실행하지 않고 Repository를 그대로 둔다.
- 실행 중 Cancel 또는 Escape는 Fetch를 중단하고 같은 Workspace로 돌아간다.
- 인증·네트워크 오류나 선택한 Remote가 사라지면 Git 오류를 표시하고 다시 시도할 수 있다.

## 완료 확인

- Fetch & Prune, Remote Picker와 Cancel은 키보드와 VoiceOver로 식별하고 실행할 수 있다.
- 선택한 Remote의 configured refspec만 fetch하고 prune하며 선택하지 않은 Remote ref는 바꾸지 않는다.
- 기본 Fetch에는 `--prune`을 강제하지 않고 사용자의 기존 Git 설정을 따른다.
- local branch·HEAD·index·working tree와 local 수정은 바꾸지 않는다.
- 자동 Fetch는 [UC-26](uc-26-fetch-automatically.md)에서 별도로 켜며 `--prune`을 강제하지 않는다.

[사용자 흐름 문서로 돌아가기](../README.md)
