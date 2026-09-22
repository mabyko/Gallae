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
   - 단, `push.default`가 기본값 또는 `simple`이고 Push와 upstream의 remote가 같지만 branch 이름이 다르면, 해당 실행에만 `push.default=upstream`을 적용한다. Publish에서 지정한 이름을 계속 사용하며 저장소 설정 파일은 바꾸지 않는다. 다른 Push 모드, 별도 Push remote와 명시적인 remote refspec은 그대로 따른다.
3. Push가 끝나면 Repository, Changes와 History를 다시 읽고, 캡슐이 보낸 commit 수(`Pushed N commits`)를 잠깐 보인다. 실행 중에는 툴바 Push 아이콘·창 제목 subtitle·캡슐이 진행을 보이고 Fetch·Pull과 branch 전환만 기다린다. Stage·Commit·조회는 계속 쓸 수 있다.
4. 현재 HEAD·index·working tree와 local 수정은 그대로 유지된다.

## 대안 흐름

- 사용자가 Cancel 또는 Escape를 누르면 실행 중인 Push를 중단하고 실제 Repository 상태를 유지한다.
- upstream이 없으면 같은 동작이 Publish로 바뀌며 UC-18 흐름을 사용한다.
- non-fast-forward, remote hook 거부, 인증 또는 네트워크 오류가 발생하면 force하지 않고 Git의 원인을 표시한다.
- 터미널 입력은 기다리지 않으며 기존 credential helper와 SSH 환경은 그대로 사용한다.

## 이번 Push의 목적지 지정: Push to…

- 툴바 Push 옆 메뉴, Repository 메뉴의 Push to…, History 커밋 행의 Push to…에서 연다. History에서는 선택한 커밋이 출발점이며, 현재 checkout을 바꾸지 않는다.
- Source에 local branch, remote-tracking branch, tag 또는 commit을 지정하고 Remote와 Branch Name을 고른다. 새 이름을 입력하면 새 remote branch를 만들 수 있다. detached HEAD에서도 사용할 수 있다.
- Review Push는 선택한 remote를 fetch하고 실제 Push URL의 대상 branch와 비교한다. 확인 화면에 보낼 SHA, 목적지, outgoing commit 수와 최근 100개 commit 제목을 표시한다. 이 숫자는 upstream이 아닌 선택한 목적지를 기준으로 한다.
- 변경 사항이 없으면 Push를 비활성화한다. 대상에만 있는 commit이 있으면 fast-forward가 불가능하다고 안내하고 Push를 비활성화한다. 이 경우 필요한 이력 통합은 별도로 진행한다.
- Push to `<remote>/<branch>`를 눌러야 원격에 반영한다. 검토한 SHA를 고정하여 이후 Source branch에 생긴 commit이 함께 나가지 않게 한다. 실행 직전에 Push URL과 대상 commit을 다시 확인하며 바뀌었으면 재검토를 요구한다. 원격의 최종 non-fast-forward 거부도 그대로 따른다.
- `--set-upstream`을 사용하지 않는다. 기존 tracking과 다음 일반 Push의 목적지는 유지하며, upstream이 없던 branch에도 tracking을 새로 만들지 않는다. 성공 캡슐은 `Pushed to origin/release`처럼 실제 목적지를 표시한다.
- 한 branch만 보낸다. 이 실행에서는 `remote.<name>.mirror`와 `push.followTags`를 끄고 명시적인 refspec을 사용한다. 여러 Push URL이 설정된 remote는 대상별 검토가 필요하므로 지원하지 않는다. Git 설정 파일은 바꾸지 않는다.
- 입력 변경 시 검토 결과를 지운다. Review Again으로 원격 상태를 다시 확인할 수 있다. 미리보기는 Cancel·Escape·화면 닫기로 취소할 수 있으며 원격 branch를 변경하지 않는다. 실제 Push는 기존 진행 표시와 Cancel Push를 사용한다.

예: `main`은 `origin/main`을 계속 추적하면서, Source `refs/remotes/origin/main`을 `origin`의 `release`로 보낼 수 있다. 최신 개발 commit보다 이전 시점이 필요하면 History에서 검증한 commit을 선택한다. 해당 commit까지의 이력이 함께 반영되며 특정 변경만 골라 반영하는 기능은 아니다.

## 완료 확인

- Push와 Cancel은 키보드와 VoiceOver로 식별하고 실행할 수 있다.
- 일반 Push는 기존 Git 설정을 사용한다. Push to…는 검토한 commit과 branch 하나를 명시적으로 지정한다.
- Push 자체에는 `--set-upstream`을 사용하지 않는다. force·force-with-lease, tag·여러 ref 게시와 remote branch 삭제도 포함하지 않는다.

[사용자 흐름 문서로 돌아가기](../README.md)
