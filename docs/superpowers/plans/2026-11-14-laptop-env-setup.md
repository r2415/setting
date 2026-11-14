# Laptop Environment Bootstrap (`setup.ps1`) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and verify an idempotent, zero-UAC-prompt PowerShell bootstrap script (`setup.ps1`) and companion GitHub publishing helper (`publish.ps1`) that sets up VS Code, Git (`r2415` / `pjs9785@korea.ac.kr`), GitHub CLI (`gh`), Python 3.13, Node.js LTS, `uv`, Antigravity (`agy`), and the `superpowers` plugin on a Windows laptop that resets on every shutdown.

**Architecture:** A single self-contained PowerShell script (`setup.ps1`) executable both locally and via `irm <raw-github-url> | iex`. It first recovers pre-installed baseline tools (`VS Code`, `Python 3.13` in `$env:LOCALAPPDATA\Programs`) by wiring them into both the persistent User `PATH` and current session `$env:Path`, then bootstraps Scoop in user scope to silently install missing tools (`git`, `nodejs-lts`, `gh`, `uv`), installs `agy` and `superpowers` with a git-clone fallback, applies Git and VS Code configurations non-destructively, prints a verification table, and finally triggers interactive browser authentication (unless `-SkipAuth` is passed).

**Tech Stack:** Windows PowerShell 5.1+ / PowerShell 7+, Scoop, Git, GitHub CLI (`gh`), Node.js LTS, Python 3.13, `uv`, Antigravity CLI (`agy`), VS Code CLI (`code`).

**Spec:** `docs/superpowers/specs/2026-11-14-laptop-env-setup-design.md`

## Global Constraints

- Target OS: Windows 10/11 without `winget` guaranteed in `PATH`, running on a machine (`교육생-PC14`) whose `C:` drive resets to a baseline image on shutdown.
- Must not require UAC elevation prompts during standard execution, and must also not fail if the user happens to run PowerShell as Administrator (`install-scoop.ps1 -RunAsAdmin`).
- Git identity must be configured to `user.name = "r2415"` and `user.email = "pjs9785@korea.ac.kr"`, with `init.defaultBranch = "main"` and `core.autocrlf = "true"`.
- Must update both `[Environment]::GetEnvironmentVariable("Path", "User")` and `$env:Path` in the active PowerShell session so all tools work immediately without restarting the terminal.
- All PowerShell files containing Korean text must be saved with UTF-8 BOM (or use ASCII-safe syntax with `[Console]::OutputEncoding = [System.Text.Encoding]::UTF8`) so Windows PowerShell 5.1 never fails to parse them.

## Review Focus

1. **Running `setup.ps1` from an elevated (Administrator) PowerShell window:** `get.scoop.sh` aborts by default when run as Administrator; `Install-ScoopIfMissing` must detect administrator role and pass `-RunAsAdmin` to the downloaded Scoop installer script.
2. **Running via `irm <url> | iex` vs `.\setup.ps1 -SkipAuth`:** Parameters must have default values and also honor `$env:SETUP_SKIP_AUTH = "1"` so automated testing and piped execution both work seamlessly.
3. **Pre-authentication `superpowers` plugin install:** If `agy plugin install superpowers` fails when `agy` is not logged in yet, `Install-AgyAndSuperpowers` must fall back to cloning `https://github.com/obra/superpowers.git` into `$env:USERPROFILE\.gemini\config\plugins\superpowers`.
4. **Corrupted or missing VS Code `settings.json`:** `Set-VSCodeEnvironment` must handle a missing directory, missing `settings.json`, or existing JSON with trailing commas/comments without crashing, preserving existing keys.
5. **Duplicate `PATH` entries on repeated runs:** `Add-ToUserPath` must normalize trailing backslashes and compare case-insensitively before appending to User `PATH` or `$env:Path`.

---

### Task 1: Save Design Spec, Implementation Plan, and Verification Test Script

**Files:**
- Create: `C:\Users\교육생-PC14\Desktop\setting\docs\superpowers\specs\2026-11-14-laptop-env-setup-design.md`
- Create: `C:\Users\교육생-PC14\Desktop\setting\docs\superpowers\plans\2026-11-14-laptop-env-setup.md`
- Create: `C:\Users\교육생-PC14\Desktop\setting\tests\Verify-Setup.ps1`

