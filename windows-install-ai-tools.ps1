# AI Coding Tools Installation Script for Windows
# Run the latest version with:
# iwr -useb https://raw.githubusercontent.com/radiant-ai-hub/ai_install/main/windows-install-ai-tools.ps1 | iex

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$DefaultPythonVersion = if ($env:DEFAULT_PYTHON_VERSION) { $env:DEFAULT_PYTHON_VERSION } else { "3.13.12" }

Write-Host "Rady School of Management @ UCSD" -ForegroundColor Cyan
Write-Host "AI Coding Tools Installer for Windows" -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Note: Anthropic currently documents Claude Code support on Windows via WSL." -ForegroundColor Yellow
Write-Host "This script still installs the CLI tools natively plus Git Bash." -ForegroundColor Yellow
Write-Host ""

function Refresh-Path {
    $machine = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $user = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machine;$user"
}

function Ensure-UserPathEntry {
    param([string]$Entry)

    $currentUserPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $parts = @()
    if ($currentUserPath) {
        $parts = $currentUserPath -split ';' | Where-Object { $_ }
    }

    if ($parts -notcontains $Entry) {
        $newPath = if ($currentUserPath) { "$currentUserPath;$Entry" } else { $Entry }
        [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
    }

    Refresh-Path
}

function Find-VSCodeCommand {
    $candidates = @(
        "$env:LOCALAPPDATA\Programs\Microsoft VS Code\bin\code.cmd",
        "$env:LOCALAPPDATA\Programs\Microsoft VS Code\bin\code.exe",
        "$env:ProgramFiles\Microsoft VS Code\bin\code.cmd",
        "$env:ProgramFiles\Microsoft VS Code\bin\code.exe",
        "${env:ProgramFiles(x86)}\Microsoft VS Code\bin\code.cmd",
        "${env:ProgramFiles(x86)}\Microsoft VS Code\bin\code.exe"
    )

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path $candidate)) {
            return $candidate
        }
    }

    return $null
}

function Ensure-VSCodeCliPath {
    $codeCommand = Find-VSCodeCommand
    if (-not $codeCommand) {
        throw "Visual Studio Code installed, but the CLI could not be found in expected locations."
    }

    Ensure-UserPathEntry (Split-Path -Parent $codeCommand)
    return $codeCommand
}

function Test-WingetPackageInstalled {
    param([string]$Id)

    try {
        $output = winget list --exact --id $Id --accept-source-agreements 2>$null | Out-String
        return $output -match [regex]::Escape($Id)
    } catch {
        return $false
    }
}

function Install-OrUpgradeWingetPackage {
    param(
        [string]$Id,
        [string]$Name,
        [string]$OverrideArgs = ""
    )

    $commonArgs = @(
        "--exact",
        "--id", $Id,
        "--source", "winget",
        "--scope", "user",
        "--accept-package-agreements",
        "--accept-source-agreements",
        "--silent",
        "--disable-interactivity"
    )

    if (Test-WingetPackageInstalled -Id $Id) {
        Write-Host "   $Name already installed. Skipping install." -ForegroundColor Gray
        return
    }

    Write-Host "   Installing $Name..." -ForegroundColor Gray
    $installArgs = @("install") + $commonArgs
    if ($OverrideArgs) {
        $installArgs += @("--override", $OverrideArgs)
    }
    & winget @installArgs
}

function Install-Uv {
    Write-Host "Step 5: Installing uv..." -ForegroundColor Yellow
    if (Get-Command uv -ErrorAction SilentlyContinue) {
        Write-Host "   uv already installed. Updating if possible..." -ForegroundColor Gray
        uv self update | Out-Host
    } else {
        $UvInstaller = Join-Path $env:TEMP "uv-install.ps1"
        Invoke-WebRequest https://astral.sh/uv/install.ps1 -OutFile $UvInstaller
        powershell -ExecutionPolicy Bypass -File $UvInstaller
    }

    Ensure-UserPathEntry "$env:USERPROFILE\.local\bin"
    Refresh-Path
    Write-Host ""
}

