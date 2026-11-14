#!/bin/bash
#
# Compiles and runs the focused TestUpdateChecker suite on the native
# architecture. It never touches the network or the real publisher file.
# Retains build artifacts in _trash without deleting any files.
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
ARCH="$(uname -m)"
TRASH="$ROOT/../_trash/test-update-checker-$(date +%Y%m%d-%H%M%S)-$$"
mkdir -p "$TRASH"

echo "==> Gathering sources for TestUpdateChecker ($ARCH)"
SOURCES=()
while IFS= read -r file; do
  case "$(basename "$file")" in
    App.swift|Views.swift|RenderFixtures.swift) continue ;;
  esac
  SOURCES+=("$file")
done < <(find "$ROOT/Sources/PrinterStudio" -name '*.swift' | sort)
SOURCES+=("$ROOT/Tools/TestUpdateChecker.swift")

BIN="$TRASH/TestUpdateChecker"

echo "==> Compiling native test runner (${#SOURCES[@]} sources)"
/usr/bin/swiftc \
  -O \
  -parse-as-library \
  -swift-version 5 \
  -target "${ARCH}-apple-macos13.0" \
  -o "$BIN" \
  "${SOURCES[@]}"

echo "==> Running TestUpdateChecker"
"$BIN"

echo "==> Update checker checks passed."
