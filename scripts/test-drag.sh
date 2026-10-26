#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_app="$PWD/.build/DragChecks.app"
mkdir -p "$test_app/Contents/MacOS" "$test_app/Contents/Resources"
./scripts/swift.sh --compile -swift-version 5 -parse-as-library \
  Sources/PaperTodo/DesktopWidget.swift Sources/PaperTodo/PrinterDragArea.swift \
  Sources/PaperTodo/TodoStore.swift Sources/PaperTodo/PrintEngine.swift Sources/PaperTodo/PrinterAudio.swift \
  Sources/PaperTodo/DesktopSettings.swift Sources/PaperTodo/Materials.swift \
  Sources/PaperTodo/ThermalMaterial.swift Sources/PaperTodo/MarkerStrike.swift \
  Sources/PaperTodo/WindowPresentation.swift \
  Sources/PaperTodo/PaperScrollView.swift \
  Tests/DragChecks.swift -o "$test_app/Contents/MacOS/DragChecks"
cp Sources/PaperTodo/Resources/*.png "$test_app/Contents/Resources/"
cat > "$test_app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>DragChecks</string>
<key>CFBundleIdentifier</key><string>com.paperdesk.DragChecks</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
"$test_app/Contents/MacOS/DragChecks" "$@"
