# UC-09 · hunk 단위 Stage/Unstage

> 우선순위: P1

| 항목 | 내용 |
| --- | --- |
| 사용자 목표 | 한 파일에서 검토한 변경 묶음만 다음 commit에 포함하거나 다시 제외한다. |
| 시작 조건 | 여러 hunk가 있는 수정된 tracked 텍스트 파일의 diff가 열려 있다. |
| 진입점 | staged 또는 working tree diff의 hunk 헤더 |
| 완료 상태 | 선택한 hunk만 반영된 최신 index와 diff가 같은 Workspace에 나타난다. |

## 정상 흐름

1. 사용자가 파일 diff의 hunk를 검토한다.
2. working tree hunk에서 Stage Hunk를 실행한다.
3. Gallae가 선택한 hunk만 index에 반영하고 Repository 상태를 다시 읽는다.
4. staged hunk에서는 Unstage Hunk로 해당 hunk만 index에서 제외할 수 있다.

## 대안 흐름

- 파일 전체를 반영하려면 기존 Stage 또는 Unstage를 사용한다.
- 추적하지 않는 파일, 추가·삭제·rename, binary, 지원하지 않는 인코딩과 충돌 파일에는 hunk 동작을 제공하지 않는다.
- 파일이나 index가 다시 바뀌어 선택한 patch를 적용할 수 없으면 기존 화면 상태를 유지하고 오류를 표시한다.

## 완료 확인

- 선택하지 않은 hunk의 staged 또는 unstaged 상태는 유지된다.
- working tree 파일 내용은 바뀌거나 삭제되지 않는다.
- 성공 뒤 staged와 working tree diff를 다시 읽어 다음 동작을 표시한다.
- 파일 단위 discard는 [UC-11](uc-11-discard-file.md)에서 다루며, 이 흐름은 줄 단위 선택, hunk discard와 충돌 해결을 포함하지 않는다.

[사용자 흐름 문서로 돌아가기](../README.md)
