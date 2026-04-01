# AI Coding Tools Installer

Cross-platform install scripts for a teaching or onboarding setup centered on:

- Visual Studio Code
- GitHub CLI (`gh`)
- `uv`
- UV-managed Python
- Claude Code
- Codex
- Git for Windows / Git Bash on Windows
- Git on macOS via Xcode Command Line Tools

The layout mirrors `radiant_install`: platform-specific install scripts plus GitHub Actions checks.

## Quick start

macOS:

```bash
curl -sSL https://raw.githubusercontent.com/radiant-ai-hub/ai_install/main/macos-install-ai-tools.sh | bash
```

Windows PowerShell:

```powershell
iwr -useb https://raw.githubusercontent.com/radiant-ai-hub/ai_install/main/windows-install-ai-tools.ps1 | iex
```

## Windows requirements

- `winget` is required because Git, VS Code, and Node.js LTS are currently installed with `winget`.
- The installer checks for `winget` at startup and stops with instructions if it is missing.
- If `winget` is not available, install Microsoft's App Installer package first.

## Notes

- The Windows installer uses `winget` for Git, VS Code, and Node.js LTS.
- The Windows installer downloads GitHub CLI directly from the official `cli/cli` release assets, including the ARM64 build on Windows ARM devices.
- On Windows ARM, the installer now asks `uv` for the native ARM64 Python `3.13.12` build explicitly instead of relying on the default platform selection.
- After Python install, the Windows script makes sure `python` resolves to the uv-managed executable instead of the Windows Store alias in `WindowsApps`.
- The Windows installer still requires `winget` overall because Git, VS Code, and Node.js are currently installed that way.
- The macOS installer avoids Homebrew and downloads tools directly from official vendor sources, similar to `radiant_install`.
- On macOS, Git comes from Xcode Command Line Tools.
- On Apple Silicon Macs, the installer uses the VS Code ARM DMG, not the universal build.
- `uv` is installed from Astral's official standalone installer, then used to install a managed Python.
- The default managed Python version is pinned to `3.13.12` to match the server.
- Claude Code and Codex are installed with `npm`.
- Anthropic's current Claude Code docs list Windows support via WSL. This repo still installs the CLI on Windows, but the supported Windows workflow should be considered WSL-first.
- The Windows installer explicitly locates the VS Code CLI after install because `code` is not reliably added to `PATH` in GitHub Actions runners.

## Scripts

- `macos-install-ai-tools.sh`
- `macos-uninstall-ai-tools.sh`
- `windows-install-ai-tools.ps1`
- `windows-uninstall-ai-tools.ps1`
