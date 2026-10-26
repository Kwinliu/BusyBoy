#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/swift.sh --compile -swift-version 5 -parse-as-library \
  Sources/PaperTodo/TodoStore.swift Sources/PaperTodo/PrintEngine.swift Sources/PaperTodo/PrinterAudio.swift \
  Tests/StoreChecks.swift -o .build/StoreChecks
.build/StoreChecks
