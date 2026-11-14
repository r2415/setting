param(
    [switch]$SkipAuth,
    [string]$GitName = 'r2415',
    [string]$GitEmail = 'pjs9785@korea.ac.kr'
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Write-Step {
    param([string]$Message)
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Write-Ok {
    param([string]$Message)
    Write-Host "  [OK] $Message" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Message)
    Write-Host "  [WARN] $Message" -ForegroundColor Yellow
}

function Normalize-PathEntry {
    param([string]$PathValue)
    if ([string]::IsNullOrWhiteSpace($PathValue)) { return '' }
    $trimmed = $PathValue.Trim()
    if ($trimmed -match '^[A-Za-z]:\\$') { return $trimmed }
    return $trimmed.TrimEnd('\')
}

function Test-RealCommand {
    param([string]$Name)
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if (-not $cmd) { return $false }
    if ($cmd.Source -like '*\Microsoft\WindowsApps\*') {
        $item = Get-Item -LiteralPath $cmd.Source -ErrorAction SilentlyContinue
        if (-not $item -or $item.Length -eq 0) { return $false }
    }
    return $true
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

function Test-GhAuthenticated {
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { return $false }
    Invoke-NativeQuiet { & gh auth status | Out-Null } | Out-Null
    return ($LASTEXITCODE -eq 0)
}

function Update-PathString {
    param(
        [string]$PathString,
        [string]$TargetNorm,
        [switch]$Prepend
    )

    $list = New-Object System.Collections.Generic.List[string]
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

    if (-not [string]::IsNullOrWhiteSpace($PathString)) {
        foreach ($raw in ($PathString -split ';')) {
            $norm = Normalize-PathEntry $raw
            if ($norm -and $seen.Add($norm)) {
                $list.Add($norm)
            }
        }
    }

    $existingIdx = -1
    $winAppsIdx = -1
    for ($i = 0; $i -lt $list.Count; $i++) {
        if ($list[$i].Equals($TargetNorm, [System.StringComparison]::OrdinalIgnoreCase)) {
            $existingIdx = $i
        }
        if ($winAppsIdx -lt 0 -and $list[$i] -like '*\Microsoft\WindowsApps*') {
            $winAppsIdx = $i
        }
    }

    if ($existingIdx -lt 0) {
        if ($Prepend) {
            $list.Insert(0, $TargetNorm)
        } else {
            $list.Add($TargetNorm)
        }
    } elseif ($Prepend -and $winAppsIdx -ge 0 -and $existingIdx -gt $winAppsIdx) {
        $list.RemoveAt($existingIdx)
        $list.Insert($winAppsIdx, $TargetNorm)
    }

    $joined = $list -join ';'
    if ($joined -eq $PathString) { return $null }
    return $joined
}

function Add-ToUserPath {
    param(
        [string]$Directory,
        [switch]$Prepend
    )

    if ([string]::IsNullOrWhiteSpace($Directory)) { return }
    if (-not (Test-Path -LiteralPath $Directory -PathType Container)) { return }

    $targetNorm = Normalize-PathEntry $Directory

    $rawUserPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $newUserPath = Update-PathString -PathString $rawUserPath -TargetNorm $targetNorm -Prepend:$Prepend
    if ($null -ne $newUserPath) {
        [Environment]::SetEnvironmentVariable('Path', $newUserPath, 'User')
    }

    $newProcPath = Update-PathString -PathString $env:Path -TargetNorm $targetNorm -Prepend:$Prepend
    if ($null -ne $newProcPath) {
        $env:Path = $newProcPath
    }
}

function Refresh-SessionPath {
    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $combined = @($userPath, $machinePath) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    $list = New-Object System.Collections.Generic.List[string]
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($raw in (($combined -join ';') -split ';')) {
        $norm = Normalize-PathEntry $raw
        if ($norm -and $seen.Add($norm)) {
            $list.Add($norm)
        }
    }
    $env:Path = $list -join ';'
}

function Restore-ExistingTools {
    Write-Step '[1/6] Checking and restoring pre-installed tools to PATH'

    # Pull latest persistent Machine + User PATH into this session first (e.g. Scoop app dirs)
    Refresh-SessionPath

    $candidateDirs = New-Object System.Collections.Generic.List[string]

    # Collect in desired final precedence order (highest priority first)
    $candidateDirs.Add((Join-Path $env:USERPROFILE 'scoop\shims'))
    $candidateDirs.Add((Join-Path $env:LOCALAPPDATA 'agy\bin'))

    $pythonRoot = Join-Path $env:LOCALAPPDATA 'Programs\Python'
    if (Test-Path -LiteralPath $pythonRoot -PathType Container) {
        $pyVersions = Get-ChildItem -LiteralPath $pythonRoot -Directory -Filter 'Python*' -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending
        foreach ($py in $pyVersions) {
            $candidateDirs.Add($py.FullName)
            $candidateDirs.Add((Join-Path $py.FullName 'Scripts'))
        }
        $candidateDirs.Add((Join-Path $pythonRoot 'Launcher'))
    }

    $candidateDirs.Add((Join-Path $env:LOCALAPPDATA 'Programs\Microsoft VS Code\bin'))
    $candidateDirs.Add((Join-Path $env:ProgramFiles 'Microsoft VS Code\bin'))
    $candidateDirs.Add((Join-Path $env:LOCALAPPDATA 'Programs\Git\cmd'))
    $candidateDirs.Add((Join-Path $env:ProgramFiles 'Git\cmd'))

    # Prepend in reverse order so higher-priority directories end up first
    for ($i = $candidateDirs.Count - 1; $i -ge 0; $i--) {
        $dir = $candidateDirs[$i]
        if (Test-Path -LiteralPath $dir -PathType Container) {
            Add-ToUserPath -Directory $dir -Prepend
            Write-Ok "PATH linked: $dir"
        }
    }
}

function Install-ScoopIfMissing {
    Write-Step '[2/6] Bootstrapping Scoop (user-scope package manager)'

    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    } catch {
        Write-Warn "Could not set TLS 1.2 explicitly: $($_.Exception.Message)"
    }

    try {
        $policy = Get-ExecutionPolicy -Scope CurrentUser -ErrorAction SilentlyContinue
        if ($policy -notin @('RemoteSigned', 'Unrestricted', 'Bypass')) {
            Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force -ErrorAction Stop
            Write-Ok 'ExecutionPolicy (CurrentUser) set to RemoteSigned'
        }
    } catch {
        Write-Warn "ExecutionPolicy update skipped (already governed or restricted): $($_.Exception.Message)"
    }

    $scoopShim = Join-Path $env:USERPROFILE 'scoop\shims\scoop.ps1'
    if ((Get-Command scoop -ErrorAction SilentlyContinue) -or (Test-Path -LiteralPath $scoopShim)) {
        Add-ToUserPath -Directory (Join-Path $env:USERPROFILE 'scoop\shims') -Prepend
        Write-Ok 'Scoop is already installed'
        return
    }

    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )

    if ($isAdmin) {
        Write-Warn 'Administrator session detected; installing Scoop with -RunAsAdmin'
        $tempInstaller = Join-Path $env:TEMP 'install-scoop.ps1'
        Invoke-RestMethod -Uri 'https://get.scoop.sh' | Out-File -FilePath $tempInstaller -Encoding UTF8
        & $tempInstaller -RunAsAdmin
        Remove-Item -LiteralPath $tempInstaller -Force -ErrorAction SilentlyContinue
    } else {
        Invoke-RestMethod -Uri 'https://get.scoop.sh' | Invoke-Expression
    }

    Add-ToUserPath -Directory (Join-Path $env:USERPROFILE 'scoop\shims') -Prepend
    if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
        throw 'Scoop installation completed, but scoop command was not found in PATH.'
    }
    Write-Ok 'Scoop installed successfully'
}

