# Gallae for Git

로컬 저장소의 상태와 변경 이유를 빠르게 읽고, 안전하게 Git 작업을 끝낼 수 있게 해 주는 무료·오픈소스 macOS Git GUI다.

시스템 Git만 사용한다. 별도의 Git 구현을 들고 다니지 않으므로 터미널에서 보는 것과 같은 Git이 같은 저장소를 다룬다.

## 지금 할 수 있는 것

- **읽기** — Repository Library와 폴더 탐색, 마지막 Workspace 복원, 작업 트리 상태, Unified·Split diff
- **커밋** — 파일·hunk·**줄 단위** stage와 unstage, 커밋, amend, 확인을 거치는 discard
- **히스토리** — commit 목록과 그래프, 파일별 patch, Revert, soft·mixed·hard Reset
- **동기화** — Fetch, Fetch & Prune, 자동 Fetch, fast-forward Pull, Push, Publish, Remote 관리
- **복구** — Stash 조회·생성·적용·삭제, HEAD Reflog와 복구 branch 생성
- **분기 작업** — local branch 생성·전환·Merge·Rebase, 충돌 파일의 Base·Ours·Theirs 검사와 해결, Interactive Rebase 계획 편집

## 사용자의 Git 설정이 diff를 깨뜨리지 않는다

Git을 실행해 그 출력을 읽는 GUI는 사용자의 `~/.gitconfig`에 취약하다. 출력 형식을 바꾸는 설정 하나가 diff 표시를 깨거나, 부분 stage를 통째로 못 쓰게 만든다. 널리 알려진 문제이고 여러 도구에 같은 고장이 공개 보고돼 있다.

Gallae는 patch를 만들 때 형식을 고정한다. 다음 설정이 무엇으로 잡혀 있든 diff 표시와 줄 단위 stage·discard가 그대로 동작한다.

| 설정 | 고정하지 않으면 |
| --- | --- |
| `diff.external` (difftastic, sem 등 외부 diff 도구) | 출력이 patch가 아니어서 diff와 stage가 전부 깨진다 |
| `color.ui`·`color.diff` = `always` | escape 문자가 섞여 hunk를 인식하지 못한다 |
| `diff.noprefix`·`mnemonicPrefix`·`srcPrefix`·`dstPrefix` | 부분 stage가 실패한다 |
| `diff.context` = `0` | 부분 stage가 실패한다 |
| `diff.suppressBlankEmpty` | 빈 줄 뒤의 줄 번호가 조용히 어긋난다 |
| `core.quotepath` (기본값) | 한글·CJK 파일 이름이 `\355\225\234…`로 보인다 |

파일의 **내용**을 정의하는 설정은 그대로 존중한다. `core.autocrlf`, `core.eol`, `.gitattributes`의 text·eol 속성은 저장소의 성질이므로 Gallae가 건드리지 않는다.

설정 값에 오타가 있어 Git 자체가 실행되지 않을 때는 Git이 알려 준 원인을 그대로 보여 준다. 어느 설정의 어느 값이 문제인지 화면에서 읽을 수 있다.

근거와 실험 기록은 [docs/research/git-diff-config.md](docs/research/git-diff-config.md)에 있다.

## sem이 있으면 무엇이 바뀌었는지 함께 읽는다

[sem](https://github.com/ataraxy-labs/sem)이 설치돼 있으면 diff 위에 이 변경이 건드린 함수·타입·속성을 한 줄로 보여 준다.

> Modified struct Counter · Added property isZero

Gallae가 만든 patch를 `sem`에 그대로 넘기는 방식이라 diff 표시와 줄 단위 stage는 그대로다. `sem setup` 같은 설정은 필요 없고, `sem`이 없으면 이 줄만 나오지 않는다.

## 요구 사항

- macOS 15 이상
- 시스템 Git (Xcode Command Line Tools)
- (선택) [sem](https://github.com/ataraxy-labs/sem) — entity 요약을 함께 보려면

## 문서

| 문서 | 내용 |
| --- | --- |
| [PRODUCT.md](PRODUCT.md) | 제품 기준, 방향, 클린룸 원칙, 디자인 결정 |
| [CONTEXT.md](CONTEXT.md) | 도메인 용어 |
| [DESIGN_SYSTEM.md](DESIGN_SYSTEM.md) | 재질·대비·밀도 응답 |
| [docs/IMPLEMENTATION_PLAN.md](docs/IMPLEMENTATION_PLAN.md) | 구현 순서와 단계별 완료 조건 |
| [docs/README.md](docs/README.md) | 유즈케이스 색인 |
| [docs/research/](docs/research/) | 근거를 남긴 조사 기록 |

## 라이선스

[MIT License](LICENSE)