**Interfaces:**
- Produces: `tests\Verify-Setup.ps1` which exits with code `0` only when all required commands (`code`, `git`, `python`, `pip`, `node`, `npm`, `gh`, `uv`, `agy`), the `superpowers` plugin directory (`$env:USERPROFILE\.gemini\config\plugins\superpowers`), Git global config (`r2415` / `pjs9785@korea.ac.kr`), and VS Code `settings.json` are present and valid.

- [ ] **Step 1: Save the approved design spec and implementation plan**
  Write the approved spec to `docs/superpowers/specs/2026-11-14-laptop-env-setup-design.md` and this plan to `docs/superpowers/plans/2026-11-14-laptop-env-setup.md`.

- [ ] **Step 2: Write the failing verification script `tests/Verify-Setup.ps1`**
  Create `tests/Verify-Setup.ps1` that checks:
  1. `Get-Command` succeeds for `code`, `git`, `python`, `pip`, `node`, `npm`, `gh`, `uv`, `agy`
  2. `Test-Path "$env:USERPROFILE\.gemini\config\plugins\superpowers"` is `$true`
  3. `git config --global user.name` equals `r2415` and `git config --global user.email` equals `pjs9785@korea.ac.kr`
  4. `Test-Path "$env:APPDATA\Code\User\settings.json"` is `$true` and parses as valid JSON with `files.autoSave` set
  5. Prints `[PASS]` or `[FAIL]` for each check and exits with non-zero code if any check fails.

- [ ] **Step 3: Run `tests/Verify-Setup.ps1` to confirm it initially fails**
  Run: `powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Users\교육생-PC14\Desktop\setting\tests\Verify-Setup.ps1"`
  Expected: FAIL (missing `python`, `node`, `gh`, `uv` in `PATH`, missing `git config`, etc.)

---

### Task 2: Implement and Execute `setup.ps1`

**Files:**
- Create: `C:\Users\교육생-PC14\Desktop\setting\setup.ps1`
- Test: `C:\Users\교육생-PC14\Desktop\setting\tests\Verify-Setup.ps1`

**Interfaces:**
- Consumes: `tests\Verify-Setup.ps1`
- Produces: `setup.ps1` supporting parameters `param([switch]$SkipAuth, [string]$GitName = "r2415", [string]$GitEmail = "pjs9785@korea.ac.kr")` and `$env:SETUP_SKIP_AUTH`.

- [ ] **Step 1: Implement `setup.ps1`**
  Write `C:\Users\교육생-PC14\Desktop\setting\setup.ps1` (saved with UTF-8 BOM or pure ASCII script literals so Windows PowerShell 5.1 parses cleanly) implementing these functions:
  - `Add-ToUserPath([string]$Directory)`: Normalizes path, adds to User environment variable `Path` and `$env:Path` if the directory exists and is not already listed.
  - `Restore-ExistingTools`: Scans `$env:LOCALAPPDATA\Programs\Microsoft VS Code\bin`, `$env:LOCALAPPDATA\Programs\Python\Python*` (plus `\Scripts` and `\Launcher`), `$env:LOCALAPPDATA\Programs\Git\cmd`, `$env:LOCALAPPDATA\agy\bin`, and `$env:USERPROFILE\scoop\shims`, adding each existing directory to `PATH` immediately.
  - `Install-ScoopIfMissing`: Sets `RemoteSigned` for `CurrentUser`, forces TLS 1.2, and installs Scoop (`irm https://get.scoop.sh | iex` for normal user, or downloads and runs with `-RunAsAdmin` if elevated).
  - `Install-DevPackages`: Uses Scoop to install any missing command among `git`, `nodejs-lts` (command `node`), `gh`, `uv`, plus fallback `python` and `vscode` (via `extras` bucket) if not already restored in `Restore-ExistingTools`. Refreshes `$env:Path` after installation.
  - `Install-AgyAndSuperpowers`: Installs `agy` via `irm https://antigravity.google/cli/install.ps1 | iex` if missing; installs `superpowers` via `agy plugin install superpowers` if `$env:USERPROFILE\.gemini\config\plugins\superpowers` does not exist, with a fallback to `git clone https://github.com/obra/superpowers.git "$env:USERPROFILE\.gemini\config\plugins\superpowers"`.
  - `Set-GitAndVSCodeConfig`: Sets global git config (`user.name = $GitName`, `user.email = $GitEmail`, `init.defaultBranch = main`, `core.autocrlf = true`), installs missing VS Code extensions (`ms-ceintl.vscode-language-pack-ko`, `ms-python.python`, `esbenp.prettier-vscode`, `dbaeumer.vscode-eslint`, `eamodio.gitlens`, `PKief.material-icon-theme`), and updates `$env:APPDATA\Code\User\settings.json`.
  - `Show-EnvironmentSummary`: Prints a formatted table of tool versions and statuses.
  - `Start-InteractiveAuth`: Unless `$SkipAuth` or `$env:SETUP_SKIP_AUTH -eq '1'` is set, checks `gh auth status` and prompts the user to run `gh auth login --web -p https` + `gh auth setup-git` and `agy`.

