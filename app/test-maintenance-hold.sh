#!/bin/bash
# Compiles and runs the focused update-hold suite: the pause, the real in-flight count, the
# bounded settle, the release, an abandoned hold expiring, a fresh start opening, and the
# loopback route over real HTTP. No window, no desktop, no printer.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT="$ROOT/../_trash/test-maintenance-hold-$(date +%Y%m%d-%H%M%S)-$$"
mkdir -p "$OUT"
/usr/bin/swiftc -parse-as-library -swift-version 5 \
  "$ROOT/Sources/PrinterStudio/MaintenanceHold.swift" "$ROOT/Tools/TestMaintenanceHold.swift" \
  -o "$OUT/check"
"$OUT/check"
