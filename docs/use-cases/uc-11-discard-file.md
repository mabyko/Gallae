# UC-11 · tracked 파일의 unstaged 변경 Discard

> 우선순위: P1

| 항목 | 내용 |
| --- | --- |
| 사용자 목표 | 선택한 파일에서 commit에 포함하지 않을 unstaged 변경을 안전하게 되돌린다. |
| 시작 조건 | 수정·타입 변경·삭제된 tracked 파일의 unstaged diff가 열려 있다. |
| 진입점 | 선택한 파일의 diff 헤더에 있는 `Discard…` |
| 완료 상태 | 선택한 파일의 working tree와 최신 Repository 상태가 같은 Workspace에 반영된다. |

## 정상 흐름

1. 사용자가 선택한 파일과 unstaged diff를 검토한다.
2. `Discard…`를 실행하고 되돌릴 내용과 최근 Discard 복구의 지원 범위를 확인한다.
3. 사용자가 `Discard Changes`를 확정한다.
4. Gallae가 파일의 working tree를 index 상태로 되돌리고 Repository 상태를 다시 읽는다.

## 대안 흐름

- 파일에 staged 변경도 있으면 staged 내용은 유지하고 그 이후의 unstaged 변경만 되돌린다.
- staged 변경이 없으면 파일은 마지막 commit 상태로 돌아간다.
- 사용자가 Cancel을 선택하면 파일과 화면을 바꾸지 않는다.
- Git 명령이 실패하면 기존 화면을 유지하고 오류를 표시한다.
- 충돌·untracked·rename 파일에는 Discard를 제공하지 않는다.
- 기존 일반 파일이 16 MiB 이하이고 index 버전도 지원 범위 안이면 최근 한 번의 Discard를 앱 실행 중 복구할 수 있다. 삭제된 파일·심볼릭 링크·큰 파일은 기존 Discard만 제공하며 복구를 약속하지 않는다.
- 지원 대상의 복구 사본을 안전하게 읽을 수 없으면 Discard를 시작하지 않는다.

## 완료 확인

- 선택하지 않은 파일과 index는 바뀌지 않는다.
- 성공 뒤 변경 목록과 diff를 다시 읽는다.
- 복구 가능한 최근 작업은 Workspace의 `Restore Last Discard`로 되돌린다. 이후 파일·HEAD·해당 파일의 index가 바뀌면 덮어쓰지 않는다. 상세 조건은 [UC-51](uc-51-restore-last-discard.md)을 따른다.
- 이 흐름은 untracked 파일 삭제, rename·hunk discard와 충돌 해결을 포함하지 않는다.

[사용자 흐름 문서로 돌아가기](../README.md)
