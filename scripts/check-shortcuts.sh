#!/bin/zsh
set -euo pipefail
repo_dir="${0:A:h:h}"
mkdir -p "$repo_dir/build/shortcut-validation"
swiftc -swift-version 6 -parse-as-library \
  "$repo_dir/Ben/Services/GlobalShortcut.swift" \
  "$repo_dir/Tests/GlobalShortcutChecks.swift" \
  -o "$repo_dir/build/shortcut-validation/check-shortcuts"
"$repo_dir/build/shortcut-validation/check-shortcuts"
