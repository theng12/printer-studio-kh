#!/bin/bash
# Compiles and runs the focused job-watch suite: which queued job counts as news.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT="$ROOT/../_trash/test-job-watch-$(date +%Y%m%d-%H%M%S)-$$"
mkdir -p "$OUT"
/usr/bin/swiftc -parse-as-library -swift-version 5 \
  "$ROOT/Sources/PrinterStudio/JobWatch.swift" "$ROOT/Tools/TestJobWatch.swift" -o "$OUT/check"
"$OUT/check"
