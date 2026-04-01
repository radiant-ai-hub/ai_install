# AI Coding Tools Uninstall Script for Windows

$ErrorActionPreference = "SilentlyContinue"
$ProgressPreference = "SilentlyContinue"
$WindowsStorePythonId = "9PNRBTZXMB4Z"

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
                $global:LASTEXITCODE = 0
            }
        }
    } catch {
    }

    $global:LASTEXITCODE = 0
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

Write-Host "Step 1: Removing npm-installed CLIs..." -ForegroundColor Yellow
if (Get-Command npm -ErrorAction SilentlyContinue) {
    npm uninstall -g @anthropic-ai/claude-code | Out-Host
    npm uninstall -g @openai/codex | Out-Host
}
Write-Host ""

Write-Host "Step 2: Removing Microsoft Store Python and uv data..." -ForegroundColor Yellow
if (Get-Command winget -ErrorAction SilentlyContinue) {
    Winget-UninstallIfPresent -Id $WindowsStorePythonId -Source "msstore"
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
exit 0
