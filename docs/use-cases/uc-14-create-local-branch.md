# UC-14 · 현재 HEAD에서 local branch 생성

> 우선순위: P1

| 항목 | 내용 |
| --- | --- |
| 사용자 목표 | 현재 작업 지점에서 새 local branch를 만들고 바로 전환한다. |
| 시작 조건 | Repository Workspace가 열려 있다. |
| 진입점 | Navigator Branches 섹션의 `+`, 또는 문맥 바 branch 메뉴의 `New Branch…` |
| 완료 상태 | 새 branch의 HEAD, Changes와 History가 같은 Workspace에 표시된다. |

## 정상 흐름

1. 사용자가 Navigator Branches 섹션의 `+` 또는 branch 메뉴의 `New Branch…`를 누른다.
2. Gallae가 New Branch 시트를 열고 현재 HEAD를 시작점으로 보여 준다.
3. 사용자가 새 branch 이름을 입력한다.
4. 사용자가 Create 또는 Return으로 생성한다.
5. Gallae가 branch를 만들고 전환한 뒤 Repository, Changes와 History를 다시 읽는다.

## 대안 흐름

- detached HEAD와 아직 commit이 없는 branch에서도 현재 HEAD를 시작점으로 생성할 수 있다.
- 빈 이름은 Create를 활성화하지 않는다.
- 유효하지 않은 이름이나 이미 존재하는 branch이면 생성하지 않고 현재 branch·index·working tree와 입력값을 유지한 채 오류를 표시한다.

## 완료 확인

- 시작점, 이름 입력과 Create 동작은 키보드와 VoiceOver로 식별하고 실행할 수 있다.
- 기존 branch를 강제로 다시 만들거나 local 변경을 버리지 않는다.
- 이 선택기에서는 임의의 시작점을 고르지 않는다. Reflog 시작점은 별도 복구 흐름을 사용하고, remote 게시와 upstream 설정은 branch 생성 뒤 Publish에서 수행한다.

[Reflog 지점에서 복구 branch 생성](uc-37-create-recovery-branch.md) · [사용자 흐름 문서로 돌아가기](../README.md)
