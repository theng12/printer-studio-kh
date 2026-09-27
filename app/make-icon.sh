#!/bin/bash
#
# Builds the app icon: draws it, scales it, and packs it into PrinterStudio.icns.
#
#   ./app/make-icon.sh          regenerate app/Resources/PrinterStudio.icns
#
# The icon is drawn in code by Tools/make-icon.swift, so it can be tweaked and
# regenerated without a design tool and the repository stays text-only. Only the
# finished .icns is committed, because that is what the app needs at build time
# and regenerating it should not be a prerequisite for building.
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

BASE="$WORK/icon-1024.png"
ICONSET="$WORK/PrinterStudio.iconset"

echo "==> Drawing the icon"
/usr/bin/swift "$ROOT/Tools/make-icon.swift" "$BASE" 1024

echo "==> Scaling"
mkdir -p "$ICONSET"
# The set macOS asks for: each size at 1x and 2x.
while read -r px name; do
  /usr/bin/sips -z "$px" "$px" "$BASE" --out "$ICONSET/$name" >/dev/null
done <<'SIZES'
16   icon_16x16.png
32   icon_16x16@2x.png
32   icon_32x32.png
64   icon_32x32@2x.png
128  icon_128x128.png
256  icon_128x128@2x.png
256  icon_256x256.png
512  icon_256x256@2x.png
512  icon_512x512.png
1024 icon_512x512@2x.png
SIZES

echo "==> Packing"
/usr/bin/iconutil -c icns "$ICONSET" -o "$ROOT/Resources/PrinterStudio.icns"

echo "==> Wrote $ROOT/Resources/PrinterStudio.icns"
ls -l "$ROOT/Resources/PrinterStudio.icns" | awk '{print "    " $5 " bytes"}'
