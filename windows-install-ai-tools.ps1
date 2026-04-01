# AI Coding Tools Installation Script for Windows
# Run the latest version with:
# iwr -useb https://raw.githubusercontent.com/radiant-ai-hub/ai_install/main/windows-install-ai-tools.ps1 | iex

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$DefaultPythonVersion = if ($env:DEFAULT_PYTHON_VERSION) { $env:DEFAULT_PYTHON_VERSION } else { "3.13.12" }
$RepoRawBase = "https://raw.githubusercontent.com/radiant-ai-hub/ai_install/main"
$InstallerAssetCacheDir = Join-Path $env:TEMP "ai-install-assets"

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
    param(
        [string]$Entry,
        [switch]$Prepend
    )

    $currentUserPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $parts = @()
    if ($currentUserPath) {
        $parts = $currentUserPath -split ';' | Where-Object { $_ }
    }

    $filteredParts = $parts | Where-Object { $_ -ne $Entry }
    $newParts = if ($Prepend) { @($Entry) + $filteredParts } else { $filteredParts + @($Entry) }
    $newPath = $newParts -join ';'
    [Environment]::SetEnvironmentVariable("Path", $newPath, "User")

    Refresh-Path
}

function Get-WindowsArchitecture {
    $arch = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }

    switch -Regex ($arch.ToUpperInvariant()) {
        '^ARM64$' { return 'arm64' }
        '^AMD64$' { return 'amd64' }
        '^X86$' { return '386' }
        default { throw "Unsupported Windows architecture: $arch" }
    }
}

function Get-UvPythonRequest {
    param([string]$Version)

    $arch = Get-WindowsArchitecture
    if ($arch -eq "arm64") {
        return "cpython-$Version-windows-aarch64-none"
    }

    return $Version
}

function Get-CommandSource {
    param([string]$Name)

    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    return $null
}

function Get-InstallerAssetPath {
    param([string]$RelativePath)

    $relativePath = $RelativePath -replace '\\', '/'
    $localCandidates = @()

    if ($PSScriptRoot) {
        $localCandidates += (Join-Path $PSScriptRoot $relativePath)
    }

    $localCandidates += (Join-Path (Get-Location).Path $relativePath)

    foreach ($candidate in $localCandidates | Select-Object -Unique) {
        if ($candidate -and (Test-Path $candidate)) {
            return $candidate
        }
    }

    $destination = Join-Path $InstallerAssetCacheDir ($relativePath -replace '[\\/]', '_')
    if (-not (Test-Path $destination)) {
        New-Item -ItemType Directory -Path $InstallerAssetCacheDir -Force | Out-Null
        $uri = "$RepoRawBase/$relativePath"
        Invoke-WebRequest -Uri $uri -OutFile $destination
    }

    return $destination
}

function New-JsonObject {
    return [pscustomobject]@{}
}

function Set-JsonProperty {
    param(
        [object]$Object,
        [string]$Name,
        [object]$Value
    )

    $property = $Object.PSObject.Properties[$Name]
    if ($property) {
        $property.Value = $Value
    } else {
        $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
    }
}

function Get-OrCreateJsonObjectProperty {
    param(
        [object]$Object,
        [string]$Name
    )

    $property = $Object.PSObject.Properties[$Name]
    if ($property -and $property.Value) {
        return $property.Value
    }

    $child = New-JsonObject
    Set-JsonProperty -Object $Object -Name $Name -Value $child
    return $child
}

function Read-JsonFile {
    param([string]$Path)

    return (Get-Content $Path -Raw | ConvertFrom-Json)
}

function Write-JsonFile {
    param(
        [string]$Path,
        [object]$Object
    )

    New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null
    $Object | ConvertTo-Json -Depth 32 | Set-Content -Path $Path -Encoding UTF8
}

function Backup-FileIfPresent {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        return
    }

    $backupPath = "$Path.ai-install.backup"
    if (-not (Test-Path $backupPath)) {
        Copy-Item -Path $Path -Destination $backupPath -Force
    }
}

function Find-GitBashExecutable {
    $candidates = @(
        "$env:ProgramFiles\Git\bin\bash.exe",
        "$env:ProgramFiles\Git\git-bash.exe",
        "${env:ProgramFiles(x86)}\Git\bin\bash.exe",
        "${env:ProgramFiles(x86)}\Git\git-bash.exe"
    )

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path $candidate)) {
            return $candidate
        }
    }

    throw "Git Bash was not found after installing Git for Windows."
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

