# UC-29 · Stash 적용

> 우선순위: P1

| 항목 | 내용 |
| --- | --- |
| 사용자 목표 | 보관한 작업을 현재 Repository에 복원하면서 Stash를 안전하게 남긴다. |
| 시작 조건 | Repository Workspace에 적용할 Stash가 선택되어 있다. |
| 진입점 | 선택한 Stash 상세의 `Apply` |
| 완료 상태 | 저장된 staged·unstaged 변경과 함께 저장된 untracked 파일이 복원되고 Stash는 목록에 남는다. |

## 정상 흐름

1. 사용자가 Stash와 저장된 변경을 검토한다.
2. 사용자가 `Apply`를 실행한다.
3. Gallae가 중복 실행을 막고 진행 상태를 표시한다.
4. Gallae가 선택한 Stash ID를 `--index`로 적용한다.
5. Gallae가 Repository와 Stash 목록을 다시 읽고 같은 Stash를 선택한 채 복원된 Changes를 표시한다.

## 대안 흐름

- 현재 변경과 겹쳐 Git이 적용을 거부하면 기존 변경과 Stash를 유지하고 오류를 표시한다.
- 새 HEAD와 충돌하면 HEAD와 Stash를 유지하고 Repository를 다시 읽어 conflict 파일을 Changes에 표시한다.
- 선택한 Stash가 더 이상 존재하지 않거나 Git 실행이 실패하면 현재 Repository 상태를 다시 읽고 오류를 표시한다.

## 완료 확인

- 성공해도 Stash 항목은 삭제되지 않으며 HEAD와 commit은 바뀌지 않는다.
- 저장 당시의 staged·unstaged 상태와 함께 저장된 untracked 파일이 복원된다.
- 실패 뒤에도 강제로 덮어쓰거나 Stash를 삭제하지 않고 Git이 남긴 정확한 현재 상태를 보여 준다.
- Stash 삭제는 [UC-30](uc-30-delete-stash.md)에서 다룬다.

[사용자 흐름 문서로 돌아가기](../README.md)
