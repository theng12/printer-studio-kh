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

# Universal, like the app: the diagnostic should run on whatever Mac is in
# front of you, including an Intel one.
SLICES="$(mktemp -d)"
trap 'rm -rf "$SLICES"' EXIT

for ARCH in arm64 x86_64; do
  /usr/bin/swiftc \
    -O \
    -parse-as-library \
    -swift-version 5 \
    -target "${ARCH}-apple-macos13.0" \
    -o "$SLICES/report.$ARCH" \
    "${SOURCES[@]}"
done

/usr/bin/lipo -create "$SLICES/report.arm64" "$SLICES/report.x86_64" -output "$OUT"
echo "==> Built: $OUT ($(/usr/bin/lipo -info "$OUT" | sed 's/.*are: //'))"
