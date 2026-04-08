# AI Coding Tools Installation Script for Windows
# Run the latest version with:
# iwr -useb https://raw.githubusercontent.com/radiant-ai-hub/ai_install/main/windows-install-ai-tools.ps1 | iex
# If PowerShell reports an execution policy problem, run:
# powershell -NoProfile -ExecutionPolicy Bypass -Command "iwr -useb https://raw.githubusercontent.com/radiant-ai-hub/ai_install/main/windows-install-ai-tools.ps1 | iex"

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$DefaultPythonVersion = if ($env:DEFAULT_PYTHON_VERSION) { $env:DEFAULT_PYTHON_VERSION } else { "3.13.12" }
$PythonWingetId = "Python.Python.3.13"
$QuartoReleasesApi = "https://api.github.com/repos/quarto-dev/quarto-cli/releases/latest"
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

function Ensure-ProcessPathEntryFirst {
    param([string]$Entry)

    $parts = @()
    if ($env:Path) {
        $parts = $env:Path -split ';' | Where-Object { $_ }
    }

    $filteredParts = $parts | Where-Object { $_ -ne $Entry }
    $env:Path = (@($Entry) + $filteredParts) -join ';'
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

function Get-WingetArchitecture {
    switch (Get-WindowsArchitecture) {
        "arm64" { return "arm64" }
        "amd64" { return "x64" }
        "386" { return "x86" }
        default { throw "Unsupported winget architecture." }
    }
}

function Get-CommandSource {
    param([string]$Name)

    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    return $null
}

function Get-GitHubApiHeaders {
    $headers = @{
        "Accept" = "application/vnd.github+json"
    }

    $token = if ($env:GITHUB_TOKEN) { $env:GITHUB_TOKEN } elseif ($env:GH_TOKEN) { $env:GH_TOKEN } else { $null }
    if ($token) {
        $headers["Authorization"] = "Bearer $token"
    }

    return $headers
}

function Find-QuartoCommand {
    $existing = Get-Command quarto -ErrorAction SilentlyContinue
    $candidates = @()
    if ($existing) {
        $candidates += $existing.Source
    }

    $candidates += @(
        "$env:USERPROFILE\.local\quarto\bin\quarto.cmd",
        "$env:USERPROFILE\.local\quarto\bin\quarto.exe",
        "$env:ProgramFiles\Quarto\bin\quarto.cmd",
        "$env:ProgramFiles\Quarto\bin\quarto.exe",
        "${env:ProgramFiles(x86)}\Quarto\bin\quarto.cmd",
        "${env:ProgramFiles(x86)}\Quarto\bin\quarto.exe"
    )

    foreach ($candidate in ($candidates | Where-Object { $_ } | Select-Object -Unique)) {
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    return $null
}

function Ensure-QuartoPath {
    $quartoCommand = Find-QuartoCommand
    if (-not $quartoCommand) {
        throw "Quarto installed, but the CLI could not be found in expected locations."
    }

    Ensure-UserPathEntry (Split-Path -Parent $quartoCommand)
    Refresh-Path
    return $quartoCommand
}

function Find-InstalledPythonExecutable {
    $roots = @(
        (Join-Path $env:LOCALAPPDATA "Programs\Python"),
        (Join-Path $env:USERPROFILE "AppData\Local\Programs\Python"),
        "C:\hostedtoolcache\windows\Python"
    ) | Where-Object { $_ -and (Test-Path $_) }

    $candidates = @()
    foreach ($root in ($roots | Select-Object -Unique)) {
        $candidates += Get-ChildItem -Path $root -Filter python.exe -Recurse -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName
    }

    $pythonMatches = @()
    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        try {
            $version = (& $candidate --version 2>$null | Out-String).Trim()
            if ($version -ne "Python $DefaultPythonVersion") {
                continue
            }

            $platform = (& $candidate -c "import sysconfig; print(sysconfig.get_platform())" 2>$null | Out-String).Trim()
            if ((Get-WindowsArchitecture) -eq "arm64" -and $platform -notmatch "arm64") {
                continue
            }

            $pythonMatches += [pscustomobject]@{
                Path = $candidate
                Platform = $platform
                Prefer = if ($candidate -match 'hostedtoolcache') { 1 } else { 0 }
            }
        } catch {
        }
    }

    return $pythonMatches | Sort-Object Prefer, Path | Select-Object -ExpandProperty Path -First 1
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
        "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe",
        "$env:LOCALAPPDATA\Programs\Git\git-bash.exe",
        "$env:ProgramFiles\Git\bin\bash.exe",
        "$env:ProgramFiles\Git\git-bash.exe",
        "${env:ProgramFiles(x86)}\Git\bin\bash.exe",
        "${env:ProgramFiles(x86)}\Git\git-bash.exe"
    )

    $gitCommand = Get-Command git.exe -ErrorAction SilentlyContinue
    if ($gitCommand) {
        $gitCmdDir = Split-Path -Parent $gitCommand.Source
        $gitRoot = Split-Path -Parent $gitCmdDir
        $candidates += @(
            (Join-Path $gitRoot "bin\bash.exe"),
            (Join-Path $gitRoot "git-bash.exe")
        )
    }

    foreach ($candidate in ($candidates | Where-Object { $_ } | Select-Object -Unique)) {
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    $gitSearchRoots = @(
        (Join-Path $env:LOCALAPPDATA "Programs"),
        $env:ProgramFiles,
        ${env:ProgramFiles(x86)}
    ) | Where-Object { $_ -and (Test-Path $_) }

    foreach ($root in ($gitSearchRoots | Select-Object -Unique)) {
        $match = Get-ChildItem -Path $root -Filter bash.exe -Recurse -ErrorAction SilentlyContinue |
            Where-Object {
                $_.FullName -match '\\Git\\bin\\bash\.exe$' -or
                $_.FullName -match '\\Git\\usr\\bin\\bash\.exe$'
            } |
            Sort-Object FullName |
            Select-Object -ExpandProperty FullName -First 1
        if ($match) {
            return $match
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

function Install-Python {
    Write-Host "Step 7: Installing Python $DefaultPythonVersion..." -ForegroundColor Yellow

    $arch = Get-WingetArchitecture
    $existingPython = Find-InstalledPythonExecutable

    if ($existingPython) {
        Write-Host "   Python $DefaultPythonVersion already available. Skipping install." -ForegroundColor Gray
        Write-Host ""
        return
    }

    Write-Host "   Installing Python $DefaultPythonVersion for $arch via winget..." -ForegroundColor Gray
    & winget install `
        --exact `
        --id $PythonWingetId `
        --source winget `
        --version $DefaultPythonVersion `
        --architecture $arch `
        --scope user `
        --accept-package-agreements `
        --accept-source-agreements `
        --silent `
        --disable-interactivity

    Refresh-Path
    Write-Host ""
}

function Install-GitHubCli {
    Write-Host "Step 4: Installing GitHub CLI..." -ForegroundColor Yellow

    $arch = Get-WindowsArchitecture
    $headers = Get-GitHubApiHeaders

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
    Write-Host "Step 6: Installing uv..." -ForegroundColor Yellow
    if (Get-Command uv -ErrorAction SilentlyContinue) {
        Write-Host "   uv already installed. Updating if possible..." -ForegroundColor Gray
        uv self update | Out-Host
    } else {
        $uvInstallerContent = Invoke-RestMethod https://astral.sh/uv/install.ps1
        if (-not $uvInstallerContent) {
            throw "Could not download the uv installer script."
        }

        Invoke-Expression $uvInstallerContent
    }

    Ensure-UserPathEntry "$env:USERPROFILE\.local\bin" -Prepend
    Refresh-Path
    Write-Host ""
}

function Find-ReleaseAsset {
    param(
        [object]$Release,
        [string[]]$CandidateNames
    )

    foreach ($candidateName in $CandidateNames) {
        $asset = $Release.assets | Where-Object { $_.name -eq $candidateName } | Select-Object -First 1
        if ($asset) {
            return $asset
        }
    }

    return $null
}

function Install-Quarto {
    Write-Host "Step 5: Installing Quarto..." -ForegroundColor Yellow

    $arch = Get-WindowsArchitecture
    $headers = Get-GitHubApiHeaders
    $release = Invoke-RestMethod -Headers $headers -Uri $QuartoReleasesApi
    $version = $release.tag_name -replace '^v', ''
    if (-not $version) {
        throw "Could not determine latest Quarto version."
    }

    $candidateNames = switch ($arch) {
        "arm64" { @("quarto-$version-win-arm64.zip", "quarto-$version-windows-arm64.zip", "quarto-$version-win.zip") }
        "amd64" { @("quarto-$version-win-x64.zip", "quarto-$version-win-amd64.zip", "quarto-$version-win.zip") }
        "386" { @("quarto-$version-win-x86.zip", "quarto-$version-win-386.zip", "quarto-$version-win.zip") }
        default { throw "Unsupported Windows architecture for Quarto: $arch" }
    }

    $installerAsset = Find-ReleaseAsset -Release $release -CandidateNames $candidateNames
    if (-not $installerAsset) {
        throw "Could not determine the correct Quarto installer for Windows $arch."
    }

    $checksumsAsset = Find-ReleaseAsset -Release $release -CandidateNames @("quarto-$version-checksums.txt")
    if (-not $checksumsAsset) {
        throw "Could not determine the Quarto checksum file."
    }

    Write-Host "   Detected Windows architecture: $arch" -ForegroundColor Gray
    Write-Host "   Latest Quarto release: $version" -ForegroundColor Gray
    Write-Host "   Using Quarto installer asset: $($installerAsset.name)" -ForegroundColor Gray

    $zipPath = Join-Path $env:TEMP "quarto-$arch.zip"
    $checksumsPath = Join-Path $env:TEMP "quarto-checksums.txt"
    $installRoot = Join-Path $env:USERPROFILE ".local\quarto"
    Remove-Item -Path $zipPath -Force -ErrorAction SilentlyContinue
    Remove-Item -Path $checksumsPath -Force -ErrorAction SilentlyContinue
    Remove-Item -Path $installRoot -Recurse -Force -ErrorAction SilentlyContinue

    Invoke-WebRequest -Uri $installerAsset.browser_download_url -OutFile $zipPath
    Invoke-WebRequest -Uri $checksumsAsset.browser_download_url -OutFile $checksumsPath

    $expectedHash = $null
    foreach ($line in (Get-Content $checksumsPath)) {
        if ($line -match "^(?<sha>[0-9a-fA-F]{64})\s+(?<name>\S+)$" -and $Matches["name"] -eq $installerAsset.name) {
            $expectedHash = $Matches["sha"].ToLowerInvariant()
            break
        }
    }

    if (-not $expectedHash) {
        throw "Could not find a checksum for $($installerAsset.name)."
    }

    $actualHash = (Get-FileHash -Path $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualHash -ne $expectedHash) {
        throw "Quarto checksum verification failed. Expected $expectedHash but found $actualHash."
    }

    New-Item -ItemType Directory -Path $installRoot -Force | Out-Null
    Expand-Archive -Path $zipPath -DestinationPath $installRoot -Force

    $script:QuartoCommand = Ensure-QuartoPath
    if (-not $script:QuartoCommand) {
        throw "Quarto installed, but the CLI could not be found in expected locations."
    }

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
    $pythonExecutable = $null

    for ($attempt = 1; $attempt -le 15; $attempt++) {
        Refresh-Path
        $pythonExecutable = Find-InstalledPythonExecutable
        if ($pythonExecutable) {
            break
        }
        Start-Sleep -Seconds 2
    }

    if (-not $pythonExecutable) {
        throw "Could not determine the installed Python $DefaultPythonVersion executable path."
    }

    $pythonDir = Split-Path -Parent $pythonExecutable
    Ensure-UserPathEntry $pythonDir -Prepend
    Ensure-ProcessPathEntryFirst $pythonDir
    if ($env:GITHUB_PATH) {
        Add-Content -Path $env:GITHUB_PATH -Value $pythonDir
    }
    $pythonSource = $null

    for ($attempt = 1; $attempt -le 10; $attempt++) {
        Ensure-ProcessPathEntryFirst $pythonDir
        $pythonSource = Get-CommandSource "python"
        if ($pythonSource -and $pythonSource -eq $pythonExecutable) {
            break
        }
        Start-Sleep -Seconds 1
    }

    if (-not $pythonSource) {
        throw "Python $DefaultPythonVersion was installed, but the 'python' command is not available on PATH."
    }

    if ($pythonSource -ne $pythonExecutable) {
        throw "Expected 'python' to resolve to '$pythonExecutable', but found '$pythonSource'."
    }

    $pythonVersion = (& $pythonExecutable --version | Out-String).Trim()
    if ($pythonVersion -ne "Python $DefaultPythonVersion") {
        throw "Expected Python $DefaultPythonVersion, but found '$pythonVersion'."
    }

    Write-Host "   Python command source: $pythonSource" -ForegroundColor Gray
    Write-Host "   Python executable: $pythonExecutable" -ForegroundColor Gray
    return $pythonExecutable
}

function Configure-VSCodeUserSetup {
    param(
        [string]$CodeCommand,
        [string]$GitBashPath,
        [string]$PythonCommand
    )

    Write-Host "Step 9: Configuring VS Code..." -ForegroundColor Yellow

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

        Write-Host "Step 10: Configuring Windows Terminal..." -ForegroundColor Yellow
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
        Write-Host "Step 10: Configuring Windows Terminal..." -ForegroundColor Yellow
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
        throw "Expected a native ARM64 Python on Windows ARM, but found '$pythonPlatform'."
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
Refresh-Path
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
Install-Quarto
Install-Uv
$PythonCommand = $null
Install-Python
$PythonCommand = Ensure-PythonCommand
Refresh-Path
Write-Host ""

$QuartoCommand = Ensure-QuartoPath

Write-Host "Step 8: Installing Claude Code and Codex..." -ForegroundColor Yellow
Install-NpmGlobalPackage -PackageName "@anthropic-ai/claude-code" -CommandName "claude"
Install-NpmGlobalPackage -PackageName "@openai/codex" -CommandName "codex"
Write-Host ""

Configure-VSCodeUserSetup -CodeCommand $CodeCommand -GitBashPath $GitBashPath -PythonCommand $PythonCommand
Configure-WindowsTerminalGitBash -GitBashPath $GitBashPath

Write-Host "Step 11: Verifying installed tools..." -ForegroundColor Yellow
Verify-Command "git" { git --version | Out-Host }
Verify-Command "bash" { & $GitBashPath --version | Select-Object -First 1 | Out-Host }
Verify-Command "node" { node --version | Out-Host }
Verify-Command "npm" { npm --version | Out-Host }
Verify-Command "gh" { gh --version | Select-Object -First 1 | Out-Host }
Verify-Command "quarto" { & $QuartoCommand --version | Select-Object -First 1 | Out-Host }
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
Write-Host "  1. Create your GitHub.com account if you do not already have one."
Write-Host "  2. Run the separate GitHub setup command from README.md to configure Git and SSH."
Write-Host "  3. Launch VS Code."
Write-Host "  4. Run 'gh auth login' if you want GitHub CLI auth."
Write-Host "  5. Run 'claude' to authenticate Claude Code."
Write-Host "  6. Run 'codex login' to authenticate Codex."
Write-Host ""
Write-Host "GitHub setup command:" -ForegroundColor Cyan
Write-Host "  Open Git Bash and run:"
Write-Host "  curl --ssl-no-revoke -sSL https://raw.githubusercontent.com/radiant-ai-hub/ai_install/main/github-setup.sh | bash"
