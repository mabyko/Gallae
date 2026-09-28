# UC-44 · 진행 중인 Merge·Rebase·Cherry-pick 상태 검사

> 우선순위: P1

| 항목 | 내용 |
| --- | --- |
| 사용자 목표 | 충돌 해결 뒤 어떤 Git 작업을 마쳐야 하는지 확인한다. |
| 시작 조건 | Merge·Rebase·Cherry-pick 중 하나가 진행 중인 Repository Workspace가 열려 있다. |
| 진입점 | Repository Workspace 상단 상태 영역 |
| 완료 상태 | 작업 종류, 남은 충돌 수와 Continue·Abort 가능 경로가 보인다. |

## 정상 흐름

1. Gallae가 현재 worktree의 Git 상태 경로에서 진행 중인 Merge·Rebase·Cherry-pick을 찾는다. 터미널에서 시작한 작업도 포함한다.
2. Gallae가 Repository의 unmerged 파일 수를 계산한다.
3. Workspace 상단에 작업 종류와 남은 충돌 수를 표시한다.
4. 충돌이 남아 있으면 해결 뒤 Continue할 수 있고 Abort도 가능하다고 알린다.
5. 마지막 충돌을 해결하면 같은 영역을 `Ready to Continue`로 갱신한다.

## 대안 흐름

- 진행 중인 작업이 없으면 별도 상태 영역을 표시하지 않는다.
- linked worktree에서는 해당 worktree의 Git 상태 경로를 사용한다.
- Merge·Rebase·Cherry-pick 표식이 검사 도중 사라지면 다음 Repository 새로고침에서 상태 영역도 사라진다.
- Cherry-pick에는 현재 단계를 건너뛰는 `Skip…`도 표시한다. 적용할 staged 변경이 없는 상태에서 Continue하면 Skip·Abort를 안내한다.
- 상태 검사는 Repository의 HEAD·index·working tree를 바꾸지 않는다.

## 완료 확인

- Merge·Rebase·Cherry-pick을 서로 구분한다.
- 남은 충돌 수와 Continue 가능 여부를 색 외의 텍스트로도 식별한다.
- Continue와 Abort 버튼은 상태 설명과 별개로 키보드와 VoiceOver에서 식별할 수 있다. 실제 실행은 [UC-45](uc-45-continue-or-abort-operation.md)에서 다룬다.

[현재 working tree 내용으로 충돌 해결](uc-43-mark-conflict-resolved.md) · [진행 중인 작업 계속·건너뛰기·중단](uc-45-continue-or-abort-operation.md) · [사용자 흐름 문서로 돌아가기](../README.md)
