# Gallae

Gallae는 사용자가 관리하는 로컬 Git 저장소 모음을 탐색하고, 선택한 저장소의 상태와 변경을 다루는 macOS 애플리케이션이다.

## Language

**Repository Library**:
Gallae가 알고 있는 Library Folder, 발견된 Repository, 최근 연 Repository를 한곳에서 탐색하는 영역이다.
_Avoid_: project list, repository picker

**Library Folder**:
사용자가 Repository 탐색 범위로 등록한 로컬 폴더다. 폴더 자체는 Repository일 필요가 없다.
_Avoid_: workspace root, watched folder, repository

**Repository**:
Git이 유효한 로컬 작업 트리로 판정하고 Gallae가 열 수 있는 디렉터리다.
_Avoid_: project, folder

**Repository Workspace**:
하나의 Repository에서 상태, 변경, 히스토리와 Git 작업을 보여 주는 작업 문맥이다.
_Avoid_: Repository Library, current folder

**Active Repository**:
현재 Repository Workspace가 보여 주는 Repository다.
_Avoid_: current directory, selected folder
