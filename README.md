# 초기화 노트북 원클릭 코딩 환경 세팅 (`setting`)

전원을 끌 때마다 C 드라이브가 초기화되는 윈도우 노트북에서, PowerShell 명령어 **한 줄**로 나만의 코딩 환경을 즉시 복구하는 부트스트랩 스크립트입니다.

## 재부팅 후 한 줄 실행 명령어

GitHub(`r2415/setting`)에 업로드한 뒤, 새 부팅 직후 PowerShell에서 아래 명령어를 실행하면 됩니다.

```powershell
irm https://raw.githubusercontent.com/r2415/setting/main/setup.ps1 | iex
```

로컬에서 직접 실행할 때(로그인 안내 생략 옵션 포함):

```powershell
powershell -ExecutionPolicy Bypass -File .\setup.ps1
powershell -ExecutionPolicy Bypass -File .\setup.ps1 -SkipAuth
```

---

## 자동으로 세팅되는 항목

1. **기본 이미지 내 기존 도구 즉시 복구 (1초)**
   - PC에 이미 설치된 `VS Code`, `Python 3.13` 경로를 찾아 사용자 `PATH` 및 현재 터미널 세션에 즉시 연결합니다.
   - 만약 해당 도구가 아예 없는 다른 PC라면 Scoop으로 자동 설치합니다.
2. **필수 및 추천 개발 도구 무인 설치 (Scoop 기반, 관리자 권한 팝업 없음)**
   - **필수**: `Git`, `Node.js (LTS)` + `npm`, `GitHub CLI (gh)`, `Python 3.13`, `VS Code`
   - **추천**: `uv` (초고속 Python 패키지·가상환경 매니저)
3. **AI 코딩 환경 세팅**
   - `Antigravity CLI (agy)` 설치 및 `PATH` 등록
   - `superpowers` 플러그인 설치 (`agy plugin install superpowers`, 로그인 전 실패 시 `~/.gemini/config/plugins/superpowers`로 자동 Git 클론)
4. **개인 환경 자동 적용**
   - Git 전역 설정: `user.name = r2415`, `user.email = pjs9785@korea.ac.kr`, `init.defaultBranch = main`, `core.autocrlf = true`
   - VS Code 확장: 한국어 팩, Python, Prettier, ESLint, GitLens, Material Icon Theme
   - VS Code `settings.json`: 자동 저장(`afterDelay`), 저장 시 자동 포맷(`editor.formatOnSave`), 기본 터미널 PowerShell (기존 설정 보존)
5. **마지막 인증 단계**
   - 무인 설치와 검증 요약 출력이 끝난 뒤 GitHub 브라우저 로그인(`gh auth login`)과 `agy` 로그인을 안내합니다.

---

## 노트북을 끄기 전 오늘 최초 1회 업로드하기

이 폴더(`C:\Users\교육생-PC14\Desktop\setting`)도 컴퓨터를 끄면 초기화되므로, 아래 명령으로 내 GitHub에 올려두세요.

```powershell
.\publish.ps1
```

이미 `r2415/setting` 저장소가 없다면 브라우저 로그인 후 자동으로 Public 저장소를 생성하고 푸시해 줍니다.

---

## 검증 및 커스터마이징

- 전체 설치 상태 검증 테스트 실행:
  ```powershell
  powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Verify-Setup.ps1
  ```
- Git 계정 변경 실행:
  ```powershell
  .\setup.ps1 -GitName "내이름" -GitEmail "이메일"
  ```
- 설치할 Scoop 패키지나 VS Code 확장을 늘리려면 [setup.ps1](setup.ps1)의 `Install-DevPackages` 또는 `Set-GitAndVSCodeConfig` 목록을 수정하세요.
