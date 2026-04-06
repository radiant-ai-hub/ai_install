#!/usr/bin/env bash

set -euo pipefail

DEFAULT_PYTHON_VERSION="${DEFAULT_PYTHON_VERSION:-3.13.12}"

echo "Rady School of Management @ UCSD"
echo "AI Coding Tools Installer for macOS"
echo "=================================="
echo

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This installer is intended for macOS."
  exit 1
fi

macos_version="$(sw_vers -productVersion)"
echo "Checking system compatibility..."
echo "macOS version: $macos_version"
echo

TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT
cd "$TEMP_DIR"

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

check_success() {
  if [[ $? -eq 0 ]]; then
    echo "   OK: $1"
  else
    echo "   ERROR: $1 failed"
    exit 1
  fi
}

ensure_path_entry() {
  local entry="$1"
  local shell_file

  if [[ ":$PATH:" != *":$entry:"* ]]; then
    export PATH="$entry:$PATH"
  fi

  for shell_file in "$HOME/.zprofile" "$HOME/.zshrc" "$HOME/.bash_profile"; do
    if [[ ! -f "$shell_file" ]]; then
      touch "$shell_file"
    fi
    if ! grep -Fqs "$entry" "$shell_file"; then
      printf '\nexport PATH="%s:$PATH"\n' "$entry" >>"$shell_file"
      break
    fi
  done
}

copy_app_to_applications() {
  local app_path="$1"

  if cp -R "$app_path" /Applications/ 2>/dev/null; then
    return
  fi

  echo "   Copying to /Applications requires admin privileges..."
  sudo cp -R "$app_path" /Applications/
}

remove_target() {
  local path="$1"

  if [[ -e "$path" || -L "$path" ]]; then
    rm -rf "$path" 2>/dev/null || sudo rm -rf "$path"
  fi
}

install_symlink() {
  local source_path="$1"
  local target_path="$2"
  local target_dir

  target_dir="$(dirname "$target_path")"
  if [[ ! -d "$target_dir" ]]; then
    mkdir -p "$target_dir" 2>/dev/null || sudo mkdir -p "$target_dir"
  fi

  if ln -sf "$source_path" "$target_path" 2>/dev/null; then
    return
  fi

  sudo ln -sf "$source_path" "$target_path"
}

install_xcode_command_line_tools() {
  echo "Step 1: Checking Xcode Command Line Tools..."

  if xcode-select -p >/dev/null 2>&1; then
    echo "   Xcode Command Line Tools already installed"
    echo
    return
  fi

  if [[ "${CI:-false}" == "true" ]]; then
    echo "   CI mode expected Xcode Command Line Tools to already exist."
    echo "   They are missing, so installation cannot continue."
    exit 1
  fi

  echo "   Installing Xcode Command Line Tools..."
  touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
  clt_label="$(softwareupdate -l 2>/dev/null | sed -n 's/^ *\* Label: //p' | grep 'Command Line Tools' | tail -n1)"

  if [[ -z "$clt_label" ]]; then
    rm -f /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
    echo "   Could not determine the Command Line Tools package label."
    echo "   Run 'xcode-select --install' manually and then rerun this script."
    exit 1
  fi

  sudo softwareupdate -i "$clt_label" --verbose
  sudo xcode-select --switch /Library/Developer/CommandLineTools
  rm -f /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
  check_success "Xcode Command Line Tools installation"
  echo
}

install_vscode() {
  echo "Step 2: Installing Visual Studio Code..."

  local arch vscode_url dmg_path mount_output volume_path app_path
  arch="$(uname -m)"

  if [[ "$arch" == "arm64" ]]; then
    vscode_url='https://code.visualstudio.com/sha/download?build=stable&os=darwin-arm64-dmg'
  else
    vscode_url='https://code.visualstudio.com/sha/download?build=stable&os=darwin-x64-dmg'
  fi

  echo "   Downloading Visual Studio Code for $arch..."
  dmg_path="$TEMP_DIR/VSCode.dmg"
  curl -L -o "$dmg_path" "$vscode_url"
  check_success "VS Code download"

  mount_output="$(hdiutil attach "$dmg_path" -nobrowse)"
  volume_path="$(echo "$mount_output" | awk -F'\t' '/\/Volumes\// {print $3; exit}')"
  app_path="$volume_path/Visual Studio Code.app"

  if [[ ! -d "$app_path" ]]; then
    echo "   Could not find Visual Studio Code.app in mounted image."
    exit 1
  fi

  remove_target "/Applications/Visual Studio Code.app"
  copy_app_to_applications "$app_path"
  hdiutil detach "$volume_path" -quiet

  install_symlink "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code" "/usr/local/bin/code"
  check_success "VS Code installation"
  echo
}

