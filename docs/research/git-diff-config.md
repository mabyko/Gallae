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
| `diff.context` | `0` | `git apply`가 `patch does not apply`로 실패. 스테이징 불가 |
| `diff.suppressBlankEmpty` | `true` | 빈 문맥 줄이 앞 공백 없이 나와 파서가 문맥으로 못 세고 **이후 줄 번호가 조용히 어긋난다**. 3번 줄이 "line 2"로 표시됨 |
| `diff.algorithm` 등 **아무 설정의 잘못된 값** | 예: `histgram` | `git status`·`diff`·`log`가 전부 exit 128. 앱은 **Repository Unavailable**이 되고 원인을 알려 주지 않는다 |

`core.quotepath`는 기본 설정에서 그냥 일어난다. 적용은 되므로 표시 결함이다. `diff.suppressBlankEmpty`는 화면이 멀쩡해 보이는데 숫자만 틀려 가장 위험하다.

`diff.srcPrefix`·`diff.dstPrefix`도 `diff.noprefix`와 같은 부류다.

**잘못된 값은 재정의로 구제되지 않는다.** `-c diff.algorithm=histogram`도 `--diff-algorithm=histogram`도 exit 128을 막지 못한다. git이 설정 파일을 파싱하는 단계에서 죽기 때문이다. 전역 설정에 있으면 모든 Repository가 동시에 열리지 않는다. 이 부류는 고칠 수 없고 **원인을 사람에게 전달하는 것**만 할 수 있다.

값의 집합은 닫혀 있다. `git-config(1)`이 `diff.algorithm`의 variants를 `default`·`myers`·`minimal`·`patience`·`histogram`으로 열거하며 `default`는 `myers`의 별칭이라 실제 알고리즘은 넷이다. 넷 모두 문법 위반 없이 apply까지 통과하는 것을 확인했다.

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

## 5. 결정 — 표준 하나를 정해 고정한다

사용자 설정으로 diff를 표현하지 않는다. Gallae가 표준 하나를 정해 고정하고, 필요해지면 **호환이 확인된 항목만** 앱 설정으로 연다. 이유는 4절까지의 실험이 보여 준 대로다. 화면에 보이는 patch와 index에 적용되는 patch가 같아야 하는데, 사용자 설정을 그대로 통과시키면 그 둘이 갈리거나 파싱이 깨진다. 앱 설정으로 옮기면 UI가 감당할 수 있는 범위 안에서만 선택지를 준다.

고정할 호출은 이렇다.

```
git -C <root> \
    -c core.quotepath=false \
    -c diff.suppressBlankEmpty=false \
    diff \
    --no-color --no-ext-diff --no-textconv \
    --default-prefix \
    --find-renames \
    --diff-algorithm=histogram \
    -U3 \
    -- <pathspec>
```

`-c`는 하위 명령보다 앞에 와야 한다. `--default-prefix`는 git 2.45 이상이며 macOS 15 기본 git(2.50.1)에서 확인했다. 더 오래된 git까지 감안하면 `--src-prefix=a/ --dst-prefix=b/`가 같은 효과를 낸다.

`histogram`을 고른 이유는 실제 코드에서 hunk 경계가 더 읽기 좋게 나오기 때문이다. `myers`(git 기본값)로 바꾸는 것은 한 단어짜리 변경이다.

**존중하는 것은 파일의 내용을 정의하는 설정뿐이다.** `core.autocrlf`·`core.eol`과 `.gitattributes`의 text/eol 속성은 diff 렌더링이 아니라 저장소의 성질이므로 건드리지 않는다. `.gitattributes`의 `diff=<driver>` funcname 패턴도 hunk 헤더 뒤 문맥 텍스트일 뿐이라 그대로 둔다.

## 6. 나중에 설정으로 열 수 있는 것과 열면 안 되는 것

지금 만들지 않는다. 필요해질 때를 위한 기록이다.

**열어도 되는 것 (apply 호환 확인됨)**

| 항목 | 범위 | 근거 |
| --- | --- | --- |
| 문맥 줄 수 | 1 이상 | `-U0`만 apply가 깨진다. 1은 통과 확인 |
| diff 알고리즘 | myers·minimal·patience·histogram | 넷 모두 문법 위반 0, apply 통과 확인 |
| Unified·Split | — | 이미 있다 |

**열면 안 되거나, 열려면 staging을 꺼야 하는 것**

| 항목 | 문제 |
| --- | --- |
| 공백 무시 (`-w`, `--ignore-space-change`, `--ignore-blank-lines`) | 생성된 patch를 **apply 할 수 없다**(`patch failed` 확인). 표시 전용으로 두고 그 동안 hunk·줄 단위 staging과 discard를 비활성으로 해야 한다 |
| 단어 단위 diff (`--word-diff`) | 출력이 줄 단위 patch가 아니다. 파서와 부분 패치 빌더가 다룰 수 없다 |

## 7. 남는 설계 질문

Gallae는 `diff --git`·`index`·`---`·`+++` 네 줄을 diff 화면에 그대로 보여 준다. GUI에는 이미 "Working Tree" 구획 머리와 파일 이름이 있으므로 이 네 줄은 정보를 더하지 않는다. 이 줄들을 화면에서 빼면

- `core.quotepath`의 octal escape가 표시 면에서 무의미해진다(파일 이름은 GUI가 따로 보여 준다)
- `--default-prefix`로 접두사를 정규화해도 사용자가 잃는 것이 없다

즉 5절의 고정과 이 결정은 함께 가는 것이 자연스럽다. 다만 화면에서 눈에 보이는 변화이므로 제품 결정으로 남긴다.

## 8. 고칠 수 없는 부류의 처리

잘못된 설정 값으로 git이 아예 돌지 않을 때, 지금 앱은 "The Repository exists, but its working tree status cannot be read."라고만 말하고 유일한 행동으로 Remove from Recent를 제안한다. 실제 해법은 gitconfig 한 줄을 고치는 것이므로 이 안내는 사용자를 틀린 곳으로 보낸다. git의 stderr(`unknown value for config 'diff.algorithm': histgram`)에 원인과 위치가 이미 들어 있으니 그것을 문구에 실어야 한다.