function Install-ScoopPackageIfMissing {
    param(
        [string]$PackageName,
        [string]$CommandName,
        [string]$Bucket = ''
    )

    if (Test-RealCommand $CommandName) {
        Write-Ok "$CommandName is already available"
        return
    }

    if ($Bucket) {
        $buckets = (Invoke-NativeQuiet { & scoop bucket list } | Out-String)
        if ($buckets -notmatch "(?m)^\s*$([regex]::Escape($Bucket))\b") {
            Write-Host "  Adding Scoop bucket: $Bucket" -ForegroundColor Gray
            & scoop bucket add $Bucket
        }
    }

    Write-Host "  Installing $PackageName via Scoop..." -ForegroundColor Gray
    & scoop install $PackageName
    Refresh-SessionPath

    if (Test-RealCommand $CommandName) {
        Write-Ok "$PackageName installed ($CommandName)"
    } else {
        Write-Warn "$PackageName installed, but '$CommandName' was not detected in current PATH"
    }
}

function Install-DevPackages {
    Write-Step '[3/6] Installing missing development tools via Scoop'

    # Install Git first so Scoop bucket commands work on clean machines
    Install-ScoopPackageIfMissing -PackageName 'git' -CommandName 'git'
    Install-ScoopPackageIfMissing -PackageName 'nodejs-lts' -CommandName 'node'
    Install-ScoopPackageIfMissing -PackageName 'gh' -CommandName 'gh'
    Install-ScoopPackageIfMissing -PackageName 'uv' -CommandName 'uv'
    Install-ScoopPackageIfMissing -PackageName 'python' -CommandName 'python'
    Install-ScoopPackageIfMissing -PackageName 'vscode' -CommandName 'code' -Bucket 'extras'

    Refresh-SessionPath
}

