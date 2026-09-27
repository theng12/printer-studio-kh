#!/bin/bash
#
# Builds "printer-studio-report", a CLI diagnostic built from the same service
# code as the app. No GUI, no @State, no Xcode — just the shared logic.
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT="$ROOT/../dist/printer-studio-report"

SOURCES=(
  "$ROOT/Sources/PrinterStudio/Shell.swift"
  "$ROOT/Sources/PrinterStudio/Models.swift"
  "$ROOT/Sources/PrinterStudio/CUPS.swift"
  "$ROOT/Sources/PrinterStudio/ShareFix.swift"
  "$ROOT/Sources/PrinterStudio/Driver.swift"
  "$ROOT/Sources/PrinterStudio/DriverInstaller.swift"
  "$ROOT/Tools/Report.swift"
)

for file in "${SOURCES[@]}"; do
  if [ ! -f "$file" ]; then
    echo "!! Missing source: $file" >&2
    exit 1
  fi
done

mkdir -p "$(dirname "$OUT")"

/usr/bin/swiftc \
  -O \
  -parse-as-library \
  -swift-version 5 \
  -target arm64-apple-macos15.0 \
  -o "$OUT" \
  "${SOURCES[@]}"

echo "==> Built: $OUT"
