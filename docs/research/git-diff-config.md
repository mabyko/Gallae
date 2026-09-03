# Git diff 설정과 GUI의 처리

> 확인일: 2026-09-03
> Context7로 Git 공식 문서(`/git/htmldocs`)를 가져오고, 로컬 `git 2.50.1`에 직접 실험했다. 다른 GUI는 클린룸 원칙에 따라 코드나 화면이 아니라 **공개된 동작 보고와 제조사 자신의 설명만** 참고했다.

## 1. 문제

Gallae는 `git diff`를 그대로 부르고 출력을 파싱한다(`RepositoryInspector.swift:3876`). `-c` 재정의도 `GIT_CONFIG_NOSYSTEM`도 없으므로 사용자의 `~/.gitconfig`와 저장소 설정이 거의 다 들어온다. 그중 일부는 **출력 형식**을 바꾸어 파싱과 패치 적용을 깨뜨린다.

실험으로 확인한 것은 셋이다.

| 설정 | 값 | 결과 |
| --- | --- | --- |
| `color.diff` / `color.ui` | `always` | ANSI escape가 본문에 섞여 `@@` 헤더 인식 실패. 모든 줄이 metadata가 되고 **Stage Hunk·줄 체크박스·Discard가 사라진다** |
| `diff.noprefix` | `true` | 화면은 그려지지만 `git apply -p1`이 경로를 벗기지 못해 **"Couldn't Stage Hunk"**. 줄 단위 staging·discard 전부 실패 |
| `core.quotepath` | **기본값 `true`** | 비 ASCII 파일명이 `"i/\355\225\234..."` octal escape로 표시된다. 한글·CJK·악센트 파일명이 전부 깨져 보인다 |

앞의 둘은 사용자가 설정을 바꿔야 나타나지만, **세 번째는 기본 설정에서 그냥 일어난다.** 적용은 되므로 표시 결함이다.

`diff.srcPrefix`·`diff.dstPrefix`도 `diff.noprefix`와 같은 부류다.

## 2. 이건 이 앱만의 문제가 아니다

같은 원인의 고장이 여러 도구에서 공개적으로 보고돼 있다. 원인과 처방이 이미 널리 알려진 문제라는 뜻이다.

