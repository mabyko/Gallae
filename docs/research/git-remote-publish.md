# Git remote 선택 Publish 검증

> 확인일: 2026-08-31
> Context7 quota로 문서를 가져오지 못해 Git 공식 웹 문서를 직접 확인했다.

- `git remote`를 인자 없이 실행하면 현재 Repository에 설정된 remote 이름을 나열한다. URL까지 필요할 때만 `-v`를 붙인다. ([git-remote · DESCRIPTION/OPTIONS](https://git-scm.com/docs/git-remote))
- 선택한 remote에 현재 local branch를 같은 이름으로 게시하려면 `git push <remote> HEAD`를 사용한다. `HEAD`는 현재 branch를 remote의 같은 이름 branch로 보낸다. ([git-push · EXAMPLES](https://git-scm.com/docs/git-push))
- `--force`와 refspec의 `+`를 쓰지 않은 일반 push는 branch의 비-fast-forward 갱신을 거부한다. 따라서 안전한 Publish 명령은 `git push --set-upstream <remote> HEAD`다. ([git-push · PUSH RULES](https://git-scm.com/docs/git-push))
- `--set-upstream`(`-u`)은 성공적으로 push됐거나 이미 최신인 branch에 tracking reference를 설정한다. 이후 인자 없는 pull 등에서 이 tracking 정보가 쓰인다. ([git-push · `--set-upstream`](https://git-scm.com/docs/git-push))
