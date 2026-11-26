#!/bin/bash
#
# Compiles and runs the focused TestErrorReport test suite on the native architecture.
# Keeps its build artifacts in a scratch dir under TMPDIR; nothing is deleted.
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
ARCH="$(uname -m)"
TRASH="$(mktemp -d "${TMPDIR:-/tmp}/test-error-report.XXXXXX")"

echo "==> Gathering sources for TestErrorReport ($ARCH)"
SOURCES=()
while IFS= read -r file; do
  case "$(basename "$file")" in
    App.swift|Views.swift|RenderFixtures.swift) continue ;;
  esac
  SOURCES+=("$file")
done < <(find "$ROOT/Sources/PrinterStudio" -name '*.swift' | sort)
SOURCES+=("$ROOT/Tools/TestErrorReport.swift")

BIN="$TRASH/TestErrorReport"

echo "==> Compiling native test runner (${#SOURCES[@]} sources)"
/usr/bin/swiftc \
  -O \
  -parse-as-library \
  -swift-version 5 \
  -target "${ARCH}-apple-macos13.0" \
  -o "$BIN" \
  "${SOURCES[@]}"

echo "==> Running TestErrorReport"
"$BIN"

echo "==> Typechecking full SwiftUI app target"
# Same pin as build.sh:42-47 — the CLT 27.2 SDK's SwiftUI macro plugin ships only with Xcode.
# shortcut: SDK 26.5 until the CLT ships the plugin; upgrade when it does.
SDK="$(/usr/bin/xcrun --show-sdk-path --sdk macosx26.5 2>/dev/null || true)"
[ -n "$SDK" ] || SDK="$(/usr/bin/xcrun --show-sdk-path)"
/usr/bin/swiftc \
  -typecheck \
  -parse-as-library \
  -swift-version 5 \
  -sdk "$SDK" \
  -target "${ARCH}-apple-macos13.0" \
  -framework SwiftUI \
  -framework AppKit \
  "$ROOT/Sources/PrinterStudio"/*.swift

echo "==> All error report checks and typechecks passed."
