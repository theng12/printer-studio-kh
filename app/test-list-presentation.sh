#!/bin/bash
#
# Compiles and runs the focused TestListPresentation suite on the native architecture.
# Retains build artifacts in _trash without deleting any files.
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
ARCH="$(uname -m)"
TRASH="$ROOT/../_trash/test-list-presentation-$(date +%Y%m%d-%H%M%S)-$$"
mkdir -p "$TRASH"

echo "==> Gathering sources for TestListPresentation ($ARCH)"
SOURCES=()
while IFS= read -r file; do
  case "$(basename "$file")" in
    App.swift|Views.swift|RenderFixtures.swift) continue ;;
  esac
  SOURCES+=("$file")
done < <(find "$ROOT/Sources/PrinterStudio" -name '*.swift' | sort)
SOURCES+=("$ROOT/Tools/TestListPresentation.swift")

BIN="$TRASH/TestListPresentation"

echo "==> Compiling native test runner (${#SOURCES[@]} sources)"
/usr/bin/swiftc \
  -O \
  -parse-as-library \
  -swift-version 5 \
  -target "${ARCH}-apple-macos13.0" \
  -framework SwiftUI \
  -framework AppKit \
  -o "$BIN" \
  "${SOURCES[@]}"

echo "==> Running TestListPresentation"
"$BIN"

echo "==> List presentation checks passed."
