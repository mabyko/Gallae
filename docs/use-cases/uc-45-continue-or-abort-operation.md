# UC-45 · 진행 중인 Merge·Rebase 계속 또는 중단

> 우선순위: P1

| 항목 | 내용 |
| --- | --- |
| 사용자 목표 | 충돌을 해결한 Git 작업을 마치거나 안전하게 중단한다. |
| 시작 조건 | Merge 또는 Rebase가 진행 중인 Repository Workspace가 열려 있다. |
| 진입점 | Repository Workspace 상단의 Continue·Abort 버튼 |
| 완료 상태 | 작업을 마친 실제 Repository 상태 또는 Abort 뒤 복원된 상태가 보인다. |

## 정상 흐름

1. Gallae가 작업 종류와 남은 충돌 수를 표시한다.
2. 충돌이 모두 해결되면 Continue를 활성화한다.
3. 사용자가 Continue를 실행하면 Gallae가 작업 상태를 다시 확인하고 Git의 기본 메시지로 Merge 또는 Rebase를 계속한다.
4. 사용자가 Abort를 선택하면 Gallae가 해결 중 만든 변경이 사라질 수 있음을 알리고 확인을 받는다.
5. 작업 뒤 Gallae가 Repository를 다시 읽어 최신 HEAD, Changes와 진행 상태를 보여 준다.

## 대안 흐름

- 충돌이 남아 있으면 Continue를 비활성화하고 Abort는 유지한다.
- 확인 화면에서 Cancel을 선택하면 Repository를 바꾸지 않는다.
- 실행 직전에 작업이 끝났거나 종류가 바뀌었으면 명령을 실행하지 않고 최신 상태를 보여 준다.
- Rebase Continue가 다음 충돌에서 멈추면 새 충돌과 진행 중인 Rebase 상태를 보여 준다.
- Git 명령이 실패하면 실제 Repository를 다시 읽어 부분적으로 바뀐 상태도 숨기지 않고 오류를 표시한다.

## 완료 확인

- Continue는 별도 편집기를 열지 않는다.
- Abort는 확인 전에는 실행되지 않는다.
- 성공하면 Merge commit 관계 또는 Rebase 뒤 commit 관계가 실제 Git 결과와 일치한다.
- Rebase Skip은 제공하지 않는다.
- Continue·Abort, 확인과 취소는 키보드와 VoiceOver로 구분해 실행할 수 있다.

[진행 중인 Merge·Rebase 상태 검사](uc-44-inspect-in-progress-operation.md) · [기본 Interactive Rebase 계획 검사](uc-46-inspect-interactive-rebase-plan.md) · [사용자 흐름 문서로 돌아가기](../README.md)
