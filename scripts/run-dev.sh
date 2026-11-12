#!/bin/zsh
set -euo pipefail

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
app_path="$repo_dir/build/Build/Products/Debug/Ben.app"

xcodebuild -project "$repo_dir/Ben.xcodeproj" -scheme Ben -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath "$repo_dir/build" \
  CODE_SIGNING_ALLOWED=YES build

# Restart only this checkout's Debug app after a successful build.
for app_pid in $(pgrep -x Ben || true); do
  executable="$(ps -p "$app_pid" -o comm= || true)"
  if [[ "$executable" == "$app_path/Contents/MacOS/Ben" ]]; then
    kill -TERM "$app_pid"
    for attempt in {1..50}; do
      if ! kill -0 "$app_pid" 2>/dev/null; then
        break
      fi
      sleep 0.1
    done
    if kill -0 "$app_pid" 2>/dev/null; then
      print -u2 "Ben 尚未退出，请从菜单栏退出 Ben 后重试。"
      exit 1
    fi
  fi
done

# Let Finder discard an icon cached for the previous build at this path.
touch "$app_path"
open "$app_path"
print "已启动 Debug 版本：$app_path"
