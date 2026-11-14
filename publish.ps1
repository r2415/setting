param(
    [string]$Owner = 'r2415',
    [string]$RepoName = 'setting',
    [switch]$Private
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$repoDir = $PSScriptRoot
if (-not $repoDir) { $repoDir = (Get-Location).Path }

$scoopShims = Join-Path $env:USERPROFILE 'scoop\shims'
if ((Test-Path -LiteralPath $scoopShims) -and ($env:Path -notlike "*$scoopShims*")) {
    $env:Path = "$scoopShims;$env:Path"
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw 'git is not available in PATH. Run setup.ps1 first.'
}
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    throw 'GitHub CLI (gh) is not available in PATH. Run setup.ps1 first.'
}

function Invoke-NativeQuiet {
    param([scriptblock]$Action)
    $oldPref = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        return (& $Action 2>$null)
    } finally {
        $ErrorActionPreference = $oldPref
    }
}

Push-Location $repoDir
try {
    if (-not (Test-Path -LiteralPath (Join-Path $repoDir '.git'))) {
        Write-Host 'Initializing git repository (branch: main)...' -ForegroundColor Cyan
        & git init -b main
    }

    $currentName = (Invoke-NativeQuiet { & git config user.name })
    if (-not $currentName) { & git config user.name $Owner }
    $currentEmail = (Invoke-NativeQuiet { & git config user.email })
    if (-not $currentEmail) { & git config user.email 'pjs9785@korea.ac.kr' }

    $status = & git status --porcelain
    if ($status) {
        Write-Host 'Committing workspace changes...' -ForegroundColor Cyan
        & git add .
        & git commit -m 'chore: update laptop setup scripts'
    }

    Invoke-NativeQuiet { & gh auth status | Out-Null } | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host 'GitHub authentication required. Opening browser login...' -ForegroundColor Yellow
        & gh auth login --web -p https
        if ($LASTEXITCODE -ne 0) { throw 'gh auth login failed.' }
    }
    & gh auth setup-git

    $fullRepo = "$Owner/$RepoName"
    $repoExists = $false
    Invoke-NativeQuiet { & gh repo view $fullRepo | Out-Null } | Out-Null
    if ($LASTEXITCODE -eq 0) { $repoExists = $true }

    $remoteUrl = "https://github.com/$fullRepo.git"
    if ($repoExists) {
        Write-Host "Repository $fullRepo already exists. Pushing to origin/main..." -ForegroundColor Cyan
        $existingOrigin = (Invoke-NativeQuiet { & git remote get-url origin })
        if (-not $existingOrigin) {
            & git remote add origin $remoteUrl
        } elseif ($existingOrigin -ne $remoteUrl) {
            & git remote set-url origin $remoteUrl
        }
        & git push -u origin main
    } else {
        $visibilityFlag = if ($Private.IsPresent) { '--private' } else { '--public' }
        Write-Host "Creating GitHub repository $fullRepo ($visibilityFlag) and pushing..." -ForegroundColor Cyan
        & gh repo create $fullRepo $visibilityFlag --source=. --remote=origin --push
    }

    Write-Host ''
    Write-Host '=== Publish Complete! ===' -ForegroundColor Green
    Write-Host 'After rebooting your laptop, open PowerShell and run:' -ForegroundColor Cyan
    Write-Host "  irm https://raw.githubusercontent.com/$fullRepo/main/setup.ps1 | iex" -ForegroundColor Yellow
    if ($Private.IsPresent) {
        Write-Host 'Note: Raw GitHub URLs without a token only work for public repositories.' -ForegroundColor Yellow
    }
} finally {
    Pop-Location
}
