# UC-16 · configured upstream fast-forward Pull

> 우선순위: P1

| 항목 | 내용 |
| --- | --- |
| 사용자 목표 | 현재 branch를 upstream의 최신 commit으로 안전하게 갱신한다. |
| 시작 조건 | upstream이 설정된 local branch의 Repository Workspace가 열려 있다. |
| 진입점 | Repository Workspace 상단의 Pull |
| 완료 상태 | 현재 branch가 upstream으로 fast-forward되고 최신 Repository 상태가 같은 Workspace에 표시된다. |

## 정상 흐름

1. 사용자가 Pull을 누른다.
2. Gallae가 configured upstream을 Fetch하고 fast-forward 가능 여부를 확인한다.
3. fast-forward가 가능하면 현재 branch와 working tree를 upstream commit으로 갱신한다.
4. Repository, Changes와 History를 다시 읽고 최신 ahead/behind를 표시하며, 캡슐이 가져온 commit 수(`Pulled N commits`)를 잠깐 보인다. Pull은 working tree를 쓰므로 실행 중에는 Fetch·Push와 Stage·Commit도 기다린다.

## 대안 흐름

- 사용자가 Cancel 또는 Escape를 누르면 실행 중인 Pull을 중단하고 실제 Repository 상태를 유지한다.
- upstream이 없으면 설정되지 않았다는 오류를 표시한다.
- local과 upstream history가 갈라졌으면 merge하거나 rebase하지 않고 오류를 표시한다.
- remote 변경과 겹치는 local 수정, 인증 또는 네트워크 오류가 있으면 현재 HEAD·index·working tree를 유지한다.
- Pull의 Fetch 단계에서 remote-tracking ref가 갱신됐으면 최신 ahead/behind를 다시 읽는다.
- 다른 Repository를 여는 작업이 시작됐다면 이전 Pull의 완료·오류가 새 Workspace나 진행 중인 읽기 상태를 바꾸지 않는다.

## 완료 확인

- Pull과 Cancel은 키보드와 VoiceOver로 식별하고 실행할 수 있다.
- 겹치지 않는 local working tree 수정은 보존한다.
- merge/rebase 방식 선택, remote 선택, 강제 갱신과 자동 Pull은 포함하지 않는다.

[사용자 흐름 문서로 돌아가기](../README.md)
