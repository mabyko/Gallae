# Gallae 사용자 흐름 문서

> 상태: 구현 기준 · 2026-09-02
> 범위: Navigator·문맥 바 Workspace 구조와 branch·remote·tag 선택 문맥, 재질·접근성 응답과 Appearance 설정, Unified·Split diff, Open & Inspect, Commit, Repository ref History·파일별 patch와 Revert·soft·mixed·hard Reset, local branch 생성·전환·fast-forward Merge·divergent Merge commit·Rebase, Sync, Stash 조회·생성·적용·삭제, HEAD Reflog 조회·복구 branch 생성, 충돌 파일 Base·Ours·Theirs 검사와 한쪽 전체 버전·현재 working tree 내용으로 해결, 진행 중인 Merge·Rebase 상태 검사·Continue·Abort, Interactive Rebase 계획 검사·편집·검토·실행

제품 범위와 용어는 [PRODUCT.md](../PRODUCT.md)와 [CONTEXT.md](../CONTEXT.md), 구현 순서와 공통 상태는 [구현 계획](IMPLEMENTATION_PLAN.md)을 따른다.

## P0 유즈케이스

| ID | 유즈케이스 |
| --- | --- |
| UC-01 | [Repository 직접 열기](use-cases/uc-01-open-repository.md) |
| UC-02 | [Library Folder 등록 및 탐색](use-cases/uc-02-register-library-folder.md) |
| UC-03 | [발견한 Repository 선택 및 열기](use-cases/uc-03-select-and-open-repository.md) |
| UC-04 | [마지막 Workspace 복원](use-cases/uc-04-restore-workspace.md) |
| UC-05 | [작업 트리와 파일 diff 검사](use-cases/uc-05-inspect-working-tree.md) |
| UC-06 | [현재 상태 새로고침](use-cases/uc-06-refresh-repository.md) |

## P1 유즈케이스

| ID | 유즈케이스 |
| --- | --- |
| UC-07 | [파일 단위 Stage/Unstage](use-cases/uc-07-stage-file.md) |
| UC-08 | [일반 Commit 생성](use-cases/uc-08-create-commit.md) |
| UC-09 | [hunk 단위 Stage/Unstage](use-cases/uc-09-stage-hunk.md) |
| UC-10 | [최근 Commit Amend](use-cases/uc-10-amend-commit.md) |
| UC-11 | [tracked 파일의 unstaged 변경 Discard](use-cases/uc-11-discard-file.md) |
| UC-12 | [Repository commit History 검사](use-cases/uc-12-inspect-history.md) |
| UC-13 | [기존 local branch 전환 또는 Worktree 열기](use-cases/uc-13-switch-local-branch.md) |
| UC-14 | [현재 HEAD에서 local branch 생성](use-cases/uc-14-create-local-branch.md) |
| UC-15 | [기본 remote Fetch](use-cases/uc-15-fetch-default-remote.md) |
| UC-16 | [configured upstream fast-forward Pull](use-cases/uc-16-pull-fast-forward.md) |
| UC-17 | [현재 branch Push](use-cases/uc-17-push-current-branch.md) |
| UC-18 | [upstream 없는 local branch Publish](use-cases/uc-18-publish-local-branch.md) |
| UC-19 | [configured Remote 조회](use-cases/uc-19-inspect-remotes.md) |
| UC-20 | [configured Remote URL 편집](use-cases/uc-20-edit-remote.md) |
| UC-21 | [configured Remote 제거](use-cases/uc-21-remove-remote.md) |
| UC-22 | [configured Remote Fetch 연결 시험](use-cases/uc-22-test-remote-connection.md) |
| UC-23 | [configured Remote 이름 변경](use-cases/uc-23-rename-remote.md) |
| UC-24 | [Fetch 대상 Remote 선택](use-cases/uc-24-choose-fetch-remote.md) |
| UC-25 | [선택한 Remote Fetch & Prune](use-cases/uc-25-fetch-and-prune.md) |
| UC-26 | [자동 Fetch](use-cases/uc-26-fetch-automatically.md) |
| UC-27 | [Stash 변경 검사](use-cases/uc-27-inspect-stash.md) |
| UC-28 | [새 Stash 생성](use-cases/uc-28-create-stash.md) |
| UC-29 | [Stash 적용](use-cases/uc-29-apply-stash.md) |
| UC-30 | [Stash 삭제](use-cases/uc-30-delete-stash.md) |
| UC-31 | [선택한 commit Revert](use-cases/uc-31-revert-commit.md) |
| UC-32 | [merge commit mainline 선택 Revert](use-cases/uc-32-revert-merge-commit.md) |
| UC-33 | [선택한 과거 commit으로 mixed Reset](use-cases/uc-33-reset-current-branch.md) |
| UC-34 | [선택한 과거 commit으로 soft Reset](use-cases/uc-34-soft-reset-current-branch.md) |
| UC-35 | [선택한 과거 commit으로 hard Reset](use-cases/uc-35-hard-reset-current-branch.md) |
| UC-36 | [HEAD Reflog 복구 지점 검사](use-cases/uc-36-inspect-reflog.md) |
| UC-37 | [Reflog 지점에서 복구 branch 생성](use-cases/uc-37-create-recovery-branch.md) |
| UC-38 | [다른 local branch fast-forward Merge](use-cases/uc-38-merge-local-branch.md) |
| UC-39 | [갈라진 local branch Merge commit 생성](use-cases/uc-39-create-merge-commit.md) |
| UC-40 | [현재 branch를 다른 local branch 위로 Rebase](use-cases/uc-40-rebase-current-branch.md) |
| UC-41 | [충돌 파일의 Base·Ours·Theirs 검사](use-cases/uc-41-inspect-conflict-versions.md) |
| UC-42 | [충돌 파일을 Ours 또는 Theirs로 해결](use-cases/uc-42-resolve-conflict-with-side.md) |
| UC-43 | [현재 working tree 내용으로 충돌 해결](use-cases/uc-43-mark-conflict-resolved.md) |
| UC-44 | [진행 중인 Merge·Rebase 상태 검사](use-cases/uc-44-inspect-in-progress-operation.md) |
| UC-45 | [진행 중인 Merge·Rebase 계속 또는 중단](use-cases/uc-45-continue-or-abort-operation.md) |
| UC-46 | [기본 Interactive Rebase 계획 검사](use-cases/uc-46-inspect-interactive-rebase-plan.md) |
| UC-47 | [Interactive Rebase 계획 편집 및 검토](use-cases/uc-47-edit-interactive-rebase-plan.md) |
| UC-48 | [편집한 Interactive Rebase 계획 실행](use-cases/uc-48-run-interactive-rebase-plan.md) |
