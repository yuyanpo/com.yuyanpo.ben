#!/bin/zsh
set -euo pipefail
repo_dir="${0:A:h:h}"
mkdir -p "$repo_dir/build/baidu-validation"
swiftc -swift-version 6 -parse-as-library \
  "$repo_dir/Ben/Models/TranslationModels.swift" \
  "$repo_dir/Ben/Services/TranslationProvider.swift" \
  "$repo_dir/Ben/Services/BaiduTranslationProvider.swift" \
  "$repo_dir/Ben/Services/BaiduRequestToken.swift" \
  "$repo_dir/Tests/BaiduTranslationChecks.swift" \
  -o "$repo_dir/build/baidu-validation/check-baidu"
"$repo_dir/build/baidu-validation/check-baidu" "$@"
