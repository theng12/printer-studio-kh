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
# A stand-in helper bundle: the installer only copies it into the scratch
# support directory, so no signed binary is needed for this file-handling test.
FAKE_HELPER="$OUT/Printer Studio KH Helper.app"
mkdir -p "$FAKE_HELPER/Contents/MacOS" "$FAKE_HELPER/Contents/Resources"
printf '#!/bin/sh\nexit 0\n' > "$FAKE_HELPER/Contents/MacOS/Printer Studio KH Helper"
chmod 755 "$FAKE_HELPER/Contents/MacOS/Printer Studio KH Helper"
"$BIN" "$FAKE_HELPER"
