# AI Coding Tools Uninstall Script for Windows

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$PythonWingetId = "Python.Python.3.13"

if ($env:CI -ne "true") {
    Write-Host "This removes the tools installed by this repo." -ForegroundColor Yellow
    $confirmation = Read-Host "Type 'yes' to continue"
    if ($confirmation -ne "yes") {
        Write-Host "Uninstall cancelled." -ForegroundColor Yellow
        exit 0
    }
}

function Refresh-Path {
    $machine = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $user = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machine;$user"
}

function Reset-LastExitCode {
    $global:LASTEXITCODE = 0
}

function Winget-UninstallIfPresent {
    param(
        [string]$Id,
        [string]$Source = "winget"
    )

    try {
        $output = winget list --id $Id --source $Source --accept-source-agreements 2>$null | Out-String
        if ($output -match [regex]::Escape($Id)) {
            $uninstallArgs = @(
                "uninstall",
                "--id", $Id,
                "--source", $Source,
                "--silent",
                "--disable-interactivity"
            )
            if ($Source -eq "winget") {
                $uninstallArgs += @("--exact", "--scope", "user")
            }
            & winget @uninstallArgs | Out-Host
            if ($LASTEXITCODE -ne 0) {
                Write-Host "   Warning: winget could not uninstall $Id cleanly. Continuing." -ForegroundColor Yellow
                Reset-LastExitCode
            }
        }
    } catch {
    }

    Reset-LastExitCode
}

