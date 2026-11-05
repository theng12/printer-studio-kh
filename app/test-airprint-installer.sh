#!/bin/bash
#
# Runs the focused AirPrint installer test suite.
#
# Retains build artifacts in _trash without deleting any files.
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
ARCH="$(uname -m)"
OUT="$ROOT/../_trash/test-airprint-installer-$(date +%Y%m%d-%H%M%S)-$$"
mkdir -p "$OUT"

echo "==> Compiling TestAirPrintInstaller ($ARCH)"
# The sharing dependency is injected so tests never change live queues.
SOURCES=(
  "$ROOT/Sources/PrinterStudio/CUPS.swift"
  "$ROOT/Sources/PrinterStudio/PageSizeInstaller.swift"
  "$ROOT/Sources/PrinterStudio/TestPage.swift"
  "$ROOT/Sources/PrinterStudio/DriverInstaller.swift"
  "$ROOT/Sources/PrinterStudio/ShareFix.swift"
  "$ROOT/Sources/PrinterStudio/Shell.swift"
  "$ROOT/Sources/PrinterStudio/Models.swift"
  "$ROOT/Sources/PrinterStudio/StickerSizes.swift"
  "$ROOT/Sources/PrinterStudio/USBPrinterService.swift"
  "$ROOT/Tools/TestAirPrintInstaller.swift"
)

BIN="$OUT/TestAirPrintInstaller"
/usr/bin/swiftc \
  -parse-as-library \
  -swift-version 5 \
  -target "${ARCH}-apple-macos13.0" \
  -o "$BIN" \
  "${SOURCES[@]}"

echo "==> Running TestAirPrintInstaller"
"$BIN" "$ROOT/Resources/airprint-bridge.sh"
