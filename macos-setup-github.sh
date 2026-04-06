#!/usr/bin/env bash

set -euo pipefail

REPO_RAW_BASE="https://raw.githubusercontent.com/radiant-ai-hub/ai_install/main"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This GitHub setup command is intended for macOS."
  exit 1
fi

runner_path=""
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local_runner="$script_dir/github-setup.sh"
  if [[ -f "$local_runner" ]]; then
    runner_path="$local_runner"
  fi
fi

if [[ -z "$runner_path" ]]; then
  runner_path="$(mktemp)"
  trap 'rm -f "$runner_path"' EXIT
  curl -fsSL "$REPO_RAW_BASE/github-setup.sh" -o "$runner_path"
fi

bash "$runner_path"
