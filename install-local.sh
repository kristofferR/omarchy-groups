#!/usr/bin/env bash
set -euo pipefail
source_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
target_dir="$HOME/.config/omarchy/plugins/kristofferr.groups"
omarchy plugin validate "$source_dir"
mkdir -p -- "$target_dir"
# Deploy only runtime files. Layout and plugin settings remain user-owned.
for file in BarWidget.qml LayoutModel.js GroupIcons.js manifest.json LICENSE; do
  install -m 644 -- "$source_dir/$file" "$target_dir/$file"
done
# Hosted widgets retain Component references across a plugin-only rescan.
# Restart once so Qt cannot reuse the previous drawer implementation.
omarchy restart shell
