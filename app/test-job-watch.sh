#!/bin/bash
# Compiles and runs the focused job-watch suite: which queued job counts as news.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT="$(mktemp -d "${TMPDIR:-/tmp}/test-job-watch.XXXXXX")"
/usr/bin/swiftc -parse-as-library -swift-version 5 \
  "$ROOT/Sources/PrinterStudio/JobWatch.swift" "$ROOT/Tools/TestJobWatch.swift" -o "$OUT/check"
"$OUT/check"
