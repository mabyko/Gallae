# UC-17 · 현재 branch Push

> 우선순위: P1

| 항목 | 내용 |
| --- | --- |
| 사용자 목표 | 현재 branch의 local commit을 기존 Git 설정에 따라 안전하게 게시한다. |
| 시작 조건 | upstream이 설정된 local branch가 remote보다 앞선 Repository Workspace가 열려 있다. |
| 진입점 | Repository Workspace 상단의 Push |
| 완료 상태 | 현재 branch의 commit이 기본 push 목적지에 게시되고 최신 ahead/behind가 표시된다. |

## 정상 흐름

1. 사용자가 Push를 누른다.
2. Gallae가 기존 `push.default`와 remote 설정이 고르는 목적지에 현재 branch를 보낸다.
3. Push가 끝나면 Repository, Changes와 History를 다시 읽는다.
4. 현재 HEAD·index·working tree와 local 수정은 그대로 유지된다.

## 대안 흐름

- 사용자가 Cancel 또는 Escape를 누르면 실행 중인 Push를 중단하고 실제 Repository 상태를 유지한다.
- upstream이 없으면 같은 동작이 Publish로 바뀌며 UC-18 흐름을 사용한다.
- non-fast-forward, remote hook 거부, 인증 또는 네트워크 오류가 발생하면 force하지 않고 Git의 원인을 표시한다.
- 터미널 입력은 기다리지 않으며 기존 credential helper와 SSH 환경은 그대로 사용한다.

## 완료 확인

- Push와 Cancel은 키보드와 VoiceOver로 식별하고 실행할 수 있다.
- Push는 force, upstream 생성 또는 명시적인 refspec 없이 현재 branch만 처리한다.
- Push 자체에는 `--set-upstream`을 사용하지 않는다. force·force-with-lease, tag·여러 ref 게시와 remote branch 삭제도 포함하지 않는다.

[사용자 흐름 문서로 돌아가기](../README.md)