- [ ] **Step 2: Run `setup.ps1 -SkipAuth` on the current machine to provision the missing tools and configs**
  Run: `powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Users\교육생-PC14\Desktop\setting\setup.ps1" -SkipAuth`
  Expected: Installs Scoop, `nodejs-lts`, `gh`, `uv`, VS Code extensions, configures Git and PATH, and outputs the summary table with all items `OK`.

- [ ] **Step 3: Run `tests/Verify-Setup.ps1` in a fresh PowerShell process to verify persistent User `PATH` and all tools**
  Run: `powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Users\교육생-PC14\Desktop\setting\tests\Verify-Setup.ps1"`
  Expected: All checks print `[PASS]` and command exits with code `0`.

- [ ] **Step 4: Re-run `setup.ps1 -SkipAuth` once more to verify idempotency (fast no-op when everything is already installed)**
  Run: `powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Users\교육생-PC14\Desktop\setting\setup.ps1" -SkipAuth`
  Expected: Completes in a few seconds without reinstalling already-installed packages or duplicating `PATH` entries.

---

### Task 3: Create `publish.ps1`, `README.md`, and Initialize Git Repo

**Files:**
- Create: `C:\Users\교육생-PC14\Desktop\setting\publish.ps1`
- Create: `C:\Users\교육생-PC14\Desktop\setting\README.md`
- Create: `C:\Users\교육생-PC14\Desktop\setting\.gitignore`

**Interfaces:**
- Produces: `publish.ps1` (automates `gh auth login`, `gh repo create r2415/setting --public --source=. --remote=origin --push`, and prints the exact `irm https://raw.githubusercontent.com/r2415/setting/main/setup.ps1 | iex` command) and `README.md`.

- [ ] **Step 1: Create `.gitignore`, `publish.ps1`, and `README.md`**
  - `publish.ps1`: Checks if `gh` is logged in (if not, launches `gh auth login --web -p https`), creates or pushes to `https://github.com/r2415/setting` (or user-specified repo name), and prints the exact one-liner command to copy/bookmark for future reboots.
  - `README.md`: Documents the 1-line command (`irm https://raw.githubusercontent.com/r2415/setting/main/setup.ps1 | iex`), what gets installed and configured, how to customize packages/extensions, and how to run `.\publish.ps1` before shutting down the laptop today.

- [ ] **Step 2: Initialize Git repository and commit all files**
  Run:
  ```powershell
  git -C "C:\Users\교육생-PC14\Desktop\setting" init -b main
  git -C "C:\Users\교육생-PC14\Desktop\setting" add .
  git -C "C:\Users\교육생-PC14\Desktop\setting" commit -m "feat: add one-click laptop coding environment bootstrap"
  ```
  Expected: Clean git repository on branch `main` with all files committed under `r2415 <pjs9785@korea.ac.kr>`.

## Re-plan if:
- Scoop bootstrap (`get.scoop.sh`) is blocked by the training center's network firewall/proxy, requiring direct `.zip`/`.exe` downloads from GitHub/official mirrors instead.
- Disk quota or permissions in `$env:USERPROFILE` block creating `~/scoop` or writing to `HKCU:\Environment`.
