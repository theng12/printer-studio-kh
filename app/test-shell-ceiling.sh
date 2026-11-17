#!/bin/bash
# Compiles and runs the shell ceiling suite: a command answers, fails with its
# reason, or is stopped at its own ceiling — and a big stderr cannot deadlock it.
# No window, no desktop, no printer.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT="$ROOT/../_trash/test-shell-ceiling-$(date +%Y%m%d-%H%M%S)-$$"
mkdir -p "$OUT"

/usr/bin/swiftc -parse-as-library -swift-version 5 \
  "$ROOT/Sources/PrinterStudio/Shell.swift" "$ROOT/Tools/TestShell.swift" \
  -o "$OUT/check"
"$OUT/check"
