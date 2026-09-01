# UC-47 · Interactive Rebase 계획 편집 및 검토

> 우선순위: P1

| 항목 | 내용 |
| --- | --- |
| 사용자 목표 | commit의 적용 순서와 동작을 정하고 실행 전 최종 계획을 확인한다. |
| 시작 조건 | 기본 Interactive Rebase 계획이 열려 있다. |
| 진입점 | 기본 계획의 동작 메뉴와 순서 이동 동작 |
| 완료 상태 | 유효한 편집 계획이 읽기 전용 검토 단계에 보인다. |

## 정상 흐름

1. 사용자가 각 행에서 `pick`, `reword`, `squash`, `fixup`, `drop` 중 하나를 고른다.
2. drag 또는 위·아래 버튼으로 commit 실행 순서를 바꾼다.
3. Gallae가 편집할 때마다 계획 유효성을 확인한다.
4. 유효한 계획에서 Review Plan을 실행한다.
5. Gallae가 최종 순서·동작·제목·축약 SHA를 읽기 전용으로 보여 준다.
6. Back은 같은 편집 상태로 돌아가고 Close 또는 Escape는 계획을 버리고 시트를 닫는다.

## 대안 흐름

- 앞에 유지되는 commit이 없는 `squash`·`fixup`은 이유를 표시하고 Review Plan을 비활성화한다.
- 모든 commit을 `drop`하면 최소 한 commit을 유지하라고 표시한다.
- 맨 위·맨 아래 행에서 더 이동할 수 없는 방향 버튼은 비활성화한다.
- 검토 단계에서 Back을 선택하면 기존 순서와 동작을 잃지 않는다.

## 완료 확인

- 동작과 순서는 사용자가 정한 그대로 검토 단계에 보인다.
- 편집·검토 중 HEAD·index·working tree와 local 변경은 바뀌지 않는다.
- `reword` 메시지 입력과 실행 위험 확인, 실제 적용은 [UC-48](uc-48-run-interactive-rebase-plan.md)에서 이어진다.
- 동작 메뉴, drag 대체 순서 버튼, 오류, Review·Back·Close는 키보드와 VoiceOver로 식별할 수 있다.

[기본 Interactive Rebase 계획 검사](uc-46-inspect-interactive-rebase-plan.md) · [편집한 Interactive Rebase 계획 실행](uc-48-run-interactive-rebase-plan.md) · [사용자 흐름 문서로 돌아가기](../README.md)
