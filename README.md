# AI Tools Setup Guide

Use this guide to set up the tools you will need for the course.

You will install:

- Visual Studio Code
- GitHub CLI (`gh`)
- Quarto
- `uv`
- Python 3.13.12
- Claude Code
- Codex
- Git and Git Bash on Windows

## Before you start

1. Create a GitHub account at [GitHub.com](https://github.com/).
2. Your GitHub username for this course must be:
   `rsm-<first-part-of-your-ucsd-email>`
3. Example:
   If your UCSD email is `jsmith@ucsd.edu`, your GitHub username must be `rsm-jsmith`.
4. If your GitHub username is not correct yet, change it at [github.com/settings/admin](https://github.com/settings/admin). Look for "Change username" on the GitHub page and click the button to change your username
5. After your account is ready, course staff can invite you to the [rsm-genai-2026 GitHub organization](https://github.com/rsm-genai-2026).

You do not need to wait for the organization invite before installing the tools.

## Step 1: Install the tools

Choose the instructions for your computer.

### macOS

1. Open the `Terminal` app.
2. Run:

```bash
curl -sSL https://raw.githubusercontent.com/radiant-ai-hub/ai_install/main/macos-install-ai-tools.sh | bash
```

### Windows

1. Open `PowerShell` as an Admin.
2. Run:

```powershell
iwr -useb https://raw.githubusercontent.com/radiant-ai-hub/ai_install/main/windows-install-ai-tools.ps1 | iex
```

If PowerShell gives an execution policy error before the installer starts, run this instead:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "iwr -useb https://raw.githubusercontent.com/radiant-ai-hub/ai_install/main/windows-install-ai-tools.ps1 | iex"
```

## Step 2: Set up GitHub

This is a separate step. Do it after the tool installer finishes.

### macOS or Linux

Open `Terminal` and run:

```bash
curl -sSL https://raw.githubusercontent.com/radiant-ai-hub/ai_install/main/macos-setup-github.sh | bash
```

### Windows

Open `Git Bash` and run:

```bash
curl --ssl-no-revoke -sSL https://raw.githubusercontent.com/radiant-ai-hub/ai_install/main/github-setup.sh | bash
```

## What the GitHub setup does

The GitHub setup script will:

- ask you to confirm that you already created a GitHub account
- ask for your `@ucsd.edu` email address
- determine your required GitHub username for the course as `rsm-<first-part-of-your-ucsd-email>`
- check that `https://github.com/<your-course-username>` exists
- if that page returns `404`, stop fix your username at [github.com/settings/admin](https://github.com/settings/admin)
- configure Git on your computer with the correct name and email
- create or reuse an SSH key
- show you the SSH public key you need to paste into GitHub
- open the GitHub SSH key page
- test your SSH connection to GitHub

## Windows note

After the main Windows installer finishes, use `Git Bash` for the GitHub setup step. The GitHub command uses `curl --ssl-no-revoke` because Git Bash on Windows can otherwise fail when connecting to GitHub.

## If something goes wrong

- If the installer stops with a permissions error on Windows, retry with the PowerShell command that includes `-ExecutionPolicy Bypass`.
- If the GitHub setup says your required username does not exist, go to [github.com/settings/admin](https://github.com/settings/admin), use `Change username`, and then run the setup command again.
- If you are on Windows and the GitHub step does not work in PowerShell, make sure you are running it in `Git Bash`, not PowerShell.
