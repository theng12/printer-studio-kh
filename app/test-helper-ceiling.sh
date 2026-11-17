#!/bin/bash
# Compiles the helper with its ceiling driver and proves, without a printer and
# without a window: a quick command answers whole, a stuck command is stopped at
# its ceiling and says so, and a large stderr cannot deadlock the reader.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT="$ROOT/../_trash/test-helper-ceiling-$(date +%Y%m%d-%H%M%S)-$$"
mkdir -p "$OUT"

/usr/bin/swiftc -swift-version 5 -D HELPER_CEILING_TEST \
  "$ROOT/Helper/main.swift" "$ROOT/Tools/TestHelperCeiling.swift" \
  -o "$OUT/check"
PRINTER_STUDIO_CEILING_DRIVER=1 "$OUT/check"
