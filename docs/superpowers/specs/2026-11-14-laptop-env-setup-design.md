# 설계서: 초기화 노트북용 원클릭 코딩 환경 부트스트랩 (`setup.ps1`)

## 1. 목적 및 배경 (Intent & Why)
* **왜 필요한가**: 전원을 끌 때마다 C 드라이브가 초기 복원 이미지(2024-11-24 상태)로 초기화되는 노트북(`교육생-PC14`)에서, 매번 수동으로 개발 도구를 다운받고 환경변수를 잡고 Git 계정을 등록하는 반복 노동을 없애기 위함입니다.
* **최종 모습**: 부팅 후 PowerShell에 **한 줄 명령어(`irm <내 GitHub Raw 주소> | iex`)**만 붙여넣으면, 중간에 권한 승인 팝업 없이 모든 코딩 도구와 내 개인 설정이 자동으로 세팅되고, 맨 마지막에 브라우저 로그인만 한 번 수행하면 즉시 코딩을 시작할 수 있습니다.

## 2. 목표 / 비목표 / 안티목표
* **목표 (Goals)**:
  1. **필수 도구 100% 세팅**: `VS Code`, `Git`, `GitHub CLI(gh)`, `Python`, `Node.js(LTS)`, `Antigravity(agy)`, `superpowers` 플러그인 완벽 설치 및 현재 터미널 세션 `PATH` 즉시 반영
  2. **기존 설치 도구 재활용**: 기본 이미지에 이미 존재하는 `VS Code`와 `Python 3.13`은 재설치하지 않고 1초 만에 `PATH`만 복구(다른 새 노트북에서 실행해 파일이 없을 때만 자동 설치)
  3. **개인화 및 추천 도구 자동 구성**:
     * Git 계정 자동 등록 (`user.name`: `r2415`, `user.email`: `pjs9785@korea.ac.kr`, 기본 브랜치 `main`, 윈도우 줄바꿈 `core.autocrlf true`)
     * 추천 도구: **`uv`**(초고속 Python 패키지/가상환경 매니저), **VS Code 필수 확장**(Prettier, ESLint, GitLens, Material Icon Theme — 이미 깔린 한국어팩/Python 확장은 자동 스킵) 및 기본 `settings.json`(자동 저장, 저장 시 포맷팅 등)
  4. **설치와 인증의 분리**: 무인 설치(1~2분)를 먼저 끝낸 뒤, 마지막에 GitHub(`gh auth login`) 및 `agy` 인증을 안내
* **비목표 (Non-Goals)**:
  * 무거운 IDE(Visual Studio Community, Android Studio 등)나 Docker Desktop처럼 재부팅이 강제되는 시스템 드라이버 설치는 포함하지 않습니다.
* **안티목표 (Anti-Goals - 기술적으로 작동해도 실패로 간주할 상황)**:
  * 설치 도중 **관리자 권한 승인(UAC) 팝업**이나 설치 마법사 '다음(Next)' 버튼 때문에 사람이 화면 앞을 지키고 있어야 하는 상황
  * 설치는 됐는데 **터미널을 껐다 켜야만** `python`, `node`, `git`, `agy` 명령어가 인식되는 상황
  * `agy` 로그인 전이라 `superpowers` 플러그인 설치가 실패하고 넘어가는 상황

## 3. 제약 조건 (Constraints)
* 대상 PC에 윈도우 기본 `winget`이 없으며, 일반 권한(비관리자) 세션에서도 동작해야 함
* C 드라이브만 존재하므로 컴퓨터를 끄기 전에 이 스크립트 자체를 본인 GitHub(`r2415`) 저장소나 Gist에 올려두어야 다음 부팅 때 한 줄 명령어로 불러올 수 있음

## 4. 검토한 접근법 (Approaches)
1. **접근법 1: Scoop 기반 하이브리드 올인원 스크립트 (채택)**
   * 이미 깔린 앱(`VS Code`, `Python 3.13`)은 경로만 연결하고, 없는 앱(`git`, `nodejs-lts`, `gh`, `uv`)은 무권한 패키지 매니저인 **Scoop**으로 설치. UAC 팝업이 전혀 없고 유지보수가 가장 쉬워 채택.
2. **접근법 2: 공식 `.exe`/`.msi` 직접 다운로드 및 무인 설치 (기각)**
   * `.msi` 설치 시 UAC 관리자 권한 창이 뜰 수 있고 다운로드 URL 파싱 유지보수가 번거로움.
3. **접근법 3: 포터블 `.zip` 병렬 압축 해제 (기각)**
   * 속도는 빠르지만 Git 우클릭 메뉴나 shim 관리, 추후 패키지 추가가 불편함.

## 5. 상세 동작 흐름 (How It Works)
`setup.ps1`은 아래 6단계로 순차 실행되며, 이미 설치된 항목은 자동으로 건너뛰는 **멱등성(Idempotency, 여러 번 실행해도 안전함)**을 갖도록 설계합니다.

```text
[1단계: 권한 및 기존 도구 즉시 복구 (1초)]
  ├─ PowerShell 실행 정책 허용 (CurrentUser -> RemoteSigned)
  ├─ AppData\Local\Programs 내 기존 VS Code, Python 3.13 탐색
  └─ 발견 시 User PATH 및 현재 세션 $env:Path에 즉시 등록

[2단계: Scoop 및 핵심/추천 개발 도구 무인 설치 (약 60~90초)]
  ├─ Scoop 미설치 시 자동 부트스트랩 (irm get.scoop.sh | iex)
  ├─ 필수 설치: git, nodejs-lts, gh (GitHub CLI)
  ├─ 추천 설치: uv (Python 초고속 패키지 매니저)
  └─ (만약 1단계에서 VS Code나 Python이 없었던 다른 노트북이면 여기서 자동 설치)

[3단계: Antigravity (agy) 및 superpowers 플러그인 장착]
  ├─ agy 미설치 시 공식 스크립트로 설치 (irm https://antigravity.google/cli/install.ps1 | iex)
  └─ superpowers 플러그인 설치: `agy plugin install superpowers` 실행
     (인증 전이라 실패할 경우를 대비해 ~/.gemini/config/plugins/superpowers에 git clone 폴백 지원)

[4단계: 나만의 코딩 환경 설정 (Git & VS Code)]
  ├─ git config --global user.name "r2415" / user.email "pjs9785@korea.ac.kr"
  ├─ git config --global init.defaultBranch main / core.autocrlf true
  ├─ VS Code 추천 확장 설치 (Prettier, ESLint, GitLens, Material Icon Theme)
  └─ VS Code settings.json 기본값 적용 (자동 저장, Format on Save 등)

[5단계: 설치 검증 요약표 출력]
  └─ code, git, python, node, npm, gh, uv, agy, superpowers 버전 및 상태를 한눈에 출력

[6단계: 대화형 로그인 안내 (`-SkipAuth` 옵션으로 생략 가능)]
  └─ GitHub 로그인 (`gh auth login --web` + `gh auth setup-git`) 및 `agy` 실행 안내
```

## 6. 세부 결정 사항
1. **`superpowers` 설치 이중 안전장치**: `agy` 로그인 전에도 플러그인이 100% 깔리도록 `agy plugin install superpowers` 실행 후 폴더가 없으면 GitHub에서 직접 플러그인 경로로 클론하도록 설계.
2. **GitHub 업로드 도우미 포함**: 스크립트가 재부팅 시 사라지지 않도록, 본인 GitHub(`r2415`) 저장소에 바로 푸시할 수 있는 `publish.ps1`을 함께 제공.