function Install-NpmGlobalPackage {
    param(
        [string]$PackageName,
        [string]$CommandName
    )

    $installed = $false
    try {
        $null = npm list -g --depth=0 $PackageName 2>$null
        if ($LASTEXITCODE -eq 0) {
            $installed = $true
        }
    } catch {
        $installed = $false
    }

    if ($installed) {
        Write-Host "   Updating $PackageName..." -ForegroundColor Gray
    } else {
        Write-Host "   Installing $PackageName..." -ForegroundColor Gray
    }

    npm install -g $PackageName | Out-Host

    if (-not (Get-Command $CommandName -ErrorAction SilentlyContinue)) {
        throw "Command '$CommandName' is not available after installing $PackageName."
    }
}

function Verify-Command {
    param(
        [string]$Name,
        [scriptblock]$Script
    )

    Write-Host "   Verifying $Name..." -ForegroundColor Gray
    & $Script
}

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    throw "winget is required on Windows for this installer."
}

Write-Host "Step 1: Installing Git for Windows (includes Git Bash)..." -ForegroundColor Yellow
Install-OrUpgradeWingetPackage `
    -Id "Git.Git" `
    -Name "Git for Windows" `
    -OverrideArgs "/VERYSILENT /NORESTART"
Write-Host ""

Write-Host "Step 2: Installing Visual Studio Code..." -ForegroundColor Yellow
Install-OrUpgradeWingetPackage `
    -Id "Microsoft.VisualStudioCode" `
    -Name "Visual Studio Code" `
    -OverrideArgs "/VERYSILENT /MERGETASKS=!runcode,addtopath"
$CodeCommand = Ensure-VSCodeCliPath
Write-Host ""

Write-Host "Step 3: Installing Node.js LTS..." -ForegroundColor Yellow
Install-OrUpgradeWingetPackage `
    -Id "OpenJS.NodeJS.LTS" `
    -Name "Node.js LTS"
Ensure-UserPathEntry "$env:APPDATA\npm"
Refresh-Path
Write-Host ""

Write-Host "Step 4: Installing GitHub CLI..." -ForegroundColor Yellow
Install-OrUpgradeWingetPackage `
    -Id "GitHub.cli" `
    -Name "GitHub CLI"
Refresh-Path
Write-Host ""

Install-Uv

Write-Host "Step 6: Installing UV-managed Python $DefaultPythonVersion..." -ForegroundColor Yellow
uv python install --default $DefaultPythonVersion | Out-Host
Refresh-Path
Write-Host ""

Write-Host "Step 7: Installing Claude Code and Codex..." -ForegroundColor Yellow
Install-NpmGlobalPackage -PackageName "@anthropic-ai/claude-code" -CommandName "claude"
Install-NpmGlobalPackage -PackageName "@openai/codex" -CommandName "codex"
Write-Host ""

Write-Host "Step 8: Verifying installed tools..." -ForegroundColor Yellow
Verify-Command "git" { git --version | Out-Host }
Verify-Command "bash" { bash --version | Select-Object -First 1 | Out-Host }
Verify-Command "node" { node --version | Out-Host }
Verify-Command "npm" { npm --version | Out-Host }
Verify-Command "gh" { gh --version | Select-Object -First 1 | Out-Host }
Verify-Command "uv" { uv --version | Out-Host }
Verify-Command "python" { python --version | Out-Host }
Verify-Command "code" { & $CodeCommand --version | Select-Object -First 1 | Out-Host }
Verify-Command "claude" { claude --version | Out-Host }
Verify-Command "codex" { codex --version | Out-Host }
Write-Host ""

Write-Host "Installation complete." -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. Launch VS Code."
Write-Host "  2. Run 'gh auth login' if you want GitHub CLI auth."
Write-Host "  3. Run 'claude' to authenticate Claude Code."
Write-Host "  4. Run 'codex login' to authenticate Codex."
