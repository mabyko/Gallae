# UC-37 · Reflog 지점에서 복구 branch 생성

> 우선순위: P1

| 항목 | 내용 |
| --- | --- |
| 사용자 목표 | 이전 HEAD가 가리키던 commit을 기존 branch를 옮기지 않고 보존한다. |
| 시작 조건 | Reflog 항목 하나가 선택되어 있다. |
| 진입점 | Reflog 상세의 `Create Recovery Branch…` |
| 완료 상태 | 선택한 commit을 가리키는 새 local branch로 전환되고 Workspace가 갱신된다. |

## 정상 흐름

1. 사용자가 Reflog에서 복구할 항목을 선택한다.
2. 사용자가 `Create Recovery Branch…`를 누른다.
3. Gallae가 selector와 전체 commit SHA를 보여 주고 branch 이름을 받는다.
4. 사용자가 `Create & Switch` 또는 Return으로 실행한다.
5. Gallae가 선택한 전체 SHA에서 새 local branch를 만들고 전환한 뒤 Repository, Changes, History와 Reflog를 다시 읽는다.

## 대안 흐름

- 빈 이름은 실행하지 않는다.
- Cancel 또는 Escape는 Repository를 바꾸지 않는다.
- 유효하지 않거나 이미 존재하는 이름이면 입력과 현재 상태를 유지하고 오류를 표시한다.
- local 변경 때문에 선택한 commit으로 전환할 수 없으면 새 branch를 남기지 않고 기존 branch·index·working tree와 파일을 유지한다.

## 완료 확인

- 기존 local branch ref와 Remote branch는 바뀌지 않는다.
- branch 이름, 시작 commit과 실행 결과를 색 외의 텍스트로 식별할 수 있다.
- 이름 입력, 기본 동작과 취소를 키보드와 VoiceOver로 실행할 수 있다.
- 강제 branch 재생성이나 현재 branch Reset은 수행하지 않는다.

[HEAD Reflog 복구 지점 검사](uc-36-inspect-reflog.md) · [현재 HEAD에서 local branch 생성](uc-14-create-local-branch.md) · [사용자 흐름 문서로 돌아가기](../README.md)