install_node() {
  echo "Step 3: Installing Node.js LTS..."

  local node_version node_pkg_url node_pkg_path
  node_version="$(
    curl -s https://nodejs.org/dist/index.json \
      | tr '{' '\n' \
      | grep '"version"' \
      | grep -Ev '"lts":[[:space:]]*false' \
      | sed -E 's/.*"version":[[:space:]]*"([^"]+)".*/\1/' \
      | head -n1
  )"

  if [[ -z "$node_version" ]]; then
    echo "   Could not determine latest Node.js LTS version."
    exit 1
  fi

  echo "   Latest Node.js LTS: ${node_version#v}"
  node_pkg_url="https://nodejs.org/dist/$node_version/node-$node_version.pkg"
  node_pkg_path="$TEMP_DIR/node.pkg"
  curl -L -o "$node_pkg_path" "$node_pkg_url"
  check_success "Node.js download"

  sudo installer -pkg "$node_pkg_path" -target /
  check_success "Node.js installation"
  echo
}

install_github_cli() {
  echo "Step 4: Installing GitHub CLI..."

  local arch asset_suffix release_json gh_url gh_zip extracted_dir
  arch="$(uname -m)"
  if [[ "$arch" == "arm64" ]]; then
    asset_suffix="macOS_arm64.zip"
  else
    asset_suffix="macOS_amd64.zip"
  fi

  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    release_json="$(curl -s -H "Authorization: Bearer $GITHUB_TOKEN" https://api.github.com/repos/cli/cli/releases/latest)"
  elif [[ -n "${GH_TOKEN:-}" ]]; then
    release_json="$(curl -s -H "Authorization: Bearer $GH_TOKEN" https://api.github.com/repos/cli/cli/releases/latest)"
  else
    release_json="$(curl -s https://api.github.com/repos/cli/cli/releases/latest)"
  fi
  gh_url="$(printf '%s' "$release_json" | grep -o 'https://[^"]*'"$asset_suffix" | head -n1)"

  if [[ -z "$gh_url" ]]; then
    echo "   Could not determine GitHub CLI download URL."
    exit 1
  fi

  gh_zip="$TEMP_DIR/gh.zip"
  curl -L -o "$gh_zip" "$gh_url"
  check_success "GitHub CLI download"

  unzip -q "$gh_zip" -d "$TEMP_DIR/gh"
  extracted_dir="$(find "$TEMP_DIR/gh" -maxdepth 1 -type d -name 'gh_*' | head -n1)"

  if [[ -z "$extracted_dir" || ! -x "$extracted_dir/bin/gh" ]]; then
    echo "   Could not locate extracted GitHub CLI binary."
    exit 1
  fi

  install_symlink "$extracted_dir/bin/gh" "/usr/local/bin/gh"
  check_success "GitHub CLI installation"
  echo
}

install_uv() {
  echo "Step 5: Installing uv..."
  if command_exists uv; then
    echo "   uv already installed. Updating if possible..."
    uv self update || true
  else
    curl -LsSf https://astral.sh/uv/install.sh -o "$TEMP_DIR/uv-install.sh"
    sh "$TEMP_DIR/uv-install.sh"
  fi

  ensure_path_entry "$HOME/.local/bin"
  check_success "uv installation"
  echo
}

install_npm_package() {
  local package_name="$1"
  local command_name="$2"

  echo "   Installing $package_name..."
  npm install -g "$package_name"

  if ! command_exists "$command_name"; then
    echo "   Expected command '$command_name' is not available after npm install."
    exit 1
  fi
}

verify_command() {
  local name="$1"
  local command_text="$2"
  echo "   Verifying $name..."
  eval "$command_text"
}

install_xcode_command_line_tools

echo "   Verifying git from Xcode Command Line Tools..."
git --version
echo

install_vscode
install_node
install_github_cli
install_uv

echo "Step 6: Installing UV-managed Python $DEFAULT_PYTHON_VERSION..."
uv python install --default "$DEFAULT_PYTHON_VERSION"
check_success "Python installation"
echo

echo "Step 7: Installing Claude Code and Codex..."
install_npm_package "@anthropic-ai/claude-code" "claude"
install_npm_package "@openai/codex" "codex"
echo

echo "Step 8: Verifying installed tools..."
verify_command "git" "git --version"
verify_command "node" "node --version"
verify_command "npm" "npm --version"
verify_command "gh" "gh --version | head -n1"
verify_command "uv" "uv --version"
verify_command "python" "python3 --version || python --version"
verify_command "code" "code --version | head -n1"
verify_command "claude" "claude --version"
verify_command "codex" "codex --version"
echo

echo "Installation complete."
echo
echo "Next steps:"
echo "  1. Create your GitHub.com account if you do not already have one."
echo "  2. Run the separate GitHub setup command from README.md to configure Git and SSH."
echo "  3. Launch Visual Studio Code from Applications."
echo "  4. Run 'gh auth login' if you want GitHub CLI auth."
echo "  5. Run 'claude' to authenticate Claude Code."
echo "  6. Run 'codex login' to authenticate Codex."
echo
echo "GitHub setup command:"
echo "  curl -sSL https://raw.githubusercontent.com/radiant-ai-hub/ai_install/main/macos-setup-github.sh | bash"