function Install-AgyAndSuperpowers {
    Write-Step '[4/6] Installing Antigravity (agy) and superpowers plugin'

    $agyBin = Join-Path $env:LOCALAPPDATA 'agy\bin'
    if (-not (Get-Command agy -ErrorAction SilentlyContinue)) {
        if (Test-Path -LiteralPath (Join-Path $agyBin 'agy.exe')) {
            Add-ToUserPath -Directory $agyBin -Prepend
        } else {
            Write-Host '  Installing agy CLI...' -ForegroundColor Gray
            Invoke-RestMethod -Uri 'https://antigravity.google/cli/install.ps1' | Invoke-Expression
            Add-ToUserPath -Directory $agyBin -Prepend
        }
    }

    if (Get-Command agy -ErrorAction SilentlyContinue) {
        Write-Ok 'agy CLI is ready'
    } else {
        Write-Warn 'agy CLI not found after install step'
    }

    $pluginsRoot = Join-Path $env:USERPROFILE '.gemini\config\plugins'
    $superpowersDir = Join-Path $pluginsRoot 'superpowers'

    if ((Test-Path -LiteralPath $superpowersDir) -and (@(Get-ChildItem -LiteralPath $superpowersDir -ErrorAction SilentlyContinue).Count -gt 0)) {
        Write-Ok "superpowers plugin already installed ($superpowersDir)"
        return
    }

    if (Get-Command agy -ErrorAction SilentlyContinue) {
        Write-Host '  Trying: agy plugin install superpowers' -ForegroundColor Gray
        try {
            Invoke-NativeQuiet { & agy plugin install superpowers | Out-Null } | Out-Null
        } catch {
            Write-Warn "agy plugin install did not complete cleanly: $($_.Exception.Message)"
        }
    }

    if (-not ((Test-Path -LiteralPath $superpowersDir) -and (@(Get-ChildItem -LiteralPath $superpowersDir -ErrorAction SilentlyContinue).Count -gt 0))) {
        Write-Warn 'Falling back to direct git clone for superpowers plugin'
        if (-not (Test-Path -LiteralPath $pluginsRoot)) {
            New-Item -ItemType Directory -Path $pluginsRoot -Force | Out-Null
        }
        if (Test-Path -LiteralPath $superpowersDir) {
            Remove-Item -LiteralPath $superpowersDir -Recurse -Force -ErrorAction SilentlyContinue
        }
        $oldPref = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            & git clone 'https://github.com/obra/superpowers.git' $superpowersDir
        } finally {
            $ErrorActionPreference = $oldPref
        }
    }

    if (Test-Path -LiteralPath $superpowersDir) {
        Write-Ok "superpowers plugin ready ($superpowersDir)"
    } else {
        Write-Warn 'superpowers plugin installation failed'
    }
}

function ConvertFrom-JsonLenient {
    param([string]$JsonText)

    if ([string]::IsNullOrWhiteSpace($JsonText)) {
        return [PSCustomObject]@{}
    }

    # Strip // and /* */ comments only outside JSON double-quoted strings
    $stripped = [regex]::Replace(
        $JsonText,
        '"(?:\\.|[^"\\])*"|/\*[\s\S]*?\*/|//[^\r\n]*',
        {
            param($m)
            if ($m.Value.StartsWith('"')) { return $m.Value }
            return ''
        }
    )

    # Remove trailing commas before } or ]
    $stripped = [regex]::Replace($stripped, ',(?=\s*[\}\]])', '')

    if ([string]::IsNullOrWhiteSpace($stripped)) {
        return [PSCustomObject]@{}
    }

    return ($stripped | ConvertFrom-Json -ErrorAction Stop)
}

