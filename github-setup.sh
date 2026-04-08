#!/usr/bin/env bash

set -euo pipefail

GITHUB_ACCOUNT_URL="https://github.com/"
GITHUB_SSH_URL="https://github.com/settings/ssh/new"
GITHUB_ORG_URL="https://github.com/rsm-genai-2026"

detect_platform() {
  case "$(uname -s)" in
    Darwin)
      echo "macos"
      ;;
    Linux)
      echo "linux"
      ;;
    MINGW* | MSYS* | CYGWIN*)
      echo "windows"
      ;;
    *)
      echo "unsupported"
      ;;
  esac
}

prompt_nonempty() {
  local prompt="$1"
  local value=""

  while [[ -z "$value" ]]; do
    read -r -p "$prompt" value </dev/tty
    if [[ -z "$value" ]]; then
      echo "Please enter a value."
    fi
  done

  printf '%s\n' "$value"
}

prompt_yes_no() {
  local prompt="$1"
  local reply=""

  while true; do
    read -r -p "$prompt" reply </dev/tty
    case "$reply" in
      [Yy] | [Yy][Ee][Ss])
        return 0
        ;;
      [Nn] | [Nn][Oo])
        return 1
        ;;
      *)
        echo "Please answer y or n."
        ;;
    esac
  done
}

prompt_with_default() {
  local prompt="$1"
  local default_value="$2"
  local value=""

  read -r -p "$prompt [$default_value]: " value </dev/tty
  if [[ -z "$value" ]]; then
    value="$default_value"
  fi

  printf '%s\n' "$value"
}

open_url() {
  local url="$1"
  local platform="$2"

  if [[ "$platform" == "macos" ]] && command -v open >/dev/null 2>&1; then
    open "$url" >/dev/null 2>&1 || true
    return
  fi

  if [[ "$platform" == "linux" ]] && command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$url" >/dev/null 2>&1 || true
    return
  fi

  if [[ "$platform" == "windows" ]] && command -v explorer.exe >/dev/null 2>&1; then
    explorer.exe "$url" >/dev/null 2>&1 || true
    return
  fi

  echo "Open this URL in your browser:"
  echo "  $url"
}

copy_key_to_clipboard() {
  local key_path="$1"
  local platform="$2"

  if [[ "$platform" == "macos" ]] && command -v pbcopy >/dev/null 2>&1; then
    pbcopy <"$key_path"
    echo "Your SSH public key has been copied to the clipboard."
    return
  fi

  if [[ "$platform" == "windows" ]] && command -v clip.exe >/dev/null 2>&1; then
    clip.exe <"$key_path"
    echo "Your SSH public key has been copied to the clipboard."
    return
  fi

  if [[ "$platform" == "linux" ]] && command -v wl-copy >/dev/null 2>&1; then
    wl-copy <"$key_path"
    echo "Your SSH public key has been copied to the clipboard."
    return
  fi

  if [[ "$platform" == "linux" ]] && command -v xclip >/dev/null 2>&1; then
    xclip -selection clipboard <"$key_path"
    echo "Your SSH public key has been copied to the clipboard."
    return
  fi

  echo "Could not copy the SSH public key automatically."
}

show_public_key() {
  local key_path="$1"

  echo "Paste this public key into GitHub."
  echo "Copy the single line shown below."
  cat "$key_path"
  echo
}

generate_ssh_key() {
  local private_key_path="$1"
  local key_comment="$2"

  if ssh-keygen -q -t ed25519 -f "$private_key_path" -C "$key_comment" -N ""; then
    echo "ed25519"
    return
  fi

  ssh-keygen -q -t rsa -b 4096 -f "$private_key_path" -C "$key_comment" -N ""
  echo "rsa"
}

ensure_public_key() {
  local private_key_path="$1"
  local public_key_path="$2"

  if [[ -f "$public_key_path" ]]; then
    return
  fi

  ssh-keygen -y -f "$private_key_path" >"$public_key_path"
}

platform="$(detect_platform)"

