# UC-48 · 편집한 Interactive Rebase 계획 실행

> 우선순위: P1

| 항목 | 내용 |
| --- | --- |
| 사용자 목표 | 검토한 순서와 동작으로 현재 local branch의 History를 다시 쓴다. |
| 시작 조건 | 유효한 Interactive Rebase 계획의 검토 단계가 열려 있고 Repository가 깨끗하다. |
| 진입점 | 검토 단계의 `Run Rebase…` 버튼 |
| 완료 상태 | 계획이 적용된 새 History 또는 해결 가능한 진행 중인 Rebase 상태가 보인다. |

## 정상 흐름

1. 사용자가 각 `reword` 행에 새 commit 메시지를 입력한다.
2. Gallae가 빈 메시지와 local 변경을 확인하고 실행 버튼을 활성화한다.
3. 사용자가 현재 local branch의 commit ID가 바뀌며 강제 Push는 실행하지 않는다는 경고를 확인한다.
4. Gallae가 attached branch, 깨끗한 working tree, 진행 중인 작업 없음, 대상 범위와 계획을 다시 검사한다.
5. Git이 위에서 아래 순서로 계획을 적용한다.
6. Gallae가 실제 Repository 상태와 History를 다시 읽고 시트를 닫는다.

## 대안 흐름

- `reword` 메시지가 비었거나 local 변경이 있으면 이유를 표시하고 실행하지 않는다.
- 실행 전에 branch·HEAD·계획이 바뀌었으면 Repository를 변경하지 않고 오류를 표시한다.
- 충돌이 나면 시트를 닫고 진행 중인 Rebase와 충돌 파일을 Workspace에 표시한다. 사용자는 기존 Resolve·Continue·Abort 흐름을 사용한다.
- 실행이 실패하면 실제 Repository 상태를 다시 읽고 같은 검토 단계에 오류를 표시한다.
- 실행 중 Cancel은 Git 프로세스를 중단하고 Rebase를 Abort한 뒤 원래 branch·HEAD와 깨끗한 working tree가 복원됐는지 확인한다.
- 실행 전 확인을 취소하거나 검토 시트를 닫으면 계획을 버리고 Repository를 바꾸지 않는다.

## 완료 확인

- `pick`, `reword`, `squash`, `fixup`, `drop`과 사용자가 정한 순서가 적용된다.
- 다른 local ref는 이동하지 않으며 Gallae는 Push 또는 강제 Push를 실행하지 않는다.
- 성공·충돌·실패·취소 뒤 실제 Repository 상태를 숨기지 않는다.
- 메시지 입력, 실행 확인, 진행 상태와 Cancel은 키보드와 VoiceOver로 식별할 수 있다.

[Interactive Rebase 계획 편집 및 검토](uc-47-edit-interactive-rebase-plan.md) · [진행 중인 Merge·Rebase 계속 또는 중단](uc-45-continue-or-abort-operation.md) · [사용자 흐름 문서로 돌아가기](../README.md)