function Set-VSCodeEnvironment {
    param([string[]]$Extensions)

    $codeCmd = Get-Command code -ErrorAction SilentlyContinue
    if ($codeCmd) {
        $rawExts = Invoke-NativeQuiet { & $codeCmd.Source --list-extensions }
        $installed = @($rawExts | Where-Object { $_ } | ForEach-Object { $_.ToString().Trim().ToLowerInvariant() })
        foreach ($ext in $Extensions) {
            if ($installed -contains $ext.ToLowerInvariant()) {
                Write-Ok "VS Code extension present: $ext"
            } else {
                Write-Host "  Installing VS Code extension: $ext" -ForegroundColor Gray
                try {
                    Invoke-NativeQuiet { & $codeCmd.Source --install-extension $ext | Out-Null } | Out-Null
                    if ($LASTEXITCODE -eq 0) {
                        Write-Ok "Installed extension: $ext"
                    } else {
                        Write-Warn "Extension install returned exit code $LASTEXITCODE for $ext"
                    }
                } catch {
                    Write-Warn "Failed to install extension ${ext}: $($_.Exception.Message)"
                }
            }
        }
    } else {
        Write-Warn 'code CLI not found; skipping VS Code extension installation'
    }

    $userDir = Join-Path $env:APPDATA 'Code\User'
    $settingsPath = Join-Path $userDir 'settings.json'

    if (-not (Test-Path -LiteralPath $userDir -PathType Container)) {
        New-Item -ItemType Directory -Path $userDir -Force | Out-Null
    }

    $currentObj = [PSCustomObject]@{}
    if (Test-Path -LiteralPath $settingsPath -PathType Leaf) {
        try {
            $raw = [System.IO.File]::ReadAllText($settingsPath, [System.Text.Encoding]::UTF8)
            $parsed = ConvertFrom-JsonLenient -JsonText $raw
            if ($null -ne $parsed) {
                $currentObj = $parsed
            }
        } catch {
            $backupPath = "$settingsPath.bak"
            Copy-Item -LiteralPath $settingsPath -Destination $backupPath -Force -ErrorAction SilentlyContinue
            Write-Warn "Existing VS Code settings.json was invalid; backed up to $backupPath and recreated"
            $currentObj = [PSCustomObject]@{}
        }
    }

    $merged = [ordered]@{}
    foreach ($prop in $currentObj.PSObject.Properties) {
        $merged[$prop.Name] = $prop.Value
    }

    $defaults = [ordered]@{
        'files.autoSave'                          = 'afterDelay'
        'files.autoSaveDelay'                     = 1000
        'editor.formatOnSave'                     = $true
        'editor.tabSize'                          = 2
        'terminal.integrated.defaultProfile.windows' = 'PowerShell'
    }

    foreach ($key in $defaults.Keys) {
        if (-not $merged.Contains($key)) {
            $merged[$key] = $defaults[$key]
        }
    }

    $jsonOut = ([PSCustomObject]$merged | ConvertTo-Json -Depth 10) + [Environment]::NewLine
    [System.IO.File]::WriteAllText($settingsPath, $jsonOut, [System.Text.UTF8Encoding]::new($false))
    Write-Ok "VS Code settings updated: $settingsPath"
}

function Set-GitAndVSCodeConfig {
    param(
        [string]$UserName,
        [string]$UserEmail
    )

    Write-Step '[5/6] Configuring Git and VS Code environment'

    if (Get-Command git -ErrorAction SilentlyContinue) {
        & git config --global user.name $UserName
        & git config --global user.email $UserEmail
        & git config --global init.defaultBranch main
        & git config --global core.autocrlf true
        Write-Ok "Git configured: $UserName <$UserEmail> (branch=main, autocrlf=true)"
    } else {
        Write-Warn 'git command not found; skipping Git configuration'
    }

    if (Test-GhAuthenticated) {
        Invoke-NativeQuiet { & gh auth setup-git | Out-Null } | Out-Null
        Write-Ok 'GitHub git credential helper linked (gh auth setup-git)'
    }

    $extensions = @(
        'ms-ceintl.vscode-language-pack-ko',
        'ms-python.python',
        'esbenp.prettier-vscode',
        'dbaeumer.vscode-eslint',
        'eamodio.gitlens',
        'PKief.material-icon-theme'
    )
    Set-VSCodeEnvironment -Extensions $extensions
}

