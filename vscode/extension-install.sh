#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
extensions_file="$script_dir/extensions.txt"

while IFS= read -r extension || [[ -n "$extension" ]]; do
  [[ -z "$extension" ]] && continue
  code --install-extension "$extension" --force
done < "$extensions_file"
