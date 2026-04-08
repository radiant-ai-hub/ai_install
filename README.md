# AI Coding Tools Installer

Cross-platform install scripts for a teaching or onboarding setup centered on:

- Visual Studio Code
- GitHub CLI (`gh`)
- `uv`
- Python 3.13.12
- Claude Code
- Codex
- Git for Windows / Git Bash on Windows
- Git on macOS via Xcode Command Line Tools

The layout mirrors `radiant_install`: platform-specific install scripts plus GitHub Actions checks.

## Student flow

1. Create your account at [GitHub.com](https://github.com/).
2. Share or confirm your GitHub username with course staff.
3. After your account exists, course staff can invite you to the [rsm-genai-2026 GitHub organization](https://github.com/rsm-genai-2026).
4. Run the tools installer for your platform.
5. Run the separate GitHub setup command for your platform to configure Git and SSH access.

You do not need to wait for the organization invite to install the tools. The GitHub setup step configures your machine so you are ready once the invite is accepted.

## Tool install

macOS:

```bash
curl -sSL https://raw.githubusercontent.com/radiant-ai-hub/ai_install/main/macos-install-ai-tools.sh | bash
```

Windows PowerShell:

```powershell
iwr -useb https://raw.githubusercontent.com/radiant-ai-hub/ai_install/main/windows-install-ai-tools.ps1 | iex
```

## GitHub setup

Run this after the tools installer finishes. This is a separate step from the main tool install.

Separate command:

macOS or Linux:

```bash
curl -sSL https://raw.githubusercontent.com/radiant-ai-hub/ai_install/main/macos-setup-github.sh | bash
```

Windows Git Bash:

```bash
curl --ssl-no-revoke -sSL https://raw.githubusercontent.com/radiant-ai-hub/ai_install/main/github-setup.sh | bash
```

The GitHub setup step:

- asks the student to create a GitHub.com account first
- records the student's GitHub username
- configures global Git name and `@ucsd.edu` email
- creates or reuses an SSH key, preferring `ed25519`
- always prints the public key so the student can paste it into GitHub, even when reusing an existing key
- opens `https://github.com/settings/ssh/new` and prompts the student to add the key
- tests `ssh -T git@github.com`

On Windows, run the GitHub setup command from Git Bash after the main Windows installer has installed Git for Windows. The command uses `curl --ssl-no-revoke` because Git Bash on Windows can otherwise fail TLS revocation checks against GitHub.

## Windows requirements

- `winget` is required because Git, VS Code, and Node.js LTS are currently installed with `winget`.
- `winget` is also required for the Python `Python.Python.3.13` install on Windows.
- The installer checks for `winget` at startup and stops with instructions if it is missing.
- If `winget` is not available, install Microsoft's App Installer package first.

## Notes

- For day-to-day Windows work with `uv` and Python, this repo treats Git Bash as the preferred interactive shell. The installer itself still runs from PowerShell.
- The Windows installer uses `winget` for Git, VS Code, Node.js LTS, and Python.
- The Windows installer downloads GitHub CLI directly from the official `cli/cli` release assets, including the ARM64 build on Windows ARM devices.
- The Windows installer uses the official `winget` package `Python.Python.3.13` pinned to version `3.13.12`, with architecture selection set to `arm64` on Windows ARM and `x64` on Intel/AMD Windows.
- On Windows, the installer verifies that `python` resolves to the actual installed Python executable and not the Windows Store alias in `WindowsApps`.
- On Windows, the installer copies the repo's `vscode/settings.json` and `vscode/keybindings.json` into the VS Code user profile, then installs the extensions listed in `vscode/extensions.txt`.
- On Windows, VS Code is configured to use Git Bash as the default integrated terminal.
- On Windows, the installer also adds a Git Bash profile to Windows Terminal when a Windows Terminal settings file is present.
- On Windows, the uninstaller returns control to the current PowerShell session instead of terminating the host shell, and it explicitly removes the npm shims for `claude` and `codex` if they were installed.
- On current VS Code builds, Copilot-related functionality may show up as built-in AI features plus `github.copilot-chat`, even when `github.copilot` is requested from the extensions list.
- The Windows installer still requires `winget` overall because Git, VS Code, and Node.js are currently installed that way.
- The macOS installer avoids Homebrew and downloads tools directly from official vendor sources, similar to `radiant_install`.
- On macOS, Git comes from Xcode Command Line Tools.
- On Apple Silicon Macs, the installer uses the VS Code ARM DMG, not the universal build.
- `uv` is installed from Astral's official standalone installer and can use the installed system Python on Windows.
- The default Python version target is pinned to `3.13.12` to match the server.
- Claude Code and Codex are installed with `npm`.
- Anthropic's current Claude Code docs list Windows support via WSL. This repo still installs the CLI on Windows, but the supported Windows workflow should be considered WSL-first.
- The Windows installer explicitly locates the VS Code CLI after install because `code` is not reliably added to `PATH` in GitHub Actions runners.

## Scripts

- `macos-install-ai-tools.sh`
- `macos-setup-github.sh`
- `macos-uninstall-ai-tools.sh`
- `github-setup.sh`
- `windows-install-ai-tools.ps1`
- `windows-uninstall-ai-tools.ps1`
- `vscode/settings.json`
- `vscode/keybindings.json`
- `vscode/extensions.txt`

GitHub Actions runs both install and uninstall coverage on Windows full-install jobs, with cleanup checks for the user-scope files and PATH entries managed by these scripts.
