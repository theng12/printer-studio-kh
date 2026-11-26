#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT="$(mktemp -d "${TMPDIR:-/tmp}/test-test-page.XXXXXX")"
/usr/bin/swiftc -parse-as-library -swift-version 5 -framework CoreGraphics \
  "$ROOT/Sources/PrinterStudio/TestPage.swift" "$ROOT/Tools/TestTestPage.swift" -o "$OUT/check"
"$OUT/check" "$OUT"