if [[ "$platform" == "unsupported" ]]; then
  echo "This GitHub setup script supports macOS, Linux, and Git Bash on Windows."
  exit 1
fi

echo "Rady School of Management @ UCSD"
echo "GitHub Setup"
echo "============"
echo
echo "Start by creating your GitHub.com account:"
echo "  $GITHUB_ACCOUNT_URL"
echo
echo "After your account exists, course staff can invite you to the organization:"
echo "  $GITHUB_ORG_URL"
echo

if ! prompt_yes_no "Have you already created your GitHub.com account? (y/n): "; then
  echo
  echo "Create your account first, then rerun this setup command."
  exit 1
fi

echo
github_username="$(prompt_nonempty "Enter your GitHub username: ")"
git_email=""

while true; do
  git_email="$(prompt_nonempty "Enter your @ucsd.edu email address for Git commits: ")"
  if [[ "$git_email" == *@ucsd.edu ]]; then
    break
  fi
  echo "Use your @ucsd.edu address."
done

git_name="$(prompt_with_default "Enter your Git commit name" "$github_username")"

echo
echo "Configuring Git..."
git config --global user.email "$git_email"
git config --global user.name "$git_name"
git config --global pull.rebase false
git config --global init.defaultBranch main

echo
echo "Git configuration set:"
echo "  GitHub username: $github_username"
echo "  Git user.name:   $(git config --global user.name)"
echo "  Git user.email:  $(git config --global user.email)"
echo "  pull.rebase:     $(git config --global pull.rebase)"
echo "  defaultBranch:   $(git config --global init.defaultBranch)"
echo

ssh_dir="$HOME/.ssh"
private_key_path="$ssh_dir/id_ed25519"
public_key_path="$private_key_path.pub"
generated_key_type=""

mkdir -p "$ssh_dir"
chmod 700 "$ssh_dir"

if [[ -f "$private_key_path" ]]; then
  echo "An SSH key already exists at $private_key_path."
  if prompt_yes_no "Reuse the existing SSH key? (y/n): "; then
    ensure_public_key "$private_key_path" "$public_key_path"
  else
    timestamp="$(date +%Y%m%d%H%M%S)"
    mv "$private_key_path" "$private_key_path.$timestamp.bak"
    if [[ -f "$public_key_path" ]]; then
      mv "$public_key_path" "$public_key_path.$timestamp.bak"
    fi
    generated_key_type="$(generate_ssh_key "$private_key_path" "$git_email")"
  fi
else
  echo "Generating a new SSH key..."
  generated_key_type="$(generate_ssh_key "$private_key_path" "$git_email")"
fi

chmod 600 "$private_key_path"
chmod 644 "$public_key_path"

echo
copy_key_to_clipboard "$public_key_path" "$platform"
echo
show_public_key "$public_key_path"

if [[ -n "$generated_key_type" ]]; then
  echo "Generated SSH key type: $generated_key_type"
  echo
fi

echo "Add this key in GitHub:"
echo "  1. Open $GITHUB_SSH_URL"
echo "  2. Give the key a recognizable title"
echo "  3. Keep 'Authentication key' selected"
echo "  4. Paste your public key and save"
echo
open_url "$GITHUB_SSH_URL" "$platform"

if ! prompt_yes_no "Have you added the SSH key in GitHub? (y/n): "; then
  echo
  echo "Add the SSH key first, then rerun this setup command."
  exit 1
fi

echo
echo "Testing SSH access to GitHub..."
ssh_output="$(ssh -T -o StrictHostKeyChecking=accept-new git@github.com 2>&1 || true)"
echo "$ssh_output"
echo

if [[ "$ssh_output" == *"successfully authenticated"* ]]; then
  echo "SSH access is working."
  echo "If you have not yet accepted your organization invite, check:"
  echo "  $GITHUB_ORG_URL"
  echo
  echo "Optional next step: run 'gh auth login' if you want GitHub CLI auth."
  exit 0
fi

echo "SSH access did not verify cleanly."
echo "Check that the SSH key was added to https://github.com/settings/keys and contact course staff if needed."
exit 1
