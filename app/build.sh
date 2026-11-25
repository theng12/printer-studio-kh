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
# The app and the installer are written into ./dist on every run. Once that
# installer is installed and verified, app/finalize-dist.sh <receipt> keeps the
# newest two in dist and retires the rest recoverably, so dist never depends on
# anyone remembering to tidy it.
#
set -euo pipefail

# A gate step or launchd shell has no Homebrew in its PATH; pin it, and say what the build ran with.
source "$(dirname "$0")/toolchain.sh"
echo "==> Toolchain: $(python3 --version 2>&1 || echo 'python3 missing'); pkg-config $(command -v pkg-config || echo missing); swiftc $(command -v swiftc || echo missing)"

ROOT="$(cd "$(dirname "$0")" && pwd)"
DIST="$ROOT/../dist"
# Sparkle behind the studio's shim: a static library (nothing to embed), plus the
# framework it loads at run time and the entitlement hardened runtime needs.
SPARKLE="$ROOT/../vendor/khsparkle"
SPARKLE_ENTITLEMENTS="$ROOT/Resources/PrinterStudio.entitlements"
for sym in kh_sparkle_start kh_sparkle_last_error kh_sparkle_set_state_callback; do
  /usr/bin/nm -gU "$SPARKLE/libkhsparkle.a" 2>/dev/null | /usr/bin/grep -q "_$sym\$" \
    || { echo "FAIL: the vendored shim does not export $sym" >&2; exit 1; }
done
APP="$DIST/Printer Studio KH.app"
BIN_NAME="PrinterStudio"
MIN_MACOS="13.0"
# The CLT 27.2 SDK declares SwiftUI's @State as a macro whose plugin
# (SwiftUIMacros) ships only with Xcode, so the default SDK cannot build this
# app on a CLT-only Mac. Pin the newest SDK that can.
# shortcut: SDK 26.5 until the CLT ships the plugin; upgrade when it does.
SDK="$(/usr/bin/xcrun --show-sdk-path --sdk macosx26.5 2>/dev/null || true)"
[ -n "$SDK" ] || SDK="$(/usr/bin/xcrun --show-sdk-path)"
# Published and accepted installers are immutable, even when rebuilding this version.
if [ "${1:-}" = "--dmg" ] || [ "${2:-}" = "--dmg" ]; then
  VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Resources/Info.plist")
  if [ -e "$DIST/$(basename "$APP" .app)-$VERSION.dmg" ]; then
    printf 'Installer already exists for %s; preserve it and use a new release version.\n' "$VERSION" >&2
    exit 1
  fi
fi
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

# The checkout's _trash link points into the owner's Desktop trash, which he can
# empty at any time; a build must not depend on it resolving.
TRASH="$(mktemp -d "${TMPDIR:-/tmp}/printer-build.XXXXXX")"
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
    -sdk "$SDK" \
    -target "${ARCH}-apple-macos${MIN_MACOS}" \
    -framework SwiftUI \
    -framework AppKit \
    -F "$SPARKLE" \
    -framework Sparkle \
    -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
    -o "$SLICES/$BIN_NAME.$ARCH" \
    "${SOURCES[@]}" \
    -Xlinker -force_load -Xlinker "$SPARKLE/libkhsparkle.a"
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

# The update key travels inside the signed bundle. publisher.json is writable by
# the logged-in user, so the key must never be read from there.
PUBLISHER_KEY="$ROOT/Resources/PublisherKey.txt"
if [ ! -s "$PUBLISHER_KEY" ]; then
  echo "FAIL: Resources/PublisherKey.txt is missing or empty — update checks would have no trusted key" >&2
  exit 1
fi
cp "$PUBLISHER_KEY" "$APP/Contents/Resources/PublisherKey.txt"
chmod 644 "$APP/Contents/Resources/PublisherKey.txt"
echo "==> Bundled the update publisher key"

# Spoken announcements. Three clips made with the studio's own local VoxCPM2
# model on Gateway, so an install never needs a network to hear them.
for clip in printing-en printing-zh printing-km; do
  if [ ! -f "$ROOT/Resources/$clip.wav" ]; then
    echo "FAIL: missing announcement clip $clip.wav" >&2
    exit 1
  fi
  cp "$ROOT/Resources/$clip.wav" "$APP/Contents/Resources/$clip.wav"
done
echo "==> Bundled spoken announcements"

# Extract What's New notes for this version from CHANGELOG.md. Refuse if missing or empty.
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
CHANGELOG="$ROOT/../CHANGELOG.md"
"$ROOT/release-notes.sh" "$VERSION" "$CHANGELOG" > "$APP/Contents/Resources/WhatsNew.txt"
chmod 644 "$APP/Contents/Resources/WhatsNew.txt"
echo "==> Bundled What's New for $VERSION"

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

