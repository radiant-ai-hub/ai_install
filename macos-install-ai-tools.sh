#!/usr/bin/env bash

set -euo pipefail

DEFAULT_PYTHON_VERSION="${DEFAULT_PYTHON_VERSION:-3.13.12}"
QUARTO_RELEASES_API="https://api.github.com/repos/quarto-dev/quarto-cli/releases/latest"

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

json_release_tag_name() {
  local release_json="$1"

  printf '%s' "$release_json" | node -e '
    const fs = require("fs");
    const release = JSON.parse(fs.readFileSync(0, "utf8"));
    process.stdout.write(String(release.tag_name || "").replace(/^v/, ""));
  '
}

json_find_asset_url() {
  local release_json="$1"
  shift

  printf '%s' "$release_json" | node -e '
    const fs = require("fs");
    const release = JSON.parse(fs.readFileSync(0, "utf8"));
    const candidates = process.argv.slice(1);
    for (const candidate of candidates) {
      const asset = release.assets.find((entry) => entry.name === candidate);
      if (asset) {
        process.stdout.write(asset.browser_download_url);
        process.exit(0);
      }
    }
    process.exit(1);
  ' "$@"
}

find_quarto_command() {
  local candidates=(
    "$(command -v quarto 2>/dev/null || true)"
    "/usr/local/bin/quarto"
    "/opt/quarto/bin/quarto"
    "/Applications/quarto/bin/quarto"
    "$HOME/Applications/quarto/bin/quarto"
  )
  local candidate

  for candidate in "${candidates[@]}"; do
    if [[ -n "$candidate" && -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

ensure_quarto_command() {
  local quarto_command=""
  quarto_command="$(find_quarto_command || true)"

  if [[ -z "$quarto_command" ]]; then
    echo "   Quarto was installed, but the command could not be found in expected locations."
    exit 1
  fi

  export PATH="$(dirname "$quarto_command"):$PATH"
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

ensure_directory_owner() {
  local path="$1"
  local owner

  if [[ ! -d "$path" ]]; then
    mkdir -p "$path" 2>/dev/null || sudo mkdir -p "$path"
  fi

  owner="$(stat -f '%Su' "$path" 2>/dev/null || true)"
  if [[ "$owner" == "$(whoami)" ]]; then
    echo "   $path is already owned by $(whoami)"
    return
  fi

  echo "   Updating ownership for $path to $(whoami)..."
  sudo chown -R "$(whoami)" "$path"
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

install_binary() {
  local source_path="$1"
  local target_path="$2"
  local target_dir

  target_dir="$(dirname "$target_path")"
  if [[ ! -d "$target_dir" ]]; then
    mkdir -p "$target_dir" 2>/dev/null || sudo mkdir -p "$target_dir"
  fi

  if cp "$source_path" "$target_path" 2>/dev/null; then
    chmod +x "$target_path"
    return
  fi

  sudo cp "$source_path" "$target_path"
  sudo chmod +x "$target_path"
}

ensure_usr_local_permissions() {
  echo "Step 1: Checking /usr/local permissions..."
  ensure_directory_owner "/usr/local/bin"
  ensure_directory_owner "/usr/local/lib"
  echo
}

ensure_npm_global_permissions() {
  local npm_prefix npm_root npm_bin_dir

  if ! command_exists npm; then
    return
  fi

  npm_prefix="$(npm prefix -g 2>/dev/null || true)"
  npm_root="$(npm root -g 2>/dev/null || true)"
  npm_bin_dir=""

  if [[ -n "$npm_prefix" ]]; then
    npm_bin_dir="$npm_prefix/bin"
  fi

  echo "   Checking npm global install permissions..."
  if [[ -n "$npm_root" ]]; then
    ensure_directory_owner "$npm_root"
  fi
  if [[ -n "$npm_bin_dir" ]]; then
    ensure_directory_owner "$npm_bin_dir"
  fi
  echo
}

install_xcode_command_line_tools() {
  echo "Step 2: Checking Xcode Command Line Tools..."

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
  echo "Step 3: Installing Visual Studio Code..."

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
  echo "Step 4: Installing Node.js LTS..."

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
  ensure_npm_global_permissions
  echo
}

install_github_cli() {
  echo "Step 5: Installing GitHub CLI..."

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

  install_binary "$extracted_dir/bin/gh" "/usr/local/bin/gh"
  check_success "GitHub CLI installation"
  echo
}

install_uv() {
  echo "Step 7: Installing uv..."
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

install_quarto() {
  echo "Step 6: Installing Quarto..."

  local arch release_json quarto_version checksums_asset_name checksums_url checksums_path
  local asset_name_candidates quarto_url quarto_asset_name pkg_path expected_sha actual_sha
  local -a api_curl_args
  arch="$(uname -m)"

  api_curl_args=(-H "Accept: application/vnd.github+json")
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    api_curl_args=(-H "Authorization: Bearer $GITHUB_TOKEN" -H "Accept: application/vnd.github+json")
  elif [[ -n "${GH_TOKEN:-}" ]]; then
    api_curl_args=(-H "Authorization: Bearer $GH_TOKEN" -H "Accept: application/vnd.github+json")
  fi

  release_json="$(curl -fsSL "${api_curl_args[@]}" "$QUARTO_RELEASES_API")"
  quarto_version="$(json_release_tag_name "$release_json")"

  if [[ -z "$quarto_version" ]]; then
    echo "   Could not determine latest Quarto version."
    exit 1
  fi

  case "$arch" in
    arm64)
      asset_name_candidates=(
        "quarto-$quarto_version-macos-arm64.pkg"
        "quarto-$quarto_version-macos-aarch64.pkg"
        "quarto-$quarto_version-macos.pkg"
      )
      ;;
    x86_64)
      asset_name_candidates=(
        "quarto-$quarto_version-macos-x64.pkg"
        "quarto-$quarto_version-macos-amd64.pkg"
        "quarto-$quarto_version-macos.pkg"
      )
      ;;
    *)
      echo "   Unsupported macOS architecture for Quarto: $arch"
      exit 1
      ;;
  esac

  if ! quarto_url="$(json_find_asset_url "$release_json" "${asset_name_candidates[@]}")"; then
    echo "   Could not determine the correct Quarto installer for macOS $arch."
    exit 1
  fi

  quarto_asset_name="${quarto_url##*/}"
  checksums_asset_name="quarto-$quarto_version-checksums.txt"
  checksums_url="$(json_find_asset_url "$release_json" "$checksums_asset_name")"

  if [[ -z "$checksums_url" ]]; then
    echo "   Could not determine the Quarto checksum file."
    exit 1
  fi

  echo "   Detected macOS architecture: $arch"
  echo "   Latest Quarto release: $quarto_version"
  echo "   Using Quarto installer asset: $quarto_asset_name"

  pkg_path="$TEMP_DIR/quarto.pkg"
  checksums_path="$TEMP_DIR/quarto-checksums.txt"
  curl -fsSL -o "$pkg_path" "$quarto_url"
  check_success "Quarto download"
  curl -fsSL -o "$checksums_path" "$checksums_url"
  check_success "Quarto checksum download"

  expected_sha="$(awk -v name="$quarto_asset_name" '$2 == name { print $1; exit }' "$checksums_path")"
  if [[ -z "$expected_sha" ]]; then
    echo "   Could not find a checksum for $quarto_asset_name."
    exit 1
  fi

  actual_sha="$(shasum -a 256 "$pkg_path" | awk '{print $1}')"
  if [[ "$actual_sha" != "$expected_sha" ]]; then
    echo "   Quarto checksum verification failed."
    echo "   Expected: $expected_sha"
    echo "   Actual:   $actual_sha"
    exit 1
  fi

  sudo installer -pkg "$pkg_path" -target /
  check_success "Quarto installation"
  ensure_quarto_command
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

ensure_usr_local_permissions
install_xcode_command_line_tools

echo "   Verifying git from Xcode Command Line Tools..."
git --version
echo

install_vscode
install_node
install_github_cli
install_quarto
install_uv

echo "Step 8: Installing UV-managed Python $DEFAULT_PYTHON_VERSION..."
uv python install --default "$DEFAULT_PYTHON_VERSION"
check_success "Python installation"
echo

echo "Step 9: Installing Claude Code and Codex..."
install_npm_package "@anthropic-ai/claude-code" "claude"
install_npm_package "@openai/codex" "codex"
echo

echo "Step 10: Verifying installed tools..."
verify_command "git" "git --version"
verify_command "node" "node --version"
verify_command "npm" "npm --version"
verify_command "gh" "gh --version | head -n1"
verify_command "quarto" "quarto --version | head -n1"
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
