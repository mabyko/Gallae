# Gallae for Git

로컬 저장소의 상태와 변경 이유를 빠르게 읽고, 안전하게 Git 작업을 끝낼 수 있게 해 주는 macOS Git GUI다. 무료이고 오픈소스다.

**시스템 Git만 사용한다.** 자체 Git 구현을 들고 다니지 않으므로 터미널에서 쓰는 것과 같은 Git이 같은 저장소를 다룬다.

> **상태: 개발 중.** 아직 배포판이 없다. 직접 빌드해 쓸 수 있다.

## 무엇을 할 수 있나

| | |
| --- | --- |
| **읽기** | Repository Library와 폴더 탐색, 마지막 Workspace 복원, 작업 트리 상태, Unified·Split diff |
| **커밋** | 파일·hunk·**줄 단위** stage와 unstage, 커밋, amend, 확인을 거치는 discard |
| **히스토리** | commit 목록과 그래프, 파일별 patch, Revert, soft·mixed·hard Reset |
| **동기화** | Fetch, Fetch & Prune, 자동 Fetch, fast-forward Pull, Push, Publish, Remote 관리 |
| **복구** | Stash 조회·생성·적용·삭제, HEAD Reflog와 복구 branch 생성 |
| **분기 작업** | branch 생성·전환·Merge·Rebase, 충돌 파일의 Base·Ours·Theirs 검사와 해결, Interactive Rebase 계획 편집 |

## 다른 점

**당신의 `.gitconfig`가 diff를 깨뜨리지 않는다.** Git을 실행해 그 출력을 읽는 GUI는 사용자 설정에 취약하다. 외부 diff 도구를 걸었거나 색·접두사·문맥 설정을 바꿔 두면 diff가 깨지거나 부분 stage를 통째로 못 쓰게 되는 일이 여러 도구에서 보고돼 왔다. Gallae는 patch를 만들 때 형식을 고정하고, 파일의 내용을 정의하는 설정(`core.autocrlf`, `.gitattributes`)만 존중한다. → [무엇을 고정하고 무엇을 존중하는가](docs/git-configuration.md)

**설정 때문에 Git이 아예 실행되지 않으면 그 이유를 보여 준다.** 어느 설정의 어느 값이 문제인지 화면에서 읽고 고칠 수 있다.

**[sem](https://github.com/ataraxy-labs/sem)이 있으면 무엇이 바뀌었는지 함께 읽는다.** diff 위에 이 변경이 건드린 함수·타입·속성이 한 줄로 붙는다.

> Modified struct Counter · Added property isZero

Gallae가 만든 patch를 그대로 넘기는 방식이라 diff와 줄 단위 stage는 영향받지 않는다. `sem`이 없으면 이 줄만 나오지 않는다.

## 빌드

```sh
git clone <this repository>
cd Gallae
open Gallae.xcodeproj
```

서명이 필요하면 `Config/Local.xcconfig`를 만든다. 추적되지 않는 파일이라 개인 식별자가 저장소에 들어가지 않는다.

```
GALLAE_BUNDLE_ID = <your-bundle-id>
GALLAE_BUNDLE_ID[config=Debug] = <your-debug-bundle-id>
DEVELOPMENT_TEAM = <your-team-id>
```

명령줄에서:

```sh
xcodebuild test -project Gallae.xcodeproj -scheme Gallae -destination 'platform=macOS'
```

**요구 사항** — macOS 15 이상, Xcode, 시스템 Git(Xcode Command Line Tools). `sem`은 선택이다.

## 문서

| | |
| --- | --- |
| [PRODUCT.md](PRODUCT.md) | 제품 기준, 방향, 클린룸 원칙, 디자인 결정 |
| [CONTEXT.md](CONTEXT.md) | 도메인 용어 |
| [DESIGN_SYSTEM.md](DESIGN_SYSTEM.md) | 재질·대비·밀도 응답 |
| [docs/git-configuration.md](docs/git-configuration.md) | Gallae가 Git 설정을 다루는 방식 |
| [docs/IMPLEMENTATION_PLAN.md](docs/IMPLEMENTATION_PLAN.md) | 구현 순서와 단계별 완료 조건 |
| [docs/README.md](docs/README.md) | 유즈케이스 색인 |
| [docs/research/](docs/research/) | 근거를 남긴 조사 기록 |

## 기여

구현의 근거는 공개된 Git 동작과 문서, Apple 공개 API와 Human Interface Guidelines다. 경쟁 앱의 코드·에셋·문구·수치는 가져오지 않는다. 자세한 기준은 [PRODUCT.md의 클린룸 원칙](PRODUCT.md#클린룸-원칙)에 있다.

분기나 반복이 있는 로직은 임시 저장소를 쓰는 작은 통합 테스트를 남긴다.

## 라이선스

[MIT License](LICENSE)