function Get-ToolVersionLine {
    param(
        [string]$CommandName,
        [string[]]$VersionArgs
    )

    if (-not (Test-RealCommand $CommandName)) {
        return 'MISSING'
    }

    $oldPref = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $out = & $CommandName @VersionArgs 2>&1 | Select-Object -First 1
        if ($out) { return $out.ToString().Trim() }
        return 'INSTALLED'
    } catch {
        return 'INSTALLED'
    } finally {
        $ErrorActionPreference = $oldPref
    }
}

function Show-EnvironmentSummary {
    Write-Step '[6/6] Environment verification summary'

    $items = @(
        [PSCustomObject]@{ Tool = 'VS Code (code)'; Status = (Get-ToolVersionLine 'code' @('--version')) },
        [PSCustomObject]@{ Tool = 'Git';            Status = (Get-ToolVersionLine 'git' @('--version')) },
        [PSCustomObject]@{ Tool = 'Python';         Status = (Get-ToolVersionLine 'python' @('--version')) },
        [PSCustomObject]@{ Tool = 'pip';            Status = (Get-ToolVersionLine 'pip' @('--version')) },
        [PSCustomObject]@{ Tool = 'Node.js';        Status = (Get-ToolVersionLine 'node' @('--version')) },
        [PSCustomObject]@{ Tool = 'npm';            Status = (Get-ToolVersionLine 'npm' @('--version')) },
        [PSCustomObject]@{ Tool = 'GitHub CLI';     Status = (Get-ToolVersionLine 'gh' @('--version')) },
        [PSCustomObject]@{ Tool = 'uv';             Status = (Get-ToolVersionLine 'uv' @('--version')) },
        [PSCustomObject]@{ Tool = 'Antigravity';    Status = (Get-ToolVersionLine 'agy' @('--version')) }
    )

    $pluginDir = Join-Path $env:USERPROFILE '.gemini\config\plugins\superpowers'
    $pluginStatus = if (Test-Path -LiteralPath $pluginDir) { "OK ($pluginDir)" } else { 'MISSING' }
    $items += [PSCustomObject]@{ Tool = 'superpowers'; Status = $pluginStatus }

    if (Get-Command git -ErrorAction SilentlyContinue) {
        $gn = (Invoke-NativeQuiet { & git config --global user.name })
        $ge = (Invoke-NativeQuiet { & git config --global user.email })
        $items += [PSCustomObject]@{ Tool = 'Git Identity'; Status = "$gn <$ge>" }
    }

    $items | Format-Table -AutoSize | Out-String | Write-Host
}

function Start-InteractiveAuth {
    param([bool]$ShouldSkip)

    if ($ShouldSkip) {
        Write-Host 'Skipping interactive authentication (-SkipAuth or SETUP_SKIP_AUTH=1).' -ForegroundColor DarkGray
        return
    }

    Write-Step 'Interactive Authentication (GitHub & Antigravity)'

    if (Get-Command gh -ErrorAction SilentlyContinue) {
        if (-not (Test-GhAuthenticated)) {
            $answer = Read-Host 'GitHub is not logged in yet. Launch browser login (gh auth login) now? [Y/n]'
            if ([string]::IsNullOrWhiteSpace($answer) -or $answer -match '^[Yy]') {
                & gh auth login --web -p https
                if ($LASTEXITCODE -eq 0) {
                    & gh auth setup-git
                    Write-Ok 'GitHub authentication and git credentials configured!'
                }
            }
        } else {
            Write-Ok 'GitHub CLI is already authenticated'
        }
    }

    Write-Host ''
    Write-Host 'Next steps:' -ForegroundColor Cyan
    Write-Host '  - Run "agy" in terminal if Antigravity account sign-in is needed.' -ForegroundColor White
    Write-Host '  - Your environment is ready to use in this terminal immediately!' -ForegroundColor White
}

# --- Main Execution ---
$effectiveSkipAuth = $SkipAuth.IsPresent -or ($env:SETUP_SKIP_AUTH -in @('1', 'true', 'TRUE', 'yes', 'YES'))

Restore-ExistingTools
Install-ScoopIfMissing
Install-DevPackages
Install-AgyAndSuperpowers
Set-GitAndVSCodeConfig -UserName $GitName -UserEmail $GitEmail
Show-EnvironmentSummary
Start-InteractiveAuth -ShouldSkip $effectiveSkipAuth
