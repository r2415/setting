[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'Continue'

$failures = 0

function Assert-Check {
    param(
        [string]$Name,
        [bool]$Passed,
        [string]$Detail = ''
    )
    if ($Passed) {
        if ($Detail) {
            Write-Host "[PASS] $Name ($Detail)" -ForegroundColor Green
        } else {
            Write-Host "[PASS] $Name" -ForegroundColor Green
        }
    } else {
        if ($Detail) {
            Write-Host "[FAIL] $Name ($Detail)" -ForegroundColor Red
        } else {
            Write-Host "[FAIL] $Name" -ForegroundColor Red
        }
        $script:failures++
    }
}

# Refresh PATH from persistent registry values (simulates newly launched terminal)
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
$env:Path = (@($userPath, $machinePath) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join ';'

# 1. Verify required commands in persistent PATH (excluding 0-byte WindowsApps stubs)
$requiredCommands = @('code', 'git', 'python', 'pip', 'node', 'npm', 'gh', 'uv', 'agy')
foreach ($cmd in $requiredCommands) {
    $found = Get-Command $cmd -ErrorAction SilentlyContinue
    if ($found) {
        $isZeroStub = $false
        if ($found.Source -like '*\Microsoft\WindowsApps\*') {
            $item = Get-Item -LiteralPath $found.Source -ErrorAction SilentlyContinue
            if (-not $item -or $item.Length -eq 0) { $isZeroStub = $true }
        }
        if ($isZeroStub) {
            Assert-Check -Name "Command: $cmd" -Passed $false -Detail "Resolved to WindowsApps stub: $($found.Source)"
        } else {
            Assert-Check -Name "Command: $cmd" -Passed $true -Detail $found.Source
        }
    } else {
        Assert-Check -Name "Command: $cmd" -Passed $false -Detail 'Not found in persistent PATH'
    }
}

# 2. Verify superpowers plugin directory
$pluginDir = Join-Path $env:USERPROFILE '.gemini\config\plugins\superpowers'
$pluginExists = (Test-Path $pluginDir) -and (@(Get-ChildItem $pluginDir -ErrorAction SilentlyContinue).Count -gt 0)
Assert-Check -Name 'superpowers plugin directory' -Passed $pluginExists -Detail $pluginDir

# 3. Verify Git global config
$gitCmd = Get-Command git -ErrorAction SilentlyContinue
if ($gitCmd) {
    $gitName = (& git config --global user.name 2>$null)
    $gitEmail = (& git config --global user.email 2>$null)
    $gitBranch = (& git config --global init.defaultBranch 2>$null)
    $gitAutocrlf = (& git config --global core.autocrlf 2>$null)

    Assert-Check -Name 'git user.name' -Passed ($gitName -eq 'r2415') -Detail "actual='$gitName'"
    Assert-Check -Name 'git user.email' -Passed ($gitEmail -eq 'pjs9785@korea.ac.kr') -Detail "actual='$gitEmail'"
    Assert-Check -Name 'git init.defaultBranch' -Passed ($gitBranch -eq 'main') -Detail "actual='$gitBranch'"
    Assert-Check -Name 'git core.autocrlf' -Passed ($gitAutocrlf -eq 'true') -Detail "actual='$gitAutocrlf'"
} else {
    Assert-Check -Name 'git global config' -Passed $false -Detail 'git command unavailable'
}

# 4. Verify VS Code settings.json and preserved existing keys
$settingsPath = Join-Path $env:APPDATA 'Code\User\settings.json'
if (Test-Path $settingsPath) {
    try {
        $rawJson = [System.IO.File]::ReadAllText($settingsPath, [System.Text.Encoding]::UTF8)
        $parsed = $rawJson | ConvertFrom-Json -ErrorAction Stop
        $hasAutoSave = [bool]($parsed.PSObject.Properties['files.autoSave'] -and $parsed.'files.autoSave')
        $hasPyInterp = [bool]($parsed.PSObject.Properties['python.defaultInterpreterPath'] -and ($parsed.'python.defaultInterpreterPath' -like '*Python313*'))
        Assert-Check -Name 'VS Code settings.json valid & files.autoSave set' -Passed $hasAutoSave -Detail $settingsPath
        Assert-Check -Name 'VS Code settings.json preserved python.defaultInterpreterPath' -Passed $hasPyInterp -Detail $parsed.'python.defaultInterpreterPath'
    } catch {
        Assert-Check -Name 'VS Code settings.json valid JSON' -Passed $false -Detail $_.Exception.Message
    }
} else {
    Assert-Check -Name 'VS Code settings.json exists' -Passed $false -Detail $settingsPath
}

# 5. Verify no duplicate entries in User PATH
if ($userPath) {
    $entries = $userPath -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim().TrimEnd('\').ToLowerInvariant() }
    $uniqueCount = ($entries | Select-Object -Unique).Count
    Assert-Check -Name 'User PATH has no duplicates' -Passed ($entries.Count -eq $uniqueCount) -Detail "$($entries.Count) entries, $uniqueCount unique"
} else {
    Assert-Check -Name 'User PATH non-empty' -Passed $false -Detail 'User PATH is empty'
}

# 6. Unit checks on setup.ps1 helpers (JSONC comments/trailing commas & PATH dedup)
$setupFile = Join-Path (Split-Path -Parent $PSScriptRoot) 'setup.ps1'
if (Test-Path $setupFile) {
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($setupFile, [ref]$null, [ref]$null)
    $helperNames = @('Normalize-PathEntry', 'Update-PathString', 'ConvertFrom-JsonLenient')
    foreach ($fn in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $helperNames -contains $n.Name }, $true)) {
        Invoke-Expression $fn.Extent.Text
    }

    $jsoncSample = @"
{
    // single line comment with "http://example.com" inside string
    "url": "https://example.com/a//b",
    /* block
       comment */
    "flag": true,
}
"@
    try {
        $parsedJsonc = ConvertFrom-JsonLenient -JsonText $jsoncSample
        $jsoncOk = ($parsedJsonc.url -eq 'https://example.com/a//b') -and ($parsedJsonc.flag -eq $true)
        Assert-Check -Name 'Helper: ConvertFrom-JsonLenient handles JSONC & trailing commas' -Passed $jsoncOk
    } catch {
        Assert-Check -Name 'Helper: ConvertFrom-JsonLenient handles JSONC & trailing commas' -Passed $false -Detail $_.Exception.Message
    }

    $dupRes = Update-PathString -PathString 'C:\Tools\;c:\tools;C:\Other' -TargetNorm 'C:\Tools'
    Assert-Check -Name 'Helper: Update-PathString deduplicates case-insensitively' -Passed ($dupRes -eq 'C:\Tools;C:\Other') -Detail "result='$dupRes'"
}

Write-Host ''
if ($failures -gt 0) {
    Write-Host "Verification failed with $failures failure(s)." -ForegroundColor Red
    exit 1
} else {
    Write-Host 'All verification checks passed!' -ForegroundColor Green
    exit 0
}
