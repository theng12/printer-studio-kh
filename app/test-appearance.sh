#!/bin/bash
#
# Compiles and runs the focused TestAppearance suite on the native architecture.
# Retains build artifacts in _trash without deleting any files.
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
ARCH="$(uname -m)"
TRASH="$ROOT/../_trash/test-appearance-$(date +%Y%m%d-%H%M%S)-$$"
mkdir -p "$TRASH"

echo "==> Gathering sources for TestAppearance ($ARCH)"
SOURCES=()
while IFS= read -r file; do
  case "$(basename "$file")" in
    App.swift|Views.swift|RenderFixtures.swift) continue ;;
  esac
  SOURCES+=("$file")
done < <(find "$ROOT/Sources/PrinterStudio" -name '*.swift' | sort)
SOURCES+=("$ROOT/Tools/TestAppearance.swift")

BIN="$TRASH/TestAppearance"

echo "==> Compiling native test runner (${#SOURCES[@]} sources)"
/usr/bin/swiftc \
  -O \
  -parse-as-library \
  -swift-version 5 \
  -target "${ARCH}-apple-macos13.0" \
  -framework SwiftUI \
  -o "$BIN" \
  "${SOURCES[@]}"

echo "==> Running TestAppearance"
"$BIN"

echo "==> Appearance checks passed."
