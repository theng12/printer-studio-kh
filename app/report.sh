#!/bin/bash
#
# Builds "printer-studio-report", a CLI diagnostic built from the same service
# code as the app. No GUI, no @State, no Xcode — just the shared logic.
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT="$ROOT/../dist/printer-studio-report"

# Every service source except the two that are SwiftUI-only. Globbing rather
# than a hand-written list: a hardcoded list silently went stale when
# LoginItem.swift was added, and because the old binary was still on disk the
# build failure produced plausible-looking output from stale code.
SOURCES=()
while IFS= read -r file; do
  case "$(basename "$file")" in
    App.swift|Views.swift) continue ;;   # SwiftUI and @main; the CLI needs neither
  esac
  SOURCES+=("$file")
done < <(find "$ROOT/Sources/PrinterStudio" -name '*.swift' | sort)
SOURCES+=("$ROOT/Tools/Report.swift")

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
