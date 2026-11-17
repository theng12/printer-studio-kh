#!/bin/bash
# Checks that reopening the app from its icon brings the window back. Uses a
# throwaway probe app built from the real AppDelegate.swift, so nothing of the
# owner's is launched or changed. On the test Mac a small window appears for a
# few seconds; no click and no pointer is used.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT="$ROOT/../_trash/test-reopen-$(date +%Y%m%d-%H%M%S)-$$"
mkdir -p "$OUT"

# The probe is only meaningful if the real app is wired the same way.
python3 -I - "$ROOT/Sources/PrinterStudio/App.swift" <<'PY'
import sys
source = open(sys.argv[1]).read()
for needed in ['@NSApplicationDelegateAdaptor(AppDelegate.self)',
               '.modifier(ReopenOpensMainWindow(hiddenRun: hiddenRun))']:
    assert needed in source, f'the reopen wiring is missing: {needed}'
print('PASS: the app installs the delegate and its label listens for a reopen')
PY

cat > "$OUT/Probe.swift" <<'SW'
import SwiftUI
import AppKit

@main
struct ProbeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private let hiddenRun = ProcessInfo.processInfo.environment["PROBE_NO_WINDOW"] == "1"

    var body: some Scene {
        MenuBarExtra {
            Text("probe")
        } label: {
            Image(systemName: "printer")
                .modifier(ReopenOpensMainWindow(hiddenRun: hiddenRun))
        }
        Window("Reopen Probe", id: "main") {
            Text("probe").frame(width: 240, height: 120)
        }
    }
}
SW

cat > "$OUT/wincount.swift" <<'SW'
import CoreGraphics
import Foundation

let pid = Int32(CommandLine.arguments[1])!
let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
print(list.filter {
    ($0[kCGWindowOwnerPID as String] as? Int32) == pid
        && (($0[kCGWindowLayer as String] as? Int) ?? -1) == 0
}.count)
SW

APP="$OUT/ReopenProbe.app"
mkdir -p "$APP/Contents/MacOS"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key><string>ReopenProbe</string>
	<key>CFBundleIdentifier</key><string>com.theng12.printerstudio.reopenprobe</string>
	<key>CFBundleName</key><string>ReopenProbe</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>0.0.1</string>
	<key>LSMinimumSystemVersion</key><string>13.0</string>
	<key>LSUIElement</key><true/>
</dict>
</plist>
PLIST
/usr/bin/swiftc -parse-as-library -swift-version 5 \
  "$ROOT/Sources/PrinterStudio/AppDelegate.swift" "$OUT/Probe.swift" \
  -o "$APP/Contents/MacOS/ReopenProbe"
/usr/bin/swiftc -O "$OUT/wincount.swift" -o "$OUT/wincount"
codesign --force --sign - "$APP"

PROBE_NO_WINDOW=1 "$APP/Contents/MacOS/ReopenProbe" >"$OUT/probe.log" 2>&1 &
PID=$!
trap 'kill "$PID" 2>/dev/null || true' EXIT
sleep 1.5
BEFORE="$("$OUT/wincount" "$PID")"
AFTER="$BEFORE"
/usr/bin/open -g "$APP"
for _ in $(seq 1 40); do
  AFTER="$("$OUT/wincount" "$PID")"
  [ "$AFTER" -ge 1 ] && break
  sleep 0.25
done

if [ "$BEFORE" = 0 ] && [ "$AFTER" -ge 1 ]; then
  echo "PASS: reopen from the app icon opened the window ($BEFORE -> $AFTER)"
else
  echo "FAIL: reopen from the app icon did not open a window ($BEFORE -> $AFTER)" >&2
  exit 1
fi
