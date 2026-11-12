#!/bin/zsh
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
swift "$repo_dir/scripts/generate-app-icons.swift" "$repo_dir"
