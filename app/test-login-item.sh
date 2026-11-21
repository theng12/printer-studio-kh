#!/bin/bash
#
# Compiles and runs the focused TestLoginItem suite on the native architecture,
# then asserts from source that no caller replaces the registration state's own
# sentence with a success string.
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
ARCH="$(uname -m)"
TRASH="$(mktemp -d "${TMPDIR:-/tmp}/printer-login-item-test.XXXXXX")"

echo "==> Gathering sources for TestLoginItem ($ARCH)"
SOURCES=()
while IFS= read -r file; do
  case "$(basename "$file")" in
    App.swift|Views.swift|RenderFixtures.swift) continue ;;
  esac
  SOURCES+=("$file")
done < <(find "$ROOT/Sources/PrinterStudio" -name '*.swift' | sort)
SOURCES+=("$ROOT/Tools/TestLoginItem.swift")

BIN="$TRASH/TestLoginItem"

echo "==> Compiling native test runner (${#SOURCES[@]} sources)"
/usr/bin/swiftc \
  -O \
  -parse-as-library \
  -swift-version 5 \
  -target "${ARCH}-apple-macos13.0" \
  -o "$BIN" \
  "${SOURCES[@]}"

echo "==> Running TestLoginItem"
"$BIN"

# The launch path and the Settings toggle must report what the system said. The
# old line below overwrote it with a success sentence while macOS was waiting.
if grep -q 'success: "Printer Studio KH will open at login."' "$ROOT/Sources/PrinterStudio/App.swift"; then
  echo "FAIL: App.swift still overwrites the login item's own sentence with a success string" >&2
  exit 1
fi
echo "==> No caller overwrites the login item's own sentence"

echo "==> Login item checks passed."
