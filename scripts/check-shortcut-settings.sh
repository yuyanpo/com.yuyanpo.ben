#!/bin/zsh
set -euo pipefail
repo_dir="${0:A:h:h}"
output_dir="$repo_dir/build/shortcut-validation/settings"
mkdir -p "$output_dir"
swiftc -swift-version 6 -parse-as-library \
  "$repo_dir"/Ben/Models/*.swift \
  "$repo_dir"/Ben/Services/*.swift \
  "$repo_dir/Ben/Views/SettingsView.swift" \
  "$repo_dir/Ben/Views/ShortcutRecorder.swift" \
  "$repo_dir/Tests/ShortcutSettingsChecks.swift" \
  -o "$output_dir/check-settings"
"$output_dir/check-settings" "$output_dir"
