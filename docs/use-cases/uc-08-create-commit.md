# UC-08 · 일반 Commit 생성

> 우선순위: P1

| 항목 | 내용 |
| --- | --- |
| 사용자 목표 | 검토하고 Stage한 변경을 하나의 commit으로 기록한다. |
| 시작 조건 | staged 변경이 있고 미해결 충돌이 없는 Repository Workspace가 열려 있다. |
| 진입점 | Changes 하단의 Commit 영역 또는 `⌘Return` |
| 완료 상태 | 새 commit과 최신 작업 트리 상태가 같은 Workspace에 반영된다. |

## 정상 흐름

1. 사용자가 staged 변경을 확인하고 필수 제목과 선택적 본문을 입력한다.
2. Commit 버튼이나 `⌘Return`으로 실행한다.
3. Gallae가 현재 index만 기록하고 Repository 상태를 다시 읽는다.
4. 성공하면 제목과 본문 입력을 비우고 남은 unstaged 변경을 계속 보여 준다.

## 대안 흐름

- 제목이 비어 있거나 staged 변경이 없으면 Commit을 실행할 수 없다.
- 미해결 충돌이 있으면 Commit을 실행할 수 없다.
- 사용자의 Git identity, hook 또는 서명 설정 때문에 Git이 실패하면 기존 staged 상태와 입력한 제목·본문을 유지하고 오류를 표시한다.

## 완료 확인

- unstaged 변경은 새 commit에 자동으로 포함되지 않는다.
- 성공 뒤 최신 HEAD, 변경 목록과 diff를 다시 읽는다.
- 본문은 입력한 줄바꿈을 포함해 제목과 분리된 commit 문단으로 기록된다.
- 최근 Commit Amend는 [UC-10](uc-10-amend-commit.md), 파일 단위 discard는 [UC-11](uc-11-discard-file.md)에서 다루며, 이 흐름은 충돌 해결을 포함하지 않는다.

[사용자 흐름 문서로 돌아가기](../README.md)