- Sourcetree는 `diff.noPrefix`·`diff.srcPrefix`·`diff.dstPrefix`에서 diff 표시가 깨진다. 커뮤니티가 정리한 처방은 `-c diff.mnemonicprefix=false` 하나로는 부족하고 `-c diff.noPrefix=false -c diff.srcPrefix=a/ -c diff.dstPrefix=b/`까지 함께 줘야 한다는 것이다. ([Atlassian Community](https://community.atlassian.com/forums/Sourcetree-questions/sourcetree-diff-broken-if-diff-noPrefix-or-diff-srcPrefix-or/qaq-p/3049944))
- GitExtensions는 `diff.noprefix=true` 하나로 기능 대부분이 망가진다. ([gitextensions#4392](https://github.com/gitextensions/gitextensions/issues/4392))
- Git 자신의 GUI인 git-gui도 사용자 지정 diff가 있으면 Stage Hunk/Line 메뉴가 비활성이 된다. ([git-gui#104](https://github.com/prati0100/git-gui/issues/104))
- GitLab의 Gitaly는 아예 `diff.noprefix=false`를 강제한다. 로컬 설정이 `true`면 `a/`·`b/` 접두사가 빠져 diff 헤더 정규식이 어긋나기 때문이다.

패턴은 하나다. **git을 실행해 출력을 파싱하는 도구는 예외 없이 이 문제를 만나고, 해법은 파싱에 관계된 설정만 골라 재정의하는 것이다.**

## 3. 그럼 libgit2를 쓰면 되지 않나

libgit2는 git 실행 파일을 쓰지 않는 독립 구현이라 사용자 설정에 덜 흔들린다. 그러나 방향은 반대로 가고 있다. GitKraken은 libgit2에서 git 실행 파일로 옮기고 있고, 이유를 자신들 블로그에 이렇게 밝혔다 — git은 기능 개발 속도가 빠른 반면 libgit2의 개발 역량은 GUI 클라이언트가 아니라 Git 호스트가 필요로 하는 기능에 쏠려 있어서, 사용자가 새 기능을 쓰려면 오래 기다려야 한다는 것이다. LFS 성능과 SSH 설정 지원 같은 오래된 문제도 이전으로 풀린다고 했다. ([GitKraken 블로그](https://www.gitkraken.com/blog/gitkraken-client-migrating-from-libgit2-to-git-executable))

Gallae는 이미 시스템 git만 쓰기로 정했고(`docs/IMPLEMENTATION_PLAN.md`), 그 선택이 업계가 향하는 방향과 같다. 바꿀 이유가 없다.

## 4. Git이 주는 표준 해법

Git 문서는 스크립트가 쓸 안정적 출력을 위한 장치를 갖고 있다. `git status --porcelain`은 "Git 버전과 사용자 설정에 관계없이 안정적으로 유지된다"고 명시한다. 그러나 **`git diff`에는 `--porcelain`이 없다.** patch 형식은 옵션으로 하나씩 고정해야 한다.

핵심은 `--default-prefix`다. `git-diff(1)`이 직접 이렇게 쓴다.

> `--default-prefix` — 기본 source·destination 접두사("a/"와 "b/")를 사용한다. 이것은 `diff.noprefix`, `diff.srcPrefix`, `diff.dstPrefix`, `diff.mnemonicPrefix` 같은 설정 변수를 **재정의한다**.

즉 접두사 관련 설정 넷을 플래그 하나가 덮는다. `git 2.45`에서 들어왔고 macOS 15 기본 git(2.50.1, Apple Git-155)에서 동작을 확인했다. 더 오래된 git까지 감안하면 예전부터 있던 `--src-prefix=a/ --dst-prefix=b/`가 같은 효과를 낸다(둘 다 `diff.noprefix=true`를 덮는 것을 실험으로 확인).

## 5. 무엇을 덮고 무엇을 존중할 것인가

기준을 하나로 두면 판단이 쉽다. **출력 형식을 바꾸는 설정은 덮고, 내용을 정하는 설정은 존중한다.** 화면에 보이는 것과 index에 적용되는 것이 갈리면 안 되므로, 표시용과 적용용 patch는 같은 것이어야 한다.

**덮어야 하는 것 (형식)**

| 설정 | 방법 | 현재 |
| --- | --- | --- |
| `diff.external` | `--no-ext-diff` | ✅ 이미 |
| textconv 필터 | `--no-textconv` | ✅ 이미 |
| `color.ui`·`color.diff` | `--no-color` | ⚠️ diff 호출 4곳 중 2곳에만 |
| `diff.noprefix`·`srcPrefix`·`dstPrefix`·`mnemonicPrefix` | `--default-prefix` (또는 `--src-prefix=a/ --dst-prefix=b/`) | ❌ 없음 |
| `core.quotepath` | `-c core.quotepath=false` | ❌ 없음 |

**존중해야 하는 것 (내용)**

- `diff.algorithm` — hunk를 어디서 자를지. 사용자가 CLI에서 보는 것과 같아야 한다
- `diff.renames`, `diff.context`
- `core.autocrlf`·`core.eol`과 `.gitattributes`의 text/eol 속성 — 파일의 내용을 정의한다
- `.gitattributes`의 `diff=<driver>` funcname 패턴 — hunk 헤더 뒤 문맥 텍스트

`diff.mnemonicPrefix`만 애매하다. 형식이면서 정보를 담는다(`i/`=index, `w/`=working tree). 덮으면 `a/`·`b/`가 된다.

## 6. 남는 설계 질문

Gallae는 `diff --git`·`index`·`---`·`+++` 네 줄을 diff 화면에 그대로 보여 준다. GUI에는 이미 "Working Tree" 구획 머리와 파일 이름이 있으므로 이 네 줄은 정보를 더하지 않는다. 이 줄들을 화면에서 빼면

- `core.quotepath`의 octal escape 문제가 표시 면에서 사라진다(파일 이름은 GUI가 따로 보여 준다)
- `--default-prefix`로 접두사를 정규화해도 사용자가 잃는 것이 없다

즉 5절의 재정의와 이 결정은 함께 가는 것이 자연스럽다. 다만 화면에서 눈에 보이는 변화이므로 제품 결정으로 남긴다.
