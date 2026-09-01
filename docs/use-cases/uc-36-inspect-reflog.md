# UC-36 · HEAD Reflog 복구 지점 검사

> 우선순위: P1

| 항목 | 내용 |
| --- | --- |
| 사용자 목표 | branch 전환이나 Reset 전 HEAD가 가리키던 commit을 찾는다. |
| 시작 조건 | commit이 하나 이상 있는 Repository Workspace가 열려 있다. |
| 진입점 | Repository 헤더의 `Reflog` |
| 완료 상태 | 선택한 HEAD 이동 기록의 action, 기록자·시각과 전체 commit SHA가 표시된다. |

## 정상 흐름

1. 사용자가 Repository 헤더에서 `Reflog`를 선택한다.
2. Gallae가 현재 Repository의 HEAD Reflog를 최신순으로 최대 100개 읽는다.
3. Gallae가 최신 항목을 선택하고 selector, action, 기록자·시각과 전체 commit SHA를 표시한다.
4. 사용자는 방향키나 포인터로 다른 항목을 선택해 이전 HEAD 지점을 확인한다.

## 대안 흐름

- 아직 기록이 없으면 오류 대신 `No Recovery Points` 빈 상태를 표시한다.
- Reflog를 읽지 못하면 원인과 `Try Again`을 같은 화면에 표시한다.
- Git 유지 관리로 오래된 항목이 만료됐으면 현재 남아 있는 항목만 표시한다.

## 완료 확인

- Reflog 진입과 항목 선택은 Repository·HEAD·index·working tree를 바꾸지 않는다.
- 목록은 selector, action, 상대 시각과 축약 SHA를 색 외의 텍스트로 식별할 수 있다.
- 상세에는 전체 SHA, 기록자 이메일과 정확한 기록 시각이 표시된다.
- 항목 검사는 Repository를 바꾸지 않으며, 복구는 명시적인 별도 동작으로 시작한다.

[Reflog 지점에서 복구 branch 생성](uc-37-create-recovery-branch.md) · [hard Reset](uc-35-hard-reset-current-branch.md) · [History 검사](uc-12-inspect-history.md) · [사용자 흐름 문서로 돌아가기](../README.md)
