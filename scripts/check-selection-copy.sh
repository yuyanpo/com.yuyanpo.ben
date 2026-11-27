#!/bin/zsh
set -euo pipefail
repo_dir="${0:A:h:h}"
output_dir="$repo_dir/build/selection-validation"
mkdir -p "$output_dir"
swiftc -swift-version 6 -parse-as-library \
  "$repo_dir"/Ben/Models/TranslationModels.swift \
  "$repo_dir"/Ben/Services/SelectedTextReader.swift \
  "$repo_dir"/Ben/Services/SelectionCopyFallback.swift \
  "$repo_dir"/Ben/Services/SelectionDiagnostics.swift \
  "$repo_dir"/Ben/Services/TranslationProvider.swift \
  "$repo_dir"/Ben/Services/BaiduTranslationProvider.swift \
  "$repo_dir"/Ben/Services/BaiduRequestToken.swift \
  "$repo_dir"/Tests/SelectionCopyChecks.swift \
  -o "$output_dir/check-selection-copy"
"$output_dir/check-selection-copy"
