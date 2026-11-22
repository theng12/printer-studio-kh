#!/bin/bash
#
# Compiles and runs the focused TestUpdateChecker suite on the native
# architecture. It never touches the network or the real publisher file.
# Retains build artifacts in _trash without deleting any files.
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
ARCH="$(uname -m)"
# Own scratch dir: the checkout _trash link may dangle.
TRASH="$(mktemp -d "${TMPDIR:-/tmp}/printer-update-checker.XXXXXX")"

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
"$BIN" "$ROOT/Resources/PublisherKey.txt"

# The pin must travel in the built app unchanged, or the fix only exists in source.
APP="${1:-$ROOT/../dist/Printer Studio KH.app}"
if [ -d "$APP" ]; then
  if ! /usr/bin/cmp -s "$ROOT/Resources/PublisherKey.txt" "$APP/Contents/Resources/PublisherKey.txt"; then
    echo "FAIL: the built app does not carry the pinned update key unchanged" >&2
    exit 1
  fi
  echo "==> Built app carries the pinned key unchanged"
else
  echo "SKIP: no built app at $APP, so the bundled copy is not checked (the gate builds first)"
fi

echo "==> Update checker checks passed."
