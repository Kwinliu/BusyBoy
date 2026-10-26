#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/swift.sh --compile -swift-version 5 -parse-as-library \
  Sources/PaperTodo/StickerServices.swift Sources/PaperTodo/StickerUtilityViews.swift \
  Sources/PaperTodo/Pomodoro.swift Sources/PaperTodo/Materials.swift Sources/PaperTodo/UtilityMaterials.swift Sources/PaperTodo/PrinterAudio.swift \
  Tests/StickerChecks.swift -o .build/StickerChecks
.build/StickerChecks "$@"
