#!/bin/bash
#
# Compiles and runs the focused TestListPresentation suite on the native architecture.
# Keeps its build artifacts in a scratch dir under TMPDIR; nothing is deleted.
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
ARCH="$(uname -m)"
TRASH="$(mktemp -d "${TMPDIR:-/tmp}/test-list-presentation.XXXXXX")"

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
