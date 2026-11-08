#!/bin/bash
#
# Builds "Printer Studio KH.app" using only the Command Line Tools.
#
# Full Xcode is deliberately NOT required: SwiftUI and AppKit both live in the
# CLT SDK, so swiftc can produce a real, launchable .app bundle. SwiftPM is
# avoided because its manifest API is broken in a CLT-only install.
#
# Compatibility, so this runs on older Macs too:
#   * deployment target is macOS 13 (Ventura), not 15
#   * the binary is universal — arm64 AND x86_64 — so Intel Macs work
#   * the bundled splix driver is universal for the same reason
#
#   ./app/build.sh          build into ./dist
#   ./app/build.sh --run    build, then launch
#   ./app/build.sh --dmg    also produce a single file to send
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
DIST="$ROOT/../dist"
APP="$DIST/Printer Studio KH.app"
BIN_NAME="PrinterStudio"
MIN_MACOS="13.0"
source "$ROOT/signing.sh"

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

TRASH="$DIST/../_trash/build-$(date +%Y%m%d-%H%M%S)-$$"
mkdir -p "$TRASH"
[ ! -e "$APP" ] || mv "$APP" "$TRASH/"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# -parse-as-library is required for the @main attribute.
# -swift-version 5 keeps us in the non-strict-concurrency language mode.
echo "==> Compiling ${#SOURCES[@]} source files for arm64 and x86_64"
SLICES="$(mktemp -d)"
trap 'mv "$SLICES" "$TRASH/slices"' EXIT

for ARCH in arm64 x86_64; do
  /usr/bin/swiftc \
    -O \
    -parse-as-library \
    -swift-version 5 \
    -target "${ARCH}-apple-macos${MIN_MACOS}" \
    -framework SwiftUI \
    -framework AppKit \
    -o "$SLICES/$BIN_NAME.$ARCH" \
    "${SOURCES[@]}"
done

/usr/bin/lipo -create \
  "$SLICES/$BIN_NAME.arm64" "$SLICES/$BIN_NAME.x86_64" \
  -output "$APP/Contents/MacOS/$BIN_NAME"
echo "==> $(/usr/bin/lipo -info "$APP/Contents/MacOS/$BIN_NAME" | sed 's/.*are: //')"

cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Bundle the splix driver payload so the app can install it without needing
# the source checkout to be present.
SPLIX="$ROOT/../vendor/splix"
if [ -x "$SPLIX/bin/rastertoqpdl" ] && [ -f "$SPLIX/ppd/laser10x.ppd" ]; then
  mkdir -p "$APP/Contents/Resources/splix/bin" "$APP/Contents/Resources/splix/ppd"
  cp "$SPLIX/bin/rastertoqpdl" "$APP/Contents/Resources/splix/bin/"
  sign_code "$APP/Contents/Resources/splix/bin/rastertoqpdl" 'com.theng12.printerstudio.rastertoqpdl'
  cp "$SPLIX/ppd/laser10x.ppd" "$APP/Contents/Resources/splix/ppd/"
  echo "==> Bundled splix driver payload"
else
  echo "!! warning: vendor/splix payload missing — the app cannot install the driver" >&2
fi

# The app carries its own instructions, so it can be sent on its own without a
# separate Read Me — see the "Read Me First" item in the menu bar.
cp "$ROOT/Resources/Read Me First.txt" "$APP/Contents/Resources/"
chmod 644 "$APP/Contents/Resources/Read Me First.txt"

# Extract What's New notes for this version from CHANGELOG.md. Refuse if missing or empty.
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
CHANGELOG="$ROOT/../CHANGELOG.md"
"$ROOT/release-notes.sh" "$VERSION" "$CHANGELOG" > "$APP/Contents/Resources/WhatsNew.txt"
chmod 644 "$APP/Contents/Resources/WhatsNew.txt"
echo "==> Bundled What's New for $VERSION"

# The AirPrint advertisement script, installed by the app for iOS discovery.
cp "$ROOT/Resources/airprint-bridge.sh" "$ROOT/Resources/keep-usb-printer-ready.sh" "$APP/Contents/Resources/"
chmod 755 "$APP/Contents/Resources/airprint-bridge.sh"

# Label-only CUPS filters: use system libcups and CoreGraphics, no new runtime.
LABEL_FILTERS="$APP/Contents/Resources/label-filters"
mkdir -p "$LABEL_FILTERS"
for FILTER in urftopdf label-options; do
  for ARCH in arm64 x86_64; do
    /usr/bin/clang -O2 -Wno-deprecated-declarations -target "${ARCH}-apple-macos${MIN_MACOS}" \
      "$ROOT/Filters/$FILTER.c" -lcups -framework CoreGraphics -framework CoreFoundation -o "$SLICES/$FILTER.$ARCH"
  done
  /usr/bin/lipo -create "$SLICES/$FILTER.arm64" "$SLICES/$FILTER.x86_64" -output "$LABEL_FILTERS/$FILTER"
  sign_code "$LABEL_FILTERS/$FILTER" "com.theng12.printerstudio.$FILTER"
done
cp "$ROOT/Filters/label-filter" "$LABEL_FILTERS/label-filter"
chmod 755 "$LABEL_FILTERS/"*
echo "==> Bundled universal label conversion filters"

# The app icon. Regenerate with ./app/make-icon.sh.
if [ -f "$ROOT/Resources/PrinterStudio.icns" ]; then
  cp "$ROOT/Resources/PrinterStudio.icns" "$APP/Contents/Resources/"
  echo "==> Icon bundled"
else
  echo "!! warning: Resources/PrinterStudio.icns missing — run ./app/make-icon.sh" >&2
fi

# Nested code has already been signed; seal the app before creating its installer.
sign_code "$APP" 'com.theng12.printerstudio'
echo "==> Signed with $SIGNING_IDENTITY"

# A .dmg is the one file to send by AirDrop or Telegram: it holds the app, the
# Read Me, and an Applications shortcut. Build with --dmg.
if [ "${1:-}" = "--dmg" ] || [ "${2:-}" = "--dmg" ]; then
  VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
  APP_NAME="$(basename "$APP" .app)"
  DMG="$DIST/$APP_NAME-$VERSION.dmg"
  STAGE="$(mktemp -d)"
  echo "==> Building $DMG"
  cp -R "$APP" "$STAGE/"
  cp "$ROOT/Resources/Read Me First.txt" "$STAGE/"
  ln -s /Applications "$STAGE/Applications"
  [ ! -e "$DMG" ] || mv "$DMG" "$TRASH/"
  /usr/bin/hdiutil create -quiet -volname "Printer Studio KH" -srcfolder "$STAGE" \
    -ov -format UDZO "$DMG"
  mv "$STAGE" "$TRASH/dmg-stage"
  sign_code "$DMG" 'com.theng12.printerstudio.installer'
  echo "==> Built: $DMG"
  "$ROOT/retain-dmgs.sh" "$DIST" "$APP_NAME"
fi

echo "==> Built: $APP"

if [ "${1:-}" = "--run" ]; then
  echo "==> Launching"
  /usr/bin/open "$APP"
fi