# Sparkle lives in Contents/Frameworks with an @rpath load, signed from the inside out
# before the app: a framework signed after its host breaks the host's seal.
SPARKLE_FW="$APP/Contents/Frameworks/Sparkle.framework"
mkdir -p "$APP/Contents/Frameworks"
ditto "$SPARKLE/Sparkle.framework" "$SPARKLE_FW"
for nested in "Versions/B/XPCServices/Downloader.xpc" "Versions/B/XPCServices/Installer.xpc" \
              "Versions/B/Updater.app" "Versions/B/Autoupdate" "Versions/B" "Versions/Current" "."; do
  /usr/bin/codesign --force --sign "$SIGNING_IDENTITY" --options runtime "$SPARKLE_FW/$nested"
done
echo "==> Bundled Sparkle and signed it from the inside out"

# One helper executable, shipped in two small app bundles so every background
# process shows the app's own name. Both are signed before the app seal.
echo "==> Compiling Printer Studio KH Helper"
for ARCH in arm64 x86_64; do
  /usr/bin/swiftc \
    -O \
    -swift-version 5 \
    -sdk "$SDK" \
    -target "${ARCH}-apple-macos${MIN_MACOS}" \
    -o "$SLICES/helper.$ARCH" \
    "$ROOT/Helper/main.swift"
done
/usr/bin/lipo -create "$SLICES/helper.arm64" "$SLICES/helper.x86_64" -output "$SLICES/helper"
HELPER_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Resources/Info.plist")
HELPER_BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$ROOT/Resources/Info.plist")
for SPEC in "Printer Studio KH Helper|com.theng12.printerstudio.helper" \
            "Printer Studio KH USB Helper|com.theng12.printerstudio.usbhelper"; do
  HELPER_NAME="${SPEC%%|*}"
  HELPER_ID="${SPEC##*|}"
  HELPER_APP="$APP/Contents/Resources/$HELPER_NAME.app"
  /bin/mkdir -p "$HELPER_APP/Contents/MacOS" "$HELPER_APP/Contents/Resources"
  /bin/cp "$SLICES/helper" "$HELPER_APP/Contents/MacOS/$HELPER_NAME"
  cat > "$HELPER_APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$HELPER_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$HELPER_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$HELPER_ID</string>
    <key>CFBundleExecutable</key>
    <string>$HELPER_NAME</string>
    <key>CFBundleIconFile</key>
    <string>PrinterStudio.icns</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$HELPER_VERSION</string>
    <key>CFBundleVersion</key>
    <string>$HELPER_BUILD</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>$MIN_MACOS</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
PLIST
  if [ -f "$ROOT/Resources/PrinterStudio.icns" ]; then
    /bin/cp "$ROOT/Resources/PrinterStudio.icns" "$HELPER_APP/Contents/Resources/"
  fi
  sign_code "$HELPER_APP" "$HELPER_ID"
done
echo "==> Bundled helper apps"

# Nested code has already been signed; seal the app before creating its installer.
/usr/bin/codesign --force --sign "$SIGNING_IDENTITY" --identifier 'com.theng12.printerstudio' \
  --options runtime --entitlements "$SPARKLE_ENTITLEMENTS" "$APP"
/usr/bin/codesign --verify --strict "$APP"
echo "==> Signed with $SIGNING_IDENTITY (hardened runtime, library validation disabled for Sparkle)"

# Prove the whole seal, nested helpers and filters included, before an installer
# is made. --strict alone checks only the top-level code; a build that cannot
# pass this is not one we can offer for an automatic install.
verify_rc=0
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP" || verify_rc=$?
echo "==> codesign --verify --deep --strict: exit $verify_rc"
if [ "$verify_rc" -ne 0 ]; then
  echo "FAIL: the app seal does not verify deeply (exit $verify_rc)" >&2
  exit 1
fi

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
  /usr/bin/hdiutil create -quiet -volname "Printer Studio KH" -srcfolder "$STAGE" \
    -format UDZO "$DMG"
  mv "$STAGE" "$TRASH/dmg-stage"
  sign_code "$DMG" 'com.theng12.printerstudio.installer'
  echo "==> Built: $DMG"
  echo "==> Installer retained; accepted rollback DMGs stay until installed verification."
fi

echo "==> Built: $APP"

if [ "${1:-}" = "--run" ]; then
  echo "==> Launching"
  /usr/bin/open "$APP"
fi
