#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT="$ROOT/../_trash/test-test-page-$(date +%Y%m%d-%H%M%S)-$$"
mkdir -p "$OUT"
/usr/bin/swiftc -parse-as-library -swift-version 5 -framework CoreGraphics \
  "$ROOT/Sources/PrinterStudio/TestPage.swift" "$ROOT/Tools/TestTestPage.swift" -o "$OUT/check"
"$OUT/check" "$OUT"
