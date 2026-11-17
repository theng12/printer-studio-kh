#!/bin/bash
# Compiles and runs the full-disk suite. The real case fills a small throwaway
# volume, never this Mac's disk, and detaches it afterwards.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT="$ROOT/../_trash/test-disk-space-$(date +%Y%m%d-%H%M%S)-$$"
mkdir -p "$OUT"

/usr/bin/swiftc -parse-as-library -swift-version 5 \
  "$ROOT/Sources/PrinterStudio/Shell.swift" "$ROOT/Tools/TestDiskSpace.swift" \
  -o "$OUT/check"

/usr/bin/hdiutil create -quiet -size 4m -fs HFS+ -volname PSFull "$OUT/full.dmg"
mkdir -p "$OUT/mnt"
/usr/bin/hdiutil attach -quiet -nobrowse -mountpoint "$OUT/mnt" "$OUT/full.dmg"
trap '/usr/bin/hdiutil detach -quiet "$OUT/mnt" >/dev/null 2>&1 || true' EXIT

"$OUT/check" "$OUT/mnt"
