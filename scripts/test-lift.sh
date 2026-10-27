#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_app="$PWD/.build/LiftChecks.app"
mkdir -p "$test_app/Contents/MacOS"
./scripts/swift.sh --compile -swift-version 5 -parse-as-library \
  Sources/PaperTodo/StickerServices.swift Sources/PaperTodo/StickerUtilityViews.swift \
  Sources/PaperTodo/Pomodoro.swift Sources/PaperTodo/AlarmClock.swift Sources/PaperTodo/Materials.swift Sources/PaperTodo/UtilityMaterials.swift \
  Sources/PaperTodo/StickerPanelController.swift Sources/PaperTodo/PrinterAudio.swift Sources/PaperTodo/WindowPresentation.swift \
  Tests/LiftChecks.swift -o "$test_app/Contents/MacOS/LiftChecks"
cat > "$test_app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>LiftChecks</string>
<key>CFBundleIdentifier</key><string>com.paperdesk.LiftChecks</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
"$test_app/Contents/MacOS/LiftChecks"
