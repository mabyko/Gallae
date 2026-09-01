# UC-13 · 기존 local branch 전환

> 우선순위: P1

| 항목 | 내용 |
| --- | --- |
| 사용자 목표 | 기존 local branch를 찾아 안전하게 전환한다. |
| 시작 조건 | Repository Workspace가 열려 있다. |
| 진입점 | Repository 헤더의 현재 branch |
| 완료 상태 | 선택한 branch의 HEAD, Changes와 History가 같은 Workspace에 표시된다. |

## 정상 흐름

1. 사용자가 Repository 헤더의 현재 branch를 누른다.
2. Gallae가 기존 local branch를 읽고 현재 branch를 표시한다.
3. 사용자가 이름으로 목록을 좁히고 branch를 선택한다.
4. 사용자가 `Switch` 또는 Return으로 전환한다.
5. Gallae가 안전한 Git switch를 실행하고 Repository, Changes와 History를 다시 읽는다.

## 대안 흐름

- detached HEAD에서는 현재 표시 없이 local branch를 선택할 수 있다.
- 검색 결과가 없으면 별도 빈 상태와 `Clear Search`를 표시한다.
- branch 목록을 읽지 못하면 같은 선택기에서 다시 시도할 수 있다.
- 선택한 branch가 사라졌거나 local 변경과 충돌하면 전환하지 않고 기존 branch·index·working tree와 Workspace를 유지한다.

## 완료 확인

- 현재 branch와 선택 동작은 색 외의 텍스트와 VoiceOver 이름으로 식별할 수 있다.
- 전환은 force·merge 옵션을 쓰거나 local 변경을 버리지 않는다.
- branch 생성, remote-tracking branch 전환과 stash 보조 동작은 포함하지 않는다.

[사용자 흐름 문서로 돌아가기](../README.md)
