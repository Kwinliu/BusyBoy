#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
project_root="$(pwd -P)"
case "$project_root" in
  *OneDrive*|*CloudStorage*|*Mobile\ Documents*|*Dropbox*)
    echo '请先把开发工作树放到非同步的本地短路径，再运行构建。' >&2
    exit 1
    ;;
esac

configuration="${1:-release}"
case "$configuration" in release|debug) ;; *) echo '用法：scripts/build.sh [release|debug]' >&2; exit 1 ;; esac
./scripts/swift.sh build -c "$configuration"
binary_dir="$(./scripts/swift.sh build -c "$configuration" --show-bin-path)"
app_dir="$project_root/dist/纸间.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$binary_dir/PaperTodo" "$app_dir/Contents/MacOS/PaperTodo.next"
mv -f "$app_dir/Contents/MacOS/PaperTodo.next" "$app_dir/Contents/MacOS/PaperTodo"
cat > "$app_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>PaperTodo</string>
  <key>CFBundleIdentifier</key><string>com.paperdesk.PaperTodo</string>
  <key>CFBundleName</key><string>BusyBoy</string>
  <key>CFBundleDisplayName</key><string>BusyBoy</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>LSUIElement</key><true/>
  <key>NSHumanReadableCopyright</key><string>BusyBoy · One thing at a time.</string>
</dict></plist>
PLIST

if [ ! -f .build/AppIcon.icns ] || [ scripts/icon.swift -nt .build/AppIcon.icns ]; then
  ./scripts/swift.sh scripts/icon.swift .build
  iconutil -c icns .build/AppIcon.iconset -o .build/AppIcon.icns
fi
cp .build/AppIcon.icns "$app_dir/Contents/Resources/AppIcon.icns"
cp Sources/PaperTodo/Resources/printer-busyboy.png "$app_dir/Contents/Resources/printer-busyboy.png"
cp Sources/PaperTodo/Resources/thermal-paper.png "$app_dir/Contents/Resources/thermal-paper.png"
rm -f "$app_dir/Contents/Resources/printer-body.png" "$app_dir/Contents/Resources/printer-lazyman.png"
codesign --force --deep --sign - "$app_dir"
printf '\n已构建：%s\n' "$app_dir"
