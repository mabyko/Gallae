# Gallae 사용자 흐름 문서

> 상태: 구현 기준 · 2026-08-27
> 범위: Open & Inspect, Commit과 현재 HEAD History 검색

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
| UC-12 | [현재 HEAD의 commit History 검사](use-cases/uc-12-inspect-history.md) |
