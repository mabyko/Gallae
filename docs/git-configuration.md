# Gallae가 Git 설정을 다루는 방식

Gallae는 시스템 Git을 실행하고 그 출력을 읽는다. 그래서 사용자의 `~/.gitconfig`와 저장소 설정이 결과에 닿는다. 어디까지 닿게 둘지에는 기준이 하나 있다.

> Gallae가 화면에 그리는 patch와 `git apply`로 index에 적용하는 patch는 같은 것이어야 한다. **그 텍스트의 형식을 바꾸는 설정은 고정하고, 파일의 내용이 무엇인지 정하는 설정은 존중한다.**

## 고정하는 설정

이 값들은 patch의 형식을 바꾸어 파싱이나 적용을 깨뜨린다. Gallae는 patch를 만들 때 이들을 덮는다.

| 설정 | 고정하지 않으면 |
| --- | --- |
| `diff.external` | 출력이 patch가 아니게 되어 diff 표시와 stage가 전부 깨진다 |
| textconv 필터 | 변환된 텍스트는 원본에 적용할 수 없다 |
| `color.ui`·`color.diff` = `always` | escape 문자가 섞여 hunk 헤더를 인식하지 못한다 |
| `diff.noprefix`·`mnemonicPrefix`·`srcPrefix`·`dstPrefix` | `git apply`가 경로를 벗기지 못해 부분 stage가 실패한다 |
| `diff.context` = `0` | `git apply`가 patch를 거부한다 |
| `diff.suppressBlankEmpty` | 빈 문맥 줄이 앞 공백 없이 나와 그 뒤의 줄 번호가 어긋난다 |
| `core.quotepath` (기본값 `true`) | 한글·CJK·악센트 파일 이름이 `\355\225\234…`로 보인다 |

`diff.algorithm`도 고정한다. 네 알고리즘 모두 적용 가능한 patch를 내지만, 표시가 사람마다 달라지지 않도록 하나로 둔다.

## 존중하는 설정

이 값들은 patch의 형식이 아니라 **파일의 내용이 무엇인지**를 정한다. 저장소의 성질이므로 Gallae가 건드리지 않는다.

- `core.autocrlf`, `core.eol`
- `.gitattributes`의 `text`·`eol` 속성
- `.gitattributes`의 `diff=<driver>` funcname 패턴 — hunk 헤더 뒤에 붙는 문맥 텍스트

## 고칠 수 없는 부류

설정 값에 오타가 있으면 Git이 설정 파일을 읽는 단계에서 실패한다. `git status`, `git diff`, `git log`가 모두 종료 코드 128로 끝나므로 어떤 재정의로도 구제되지 않는다. 전역 설정에 있으면 모든 Repository가 동시에 열리지 않는다.

```
error: unknown value for config 'diff.algorithm': histgram
```

Gallae는 이 경우 Git이 알려 준 첫 줄을 화면 문구에 실어 준다. 어느 설정의 어느 값이 문제인지 읽고 고칠 수 있다.

## 나중에 설정으로 열 수 있는 것

지금은 만들지 않았다. 열게 된다면 아래 구분을 지킨다.

**열어도 되는 것** — 적용 호환을 확인했다.

| 항목 | 범위 |
| --- | --- |
| 문맥 줄 수 | 1 이상 (`0`은 `git apply`가 거부한다) |
| diff 알고리즘 | myers · minimal · patience · histogram |

**열려면 부분 stage를 꺼야 하는 것**

| 항목 | 문제 |
| --- | --- |
| 공백 무시 (`-w`, `--ignore-space-change`) | 생성된 patch를 적용할 수 없다 |
| 단어 단위 diff (`--word-diff`) | 출력이 줄 단위 patch가 아니다 |

## 근거

설정과 patch 옵션은 [Git config 문서](https://git-scm.com/docs/git-config)와 [Git diff 문서](https://git-scm.com/docs/git-diff)를 참고한다. Gallae의 설정 격리와 patch 적용 호환은 [RepositoryInspectorTests](../GallaeTests/RepositoryInspectorTests.swift)에서 검증한다.