function Remove-UserPathEntry {
    param([string]$Entry)

    $currentUserPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if (-not $currentUserPath) {
        return
    }

    $newPath = ($currentUserPath -split ';' | Where-Object { $_ -and $_ -ne $Entry }) -join ';'
    [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
    Refresh-Path
}

function Remove-IfPresent {
    param([string]$Path)

    if (Test-Path $Path) {
        Remove-Item -Path $Path -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Remove-ChildItemsIfPresent {
    param([string]$Pattern)

    Get-ChildItem -Path $Pattern -Force -ErrorAction SilentlyContinue | ForEach-Object {
        Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Get-NpmGlobalPrefix {
    if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
        return $null
    }

    try {
        $prefix = (& npm prefix -g 2>$null | Out-String).Trim()
        Reset-LastExitCode
        if ($prefix) {
            return $prefix
        }
    } catch {
    }

    return "$env:APPDATA\npm"
}

function Get-NpmGlobalModulesPath {
    if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
        return $null
    }

    try {
        $modulesPath = (& npm root -g 2>$null | Out-String).Trim()
        Reset-LastExitCode
        if ($modulesPath) {
            return $modulesPath
        }
    } catch {
    }

    $prefix = Get-NpmGlobalPrefix
    if (-not $prefix) {
        return $null
    }

    return Join-Path $prefix "node_modules"
}

function Get-NpmGlobalPackagePath {
    param(
        [string]$ModulesPath,
        [string]$PackageName
    )

    if (-not $ModulesPath) {
        return $null
    }

    if ($PackageName -match '^@([^/]+)/(.+)$') {
        return Join-Path (Join-Path $ModulesPath $Matches[1]) $Matches[2]
    }

    return Join-Path $ModulesPath $PackageName
}

function Remove-NpmCommandShims {
    param(
        [string]$Prefix,
        [string[]]$CommandNames
    )

    if (-not $Prefix) {
        return
    }

    foreach ($commandName in $CommandNames) {
        foreach ($suffix in @("", ".cmd", ".ps1")) {
            Remove-IfPresent (Join-Path $Prefix "$commandName$suffix")
        }
    }

    Remove-ChildItemsIfPresent (Join-Path $Prefix "node_modules\.bin\claude*")
    Remove-ChildItemsIfPresent (Join-Path $Prefix "node_modules\.bin\codex*")
}

function Uninstall-NpmGlobalPackage {
    param(
        [string]$PackageName,
        [string[]]$CommandNames,
        [string]$Prefix,
        [string]$ModulesPath
    )

    $packagePath = Get-NpmGlobalPackagePath -ModulesPath $ModulesPath -PackageName $PackageName
    $packageInstalled = $packagePath -and (Test-Path $packagePath)

    if ($packageInstalled) {
        Write-Host "   Removing $PackageName..." -ForegroundColor Gray
        try {
            & npm uninstall -g $PackageName | Out-Host
        } catch {
        }
        Reset-LastExitCode
    } else {
        Write-Host "   $PackageName is not installed. Skipping npm uninstall." -ForegroundColor Gray
    }

    Remove-NpmCommandShims -Prefix $Prefix -CommandNames $CommandNames
    if ($packagePath) {
        Remove-IfPresent $packagePath
    }
}

function Remove-UserPathEntriesMatching {
    param([string[]]$Patterns)

    $currentUserPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if (-not $currentUserPath) {
        return
    }

    $newPathEntries = @()
    foreach ($entry in ($currentUserPath -split ';')) {
        if (-not $entry) {
            continue
        }

        $shouldRemove = $false
        foreach ($pattern in $Patterns) {
            if ($entry -match $pattern) {
                $shouldRemove = $true
                break
            }
        }

        if (-not $shouldRemove) {
            $newPathEntries += $entry
        }
    }

    [Environment]::SetEnvironmentVariable("Path", ($newPathEntries -join ';'), "User")
    Refresh-Path
}

Write-Host "Step 1: Removing npm-installed CLIs..." -ForegroundColor Yellow
if (Get-Command npm -ErrorAction SilentlyContinue) {
    $npmPrefix = Get-NpmGlobalPrefix
    $npmModulesPath = Get-NpmGlobalModulesPath
    Uninstall-NpmGlobalPackage -PackageName "@anthropic-ai/claude-code" -CommandNames @("claude") -Prefix $npmPrefix -ModulesPath $npmModulesPath
    Uninstall-NpmGlobalPackage -PackageName "@openai/codex" -CommandNames @("codex") -Prefix $npmPrefix -ModulesPath $npmModulesPath
    Remove-UserPathEntry $npmPrefix
} else {
    Write-Host "   npm is not available. Skipping npm package removal." -ForegroundColor Gray
}
Write-Host ""

Write-Host "Step 2: Removing Python and uv data..." -ForegroundColor Yellow
if (Get-Command winget -ErrorAction SilentlyContinue) {
    Winget-UninstallIfPresent -Id $PythonWingetId -Source "winget"
}
if (Get-Command uv -ErrorAction SilentlyContinue) {
    uv cache clean | Out-Host
}
Remove-IfPresent "$env:USERPROFILE\.local\bin\uv.exe"
Remove-IfPresent "$env:USERPROFILE\.local\bin\uvx.exe"
Remove-IfPresent "$env:USERPROFILE\.local\bin\uvw.exe"
Remove-IfPresent "$env:USERPROFILE\.local\share\uv"
Remove-IfPresent "$env:LOCALAPPDATA\uv"
Remove-UserPathEntry "$env:USERPROFILE\.local\bin"
Remove-UserPathEntriesMatching @(
    '\\Python313(\\Scripts)?$',
    '\\Python\\3\.13\.12\\(x64|arm64)(\\Scripts)?$'
)
Write-Host ""

Write-Host "Step 3: Removing winget-installed packages..." -ForegroundColor Yellow
if (Get-Command winget -ErrorAction SilentlyContinue) {
    Winget-UninstallIfPresent "OpenJS.NodeJS.LTS"
    Winget-UninstallIfPresent "Microsoft.VisualStudioCode"
    Winget-UninstallIfPresent "Git.Git"
}
Remove-IfPresent "$env:USERPROFILE\.local\gh"
Remove-IfPresent "$env:USERPROFILE\.local\bin\gh.exe"
Remove-UserPathEntry "$env:LOCALAPPDATA\Programs\Microsoft VS Code\bin"
Write-Host ""

Write-Host "Uninstall complete." -ForegroundColor Green
