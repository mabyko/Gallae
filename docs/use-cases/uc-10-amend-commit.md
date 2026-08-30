# UC-10 · 최근 Commit Amend

> 우선순위: P1

| 항목 | 내용 |
| --- | --- |
| 사용자 목표 | Stage한 변경과 새 메시지로 최신 commit을 명시적으로 교체한다. |
| 시작 조건 | commit이 하나 이상 있고 staged 변경이 있으며 미해결 충돌이 없는 Repository Workspace가 열려 있다. |
| 진입점 | Changes 하단의 `Amend last commit` 선택 뒤 Amend 버튼 또는 `⌘Return` |
| 완료 상태 | commit 수를 늘리지 않은 새 HEAD와 최신 작업 트리 상태가 같은 Workspace에 반영된다. |

## 정상 흐름

1. 사용자가 staged 변경을 확인하고 제목과 선택적 본문을 입력한다.
2. `Amend last commit`을 선택하고 Amend 버튼이나 `⌘Return`으로 실행한다.
3. Gallae가 현재 index와 입력한 메시지로 최신 commit을 교체하고 Repository 상태를 다시 읽는다.
4. 성공하면 제목·본문·Amend 선택을 비우고 남은 unstaged 변경을 계속 보여 준다.

## 대안 흐름

- 아직 commit이 없거나 staged 변경이 없으면 Amend를 실행할 수 없다.
- 미해결 충돌이 있으면 Amend를 실행할 수 없다.
- Git identity, hook 또는 서명 설정 때문에 실패하면 staged 상태와 입력·Amend 선택을 유지하고 오류를 표시한다.

## 완료 확인

- unstaged 변경은 교체한 commit에 자동으로 포함되지 않는다.
- 성공 뒤 commit 수는 그대로이고 HEAD가 교체된다.
- 사용자의 Git 설정과 hook을 우회하지 않는다.
- 파일 단위 discard는 [UC-11](uc-11-discard-file.md)에서 다루며, 이 흐름은 메시지만 바꾸는 Amend와 충돌 해결을 포함하지 않는다.

[사용자 흐름 문서로 돌아가기](../README.md)
