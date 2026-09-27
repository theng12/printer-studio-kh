#!/bin/bash
#
# Builds "Printer Studio KH.app" using only the Command Line Tools.
#
# Full Xcode is deliberately NOT required: SwiftUI and AppKit both live in the
# CLT SDK, so swiftc can produce a real, launchable .app bundle. SwiftPM is
# avoided because its manifest API is broken in a CLT-only install.
#
#   ./app/build.sh          build into ./dist
#   ./app/build.sh --run    build, then launch
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
DIST="$ROOT/../dist"
APP="$DIST/Printer Studio KH.app"
BIN_NAME="PrinterStudio"

echo "==> Building $BIN_NAME"

# An array, not a string: this project's path contains a space, and an
# unquoted $SOURCES would be word-split into nonsense.
SOURCES=()
while IFS= read -r file; do
  SOURCES+=("$file")
done < <(find "$ROOT/Sources/PrinterStudio" -name '*.swift' | sort)

if [ ${#SOURCES[@]} -eq 0 ]; then
  echo "!! No Swift sources found under $ROOT/Sources/PrinterStudio" >&2
  exit 1
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# -parse-as-library is required for the @main attribute.
# -swift-version 5 keeps us in the non-strict-concurrency language mode.
echo "==> Compiling ${#SOURCES[@]} source files"
/usr/bin/swiftc \
  -O \
  -parse-as-library \
  -swift-version 5 \
  -target arm64-apple-macos15.0 \
  -framework SwiftUI \
  -framework AppKit \
  -o "$APP/Contents/MacOS/$BIN_NAME" \
  "${SOURCES[@]}"

cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Bundle the splix driver payload so the app can install it without needing
# the source checkout to be present.
SPLIX="$ROOT/../vendor/splix"
if [ -x "$SPLIX/bin/rastertoqpdl" ] && [ -f "$SPLIX/ppd/laser10x.ppd" ]; then
  mkdir -p "$APP/Contents/Resources/splix/bin" "$APP/Contents/Resources/splix/ppd"
  cp "$SPLIX/bin/rastertoqpdl" "$APP/Contents/Resources/splix/bin/"
  cp "$SPLIX/ppd/laser10x.ppd" "$APP/Contents/Resources/splix/ppd/"
  echo "==> Bundled splix driver payload"
else
  echo "!! warning: vendor/splix payload missing — the app cannot install the driver" >&2
fi

# The app carries its own instructions, so it can be sent on its own without a
# separate Read Me — see the "Read Me First" item in the menu bar.
cp "$ROOT/Resources/Read Me First.txt" "$APP/Contents/Resources/"
chmod 644 "$APP/Contents/Resources/Read Me First.txt"

# A .dmg is the one file to send by AirDrop or Telegram: it holds the app, the
# Read Me, and an Applications shortcut. Build with --dmg.
if [ "${1:-}" = "--dmg" ] || [ "${2:-}" = "--dmg" ]; then
  DMG="$DIST/Printer Studio KH.dmg"
  STAGE="$(mktemp -d)"
  echo "==> Building $DMG"
  cp -R "$APP" "$STAGE/"
  cp "$ROOT/Resources/Read Me First.txt" "$STAGE/"
  ln -s /Applications "$STAGE/Applications"
  rm -f "$DMG"
  /usr/bin/hdiutil create -quiet -volname "Printer Studio KH" -srcfolder "$STAGE" \
    -ov -format UDZO "$DMG"
  rm -rf "$STAGE"
  echo "==> Built: $DMG"
fi

# Ad-hoc signature: enough for local use, no developer account needed.
if /usr/bin/codesign --force --sign - "$APP" 2>/dev/null; then
  echo "==> Ad-hoc signed"
else
  echo "==> warning: ad-hoc signing failed (the app will still run locally)"
fi

echo "==> Built: $APP"

if [ "${1:-}" = "--run" ]; then
  echo "==> Launching"
  /usr/bin/open "$APP"
fi
