# UC-46 · 기본 Interactive Rebase 계획 검사

> 우선순위: P1

| 항목 | 내용 |
| --- | --- |
| 사용자 목표 | History를 다시 쓰기 전에 대상 commit과 기본 적용 순서를 확인한다. |
| 시작 조건 | 진행 중인 Git 작업이 없는 attached local branch의 History가 열려 있다. |
| 진입점 | 선택한 commit 상세의 `Rebase Plan…` 버튼 |
| 완료 상태 | 선택한 commit부터 현재 HEAD까지의 조회 전용 `pick` 계획이 보인다. |

## 정상 흐름

1. 사용자가 현재 branch에 포함된 commit을 선택하고 `Rebase Plan…`을 연다.
2. Gallae가 선택한 commit이 실제 현재 HEAD의 ancestor인지 다시 확인한다.
3. 오래된 commit부터 `pick`, 제목과 축약 SHA를 한 행에 표시한다.
4. 기본 선형 계획에서 merge commit이 제외된다는 점과 Repository가 바뀌지 않는다는 점을 함께 표시한다.
5. 사용자가 Close 또는 Escape로 미리보기를 닫는다.

## 대안 흐름

- 계획을 읽는 동안 로딩 상태를 표시한다.
- 범위에 `pick`할 일반 commit이 없으면 오류와 구분한 빈 상태를 표시한다.
- 선택한 commit이 현재 branch에 없거나 branch·작업 상태가 바뀌면 명령을 실행하지 않고 이유를 표시한다.
- Git이 계획을 읽지 못하면 같은 화면에서 다시 시도할 수 있다.
- 미리보기가 닫히면 진행 중인 읽기를 취소한다.

## 완료 확인

- commit은 선택한 범위의 오래된 순서로 보인다.
- HEAD·index·working tree와 local 변경은 전혀 바뀌지 않는다.
- 기본 계획 검사 뒤 순서와 동작 편집은 [UC-47](uc-47-edit-interactive-rebase-plan.md), 실제 실행은 [UC-48](uc-48-run-interactive-rebase-plan.md)에서 이어진다.
- 버튼, 계획 행, 다시 시도와 닫기는 키보드와 VoiceOver로 식별할 수 있다.

[Repository commit History 검사](uc-12-inspect-history.md) · [진행 중인 Merge·Rebase 계속 또는 중단](uc-45-continue-or-abort-operation.md) · [Interactive Rebase 계획 편집 및 검토](uc-47-edit-interactive-rebase-plan.md) · [편집한 Interactive Rebase 계획 실행](uc-48-run-interactive-rebase-plan.md) · [사용자 흐름 문서로 돌아가기](../README.md)
