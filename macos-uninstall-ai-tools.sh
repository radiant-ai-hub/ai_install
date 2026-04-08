#!/usr/bin/env bash

set -euo pipefail

echo "Rady School of Management @ UCSD"
echo "AI Coding Tools Uninstaller for macOS"
echo "====================================="
echo
echo "This removes the tools installed by this repo."
echo "It does not remove Xcode Command Line Tools."
echo

if [[ "${CI:-false}" != "true" ]]; then
  read -r -p "Type 'yes' to continue: " CONFIRM
  if [[ "$CONFIRM" != "yes" ]]; then
    echo "Uninstall cancelled."
    exit 0
  fi
fi

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

remove_target() {
  local path="$1"
  if [[ -e "$path" || -L "$path" ]]; then
    rm -rf "$path" 2>/dev/null || sudo rm -rf "$path"
  fi
}

echo "Step 1: Removing npm-installed CLIs..."
if command_exists npm; then
  npm uninstall -g @anthropic-ai/claude-code || true
  npm uninstall -g @openai/codex || true
fi
echo

echo "Step 2: Removing UV-managed Python and uv..."
if command_exists uv; then
  uv python uninstall --all || true
  uv cache clean || true
fi
remove_target "$HOME/.local/bin/uv"
remove_target "$HOME/.local/bin/uvx"
remove_target "$HOME/.local/bin/uvw"
remove_target "$HOME/.local/share/uv"
remove_target "$HOME/.cache/uv"
echo

echo "Step 3: Removing Visual Studio Code..."
remove_target "/Applications/Visual Studio Code.app"
remove_target "/usr/local/bin/code"
remove_target "$HOME/Library/Application Support/Code"
remove_target "$HOME/Library/Caches/com.microsoft.VSCode"
remove_target "$HOME/Library/Preferences/com.microsoft.VSCode.plist"
echo

echo "Step 4: Removing GitHub CLI symlink..."
remove_target "/usr/local/bin/gh"
echo

echo "Step 5: Removing Quarto files..."
remove_target "/usr/local/bin/quarto"
remove_target "/Applications/quarto"
remove_target "/opt/quarto"
echo

echo "Step 6: Removing Node.js files commonly installed by the macOS pkg..."
remove_target "/usr/local/bin/node"
remove_target "/usr/local/bin/npm"
remove_target "/usr/local/bin/npx"
remove_target "/usr/local/include/node"
remove_target "/usr/local/lib/node_modules"
remove_target "/usr/local/share/doc/node"
remove_target "/usr/local/share/man/man1/node.1"
echo

echo "Uninstall complete."