function Install-GitHubCli {
    Write-Host "Step 4: Installing GitHub CLI..." -ForegroundColor Yellow

    $arch = Get-WindowsArchitecture
    $token = if ($env:GITHUB_TOKEN) { $env:GITHUB_TOKEN } elseif ($env:GH_TOKEN) { $env:GH_TOKEN } else { $null }
    $headers = @{}
    if ($token) {
        $headers["Authorization"] = "Bearer $token"
    }

    $release = Invoke-RestMethod -Headers $headers -Uri "https://api.github.com/repos/cli/cli/releases/latest"
    $assetName = "gh_{0}_windows_{1}.zip" -f ($release.tag_name -replace '^v', ''), $arch
    $asset = $release.assets | Where-Object { $_.name -eq $assetName } | Select-Object -First 1

    if (-not $asset) {
        throw "Could not find GitHub CLI asset '$assetName' in the latest release."
    }

    $installDir = Join-Path $env:USERPROFILE ".local\gh"
    $binDir = Join-Path $env:USERPROFILE ".local\bin"
    $zipPath = Join-Path $env:TEMP "gh-$arch.zip"
    $extractDir = Join-Path $env:TEMP "gh-$arch"

    Remove-Item -Path $zipPath -Force -ErrorAction SilentlyContinue
    Remove-Item -Path $extractDir -Recurse -Force -ErrorAction SilentlyContinue

    Write-Host "   Downloading GitHub CLI for $arch..." -ForegroundColor Gray
    Invoke-WebRequest -Headers $headers -Uri $asset.browser_download_url -OutFile $zipPath
    Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force

    $ghExe = Get-ChildItem -Path $extractDir -Filter gh.exe -Recurse | Select-Object -First 1
    if (-not $ghExe) {
        throw "Could not locate gh.exe in the downloaded archive."
    }

    New-Item -ItemType Directory -Path $installDir -Force | Out-Null
    New-Item -ItemType Directory -Path $binDir -Force | Out-Null
    Copy-Item -Path $ghExe.FullName -Destination (Join-Path $installDir "gh.exe") -Force
    Copy-Item -Path (Join-Path $installDir "gh.exe") -Destination (Join-Path $binDir "gh.exe") -Force

    Ensure-UserPathEntry $binDir
    Refresh-Path
    Write-Host ""
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

    Ensure-UserPathEntry "$env:USERPROFILE\.local\bin" -Prepend
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

function Ensure-PythonCommand {
    $binDir = Join-Path $env:USERPROFILE ".local\bin"
    $pythonCommand = Join-Path $binDir "python.exe"

    if (-not (Test-Path $pythonCommand)) {
        throw "Expected uv-managed python at '$pythonCommand', but it was not found."
    }

    Ensure-UserPathEntry $binDir -Prepend
    if (-not ($env:Path -split ';' | Where-Object { $_ -eq $binDir })) {
        $env:Path = "$binDir;$env:Path"
    } elseif ((($env:Path -split ';') | Select-Object -First 1) -ne $binDir) {
        $env:Path = "$binDir;$env:Path"
    }

    $pythonSource = Get-CommandSource "python"
    if (-not $pythonSource -or $pythonSource -match 'WindowsApps') {
        Refresh-Path
        $env:Path = "$binDir;$env:Path"
        $pythonSource = Get-CommandSource "python"
    }

    if (-not $pythonSource) {
        throw "Python was installed, but the 'python' command is not available on PATH."
    }

    if ($pythonSource -match 'WindowsApps') {
        throw "Python was installed in '$binDir', but 'python' still resolves to '$pythonSource'. Windows App Execution Aliases are taking precedence."
    }

    Write-Host "   Python command source: $pythonSource" -ForegroundColor Gray
    return $pythonCommand
}

function Configure-VSCodeUserSetup {
    param(
        [string]$CodeCommand,
        [string]$GitBashPath,
        [string]$PythonCommand
    )

    Write-Host "Step 8: Configuring VS Code..." -ForegroundColor Yellow

    $settingsSource = Get-InstallerAssetPath "vscode/settings.json"
    $keybindingsSource = Get-InstallerAssetPath "vscode/keybindings.json"
    $extensionsSource = Get-InstallerAssetPath "vscode/extensions.txt"
    $userDir = Join-Path $env:APPDATA "Code\User"
    $settingsTarget = Join-Path $userDir "settings.json"
    $keybindingsTarget = Join-Path $userDir "keybindings.json"

    New-Item -ItemType Directory -Path $userDir -Force | Out-Null
    Backup-FileIfPresent $settingsTarget
    Backup-FileIfPresent $keybindingsTarget

    Copy-Item -Path $settingsSource -Destination $settingsTarget -Force
    Copy-Item -Path $keybindingsSource -Destination $keybindingsTarget -Force

    $settings = Read-JsonFile $settingsTarget
    Set-JsonProperty -Object $settings -Name "terminal.integrated.defaultProfile.windows" -Value "Git Bash"
    Set-JsonProperty -Object $settings -Name "python.defaultInterpreterPath" -Value $PythonCommand

    $windowsProfiles = Get-OrCreateJsonObjectProperty -Object $settings -Name "terminal.integrated.profiles.windows"
    $gitBashProfile = [pscustomobject]@{
        path = $GitBashPath
        args = @("--login", "-i")
        icon = "terminal-bash"
    }
    Set-JsonProperty -Object $windowsProfiles -Name "Git Bash" -Value $gitBashProfile
    Write-JsonFile -Path $settingsTarget -Object $settings

    foreach ($extension in (Get-Content $extensionsSource | Where-Object { $_ -and -not $_.StartsWith("#") })) {
        Write-Host "   Installing VS Code extension: $extension" -ForegroundColor Gray
        & $CodeCommand --install-extension $extension --force | Out-Host
    }

    Write-Host ""
}

function Configure-WindowsTerminalGitBash {
    param([string]$GitBashPath)

    $settingsPaths = @(
        "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json",
        "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json"
    )

    $configuredAny = $false
    foreach ($settingsPath in $settingsPaths) {
        if (-not (Test-Path $settingsPath)) {
            continue
        }

        Write-Host "Step 9: Configuring Windows Terminal..." -ForegroundColor Yellow
        Backup-FileIfPresent $settingsPath

        $settings = Read-JsonFile $settingsPath
        $profiles = Get-OrCreateJsonObjectProperty -Object $settings -Name "profiles"
        $profileListProperty = $profiles.PSObject.Properties["list"]
        if (-not $profileListProperty -or -not $profileListProperty.Value) {
            $profileList = @()
        } else {
            $profileList = @($profileListProperty.Value)
        }

        $gitBashGuid = "{1d5d5d38-4f2a-4b7f-9c4c-8f1b0d3b95e2}"
        $gitBashProfile = [pscustomobject]@{
            guid = $gitBashGuid
            name = "Git Bash"
            commandline = "`"$GitBashPath`" --login -i"
            startingDirectory = "%USERPROFILE%"
            hidden = $false
        }

        $filteredProfiles = @($profileList | Where-Object {
            $_.guid -ne $gitBashGuid -and $_.name -ne "Git Bash"
        })
        $filteredProfiles += $gitBashProfile
        Set-JsonProperty -Object $profiles -Name "list" -Value $filteredProfiles
        Write-JsonFile -Path $settingsPath -Object $settings
        Write-Host "   Added Git Bash profile to Windows Terminal: $settingsPath" -ForegroundColor Gray
        Write-Host ""
        $configuredAny = $true
    }

    if (-not $configuredAny) {
        Write-Host "Step 9: Configuring Windows Terminal..." -ForegroundColor Yellow
        Write-Host "   Windows Terminal settings were not found. Skipping profile setup." -ForegroundColor Gray
        Write-Host ""
    }
}

function Assert-NativeArmPython {
    param([string]$PythonCommand)

    if ((Get-WindowsArchitecture) -ne "arm64") {
        return
    }

    $pythonPlatform = (& $PythonCommand -c "import sysconfig; print(sysconfig.get_platform())" | Out-String).Trim()
    if ($pythonPlatform -notmatch "arm64") {
        throw "Expected a native ARM64 Python on Windows ARM, but uv installed '$pythonPlatform'."
    }

    Write-Host "   Verified native ARM64 Python platform: $pythonPlatform" -ForegroundColor Gray
}

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    throw "winget is required on Windows for this installer. Install Microsoft's App Installer package if winget is missing."
}

Write-Host "Step 1: Installing Git for Windows (includes Git Bash)..." -ForegroundColor Yellow
Install-OrUpgradeWingetPackage `
    -Id "Git.Git" `
    -Name "Git for Windows" `
    -OverrideArgs "/VERYSILENT /NORESTART"
$GitBashPath = Find-GitBashExecutable
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

Install-GitHubCli
Install-Uv

Write-Host "Step 6: Installing UV-managed Python $DefaultPythonVersion..." -ForegroundColor Yellow
$pythonRequest = Get-UvPythonRequest -Version $DefaultPythonVersion
Write-Host "   Requested Python target: $pythonRequest" -ForegroundColor Gray
uv python install --default $pythonRequest | Out-Host
$PythonCommand = Ensure-PythonCommand
Refresh-Path
Write-Host ""

Write-Host "Step 7: Installing Claude Code and Codex..." -ForegroundColor Yellow
Install-NpmGlobalPackage -PackageName "@anthropic-ai/claude-code" -CommandName "claude"
Install-NpmGlobalPackage -PackageName "@openai/codex" -CommandName "codex"
Write-Host ""

Configure-VSCodeUserSetup -CodeCommand $CodeCommand -GitBashPath $GitBashPath -PythonCommand $PythonCommand
Configure-WindowsTerminalGitBash -GitBashPath $GitBashPath

Write-Host "Step 10: Verifying installed tools..." -ForegroundColor Yellow
Verify-Command "git" { git --version | Out-Host }
Verify-Command "bash" { bash --version | Select-Object -First 1 | Out-Host }
Verify-Command "node" { node --version | Out-Host }
Verify-Command "npm" { npm --version | Out-Host }
Verify-Command "gh" { gh --version | Select-Object -First 1 | Out-Host }
Verify-Command "uv" { uv --version | Out-Host }
Verify-Command "python" { python --version | Out-Host }
Assert-NativeArmPython -PythonCommand $PythonCommand
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
