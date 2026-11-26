#!/bin/bash
#
# Runs the focused AirPrint installer test suite.
#
# Keeps its build artifacts in a scratch dir under TMPDIR; nothing is deleted.
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
ARCH="$(uname -m)"
OUT="$(mktemp -d "${TMPDIR:-/tmp}/test-airprint-installer.XXXXXX")"

echo "==> Checking ShareFix never reaches the cupsctl sharing default"
# Bug #33: both install and migration must inject their own sharing step.
if grep -q "CUPS.prepareAirPrintSharing" "$ROOT/Sources/PrinterStudio/ShareFix.swift"; then
  echo "  ✗ FAIL: ShareFix.swift references the cupsctl sharing default directly"
  exit 1
fi
echo "  ✓ ShareFix.swift never references the cupsctl sharing default"

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
