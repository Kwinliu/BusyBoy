#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
project_root="$(pwd -P)"
case "$project_root" in
  *OneDrive*|*CloudStorage*|*Mobile\ Documents*|*Dropbox*)
    echo '请先把开发工作树放到非同步的本地短路径，再运行打包。' >&2
    exit 1
    ;;
esac

guide="$project_root/output/pdf/BusyBoy-User-Guide-zh-CN.pdf"
if [ ! -f "$guide" ]; then
  echo '缺少 PDF 说明书：请先生成 output/pdf/BusyBoy-User-Guide-zh-CN.pdf。' >&2
  exit 1
fi
./scripts/build.sh
source_app="$project_root/dist/纸间.app"
version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$source_app/Contents/Info.plist")"
architecture="$(lipo -archs "$source_app/Contents/MacOS/PaperTodo")"
if [ "$architecture" != arm64 ]; then
  echo "请检查发行包架构：$architecture" >&2
  exit 1
fi

mkdir -p .build/publication
stage="$(mktemp -d "$project_root/.build/publication/package.XXXXXX")"
mkdir "$stage/BusyBoy"
ditto "$source_app" "$stage/BusyBoy/BusyBoy.app"
cp "$guide" "$stage/BusyBoy/BusyBoy-User-Guide-zh-CN.pdf"
cat > "$stage/BusyBoy/安装说明.txt" <<'TEXT'
BusyBoy · 桌面待办机

适用：macOS 14 或更新版本，Apple Silicon Mac。
将 BusyBoy.app 拖入“应用程序”，双击启动。
点击机身 + 或按 Control + Option + Space 写待办。
应用位于桌面和菜单栏，不显示 Dock 图标。

此版本使用临时签名，尚未进行 Apple Developer ID 签名和公证。
请核对官方 Release 与 SHA-256 校验值，并参考 Apple 官方打开说明：
https://support.apple.com/zh-cn/102445

使用方法见同目录配图 PDF。
项目：https://github.com/Kwinliu/BusyBoy
下载：https://github.com/Kwinliu/BusyBoy/releases/latest
TEXT
codesign --verify --deep --strict "$stage/BusyBoy/BusyBoy.app"
archive="BusyBoy-v$version-macOS-arm64.zip"
ditto -c -k --sequesterRsrc --keepParent "$stage/BusyBoy" "$project_root/dist/$archive"
(
  cd dist
  shasum -a 256 "$archive"
  shasum -a 256 "$guide" | sed 's#  .*/#  #'
) > dist/SHA256SUMS.txt
printf '已打包：%s/dist/%s\n' "$project_root" "$archive"
printf '暂存目录：%s\n' "$stage"
