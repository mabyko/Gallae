# UC-41 · 충돌 파일의 Base·Ours·Theirs 검사

> 우선순위: P1

| 항목 | 내용 |
| --- | --- |
| 사용자 목표 | 충돌 파일의 공통 조상과 양쪽 버전을 비교해 해결 방향을 판단한다. |
| 시작 조건 | 미해결 충돌이 있는 Repository Workspace가 열려 있다. |
| 진입점 | Changes의 충돌 파일 |
| 완료 상태 | 선택한 파일의 Base·Ours·Theirs 내용을 Repository 변경 없이 비교한다. |

## 정상 흐름

1. 사용자가 Changes에서 충돌 파일을 선택한다.
2. Gallae가 Git index의 stage 1·2·3 object를 읽는다.
3. Base·Ours·Theirs를 같은 너비의 세 열로 보여 주고 각 열에 역할과 stage 번호를 표시한다.
4. 사용자가 행 번호와 내용을 읽거나 텍스트를 선택해 비교한다.

충돌 파일 머리의 **Open in Merge Tool**에서 외부 병합 도구를 열 수 있다. 설정과 해결 절차는 [외부 도구 지원 범위](../../README.ko.md#충돌-해결과-merge-tool)를 따른다.

## 대안 흐름

- add/add 같은 충돌로 특정 stage가 없으면 빈 내용으로 꾸미지 않고 누락된 버전이라고 표시한다.
- 빈 파일, binary, 지원하지 않는 인코딩과 큰 파일은 서로 다른 상태로 설명한다.
- 읽는 동안 파일 선택이 바뀌면 이전 요청을 취소하고 새 선택을 읽는다.
- Git이 object를 읽지 못하면 오류를 표시하고 같은 화면에서 재시도할 수 있다.

## 완료 확인

- Base는 stage 1, Ours는 stage 2, Theirs는 stage 3이라는 의미를 색 외의 텍스트로도 구분한다.
- 충돌 파일 선택과 세 열의 의미를 키보드와 VoiceOver로 확인할 수 있다.
- 검사는 HEAD·index·working tree를 바꾸지 않는다.
- 비교 자체는 Repository를 바꾸지 않으며, 한쪽 전체 버전 적용과 현재 working tree 내용으로 해결 표시는 각각 별도의 명시적인 확인을 거친다.

[작업 트리와 파일 diff 검사](uc-05-inspect-working-tree.md) · [Ours 또는 Theirs로 해결](uc-42-resolve-conflict-with-side.md) · [사용자 흐름 문서로 돌아가기](../README.md)
