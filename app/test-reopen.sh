#!/bin/bash
# Checks that a reopen from the app icon reaches the app. A throwaway probe app is
# built from the real AppDelegate.swift and launched hidden, so nothing of the
# owner's is started and nothing appears on screen: the probe records that the
# reopen Apple Event arrived, and the source assertion proves that listener opens
# the main window. The window itself is not shown and no click is performed — the
# no-desktop rule ranks above seeing it.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT="$(mktemp -d "${TMPDIR:-/tmp}/printer-reopen.XXXXXX")"
mkdir -p "$OUT"

# The probe is only meaningful if the real app is wired the same way: the delegate
# must answer the reopen and the menu-bar label must install the modifier that opens
# the window, or a passing probe would prove nothing about the shipped app.
python3 -I - "$ROOT/Sources/PrinterStudio/App.swift" "$ROOT/Sources/PrinterStudio/AppDelegate.swift" <<'PY'
import sys
app = open(sys.argv[1]).read()
delegate = open(sys.argv[2]).read()
for needed in ['@NSApplicationDelegateAdaptor(AppDelegate.self)',
               '.modifier(ReopenOpensMainWindow(hiddenRun: hiddenRun))']:
    assert needed in app, f'the reopen wiring is missing from App.swift: {needed}'
for needed in ['applicationShouldHandleReopen',
               'post(name: .printerStudioOpenWindow',
               'openWindow(id: "main")']:
    assert needed in delegate, f'the reopen wiring is missing from AppDelegate.swift: {needed}'
print('PASS: the delegate answers a reopen and the label opens the main window')
PY

cat > "$OUT/Probe.swift" <<'SW'
import SwiftUI
import AppKit

@main
struct ProbeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private let hiddenRun = ProcessInfo.processInfo.environment["PROBE_NO_WINDOW"] == "1"
    private let receipt = ProcessInfo.processInfo.environment["PROBE_RECEIPT"] ?? ""

    var body: some Scene {
        MenuBarExtra {
            Text("probe")
        } label: {
            Image(systemName: "printer")
                .modifier(ReopenOpensMainWindow(hiddenRun: hiddenRun))
                // Records the arrival only; it does not stand in for the real listener,
                // which is installed right above and asserted from source.
                .onReceive(NotificationCenter.default.publisher(for: .printerStudioOpenWindow)) { _ in
                    guard !receipt.isEmpty else { return }
                    try? "pid=\(getpid())\n".write(toFile: receipt, atomically: true, encoding: .utf8)
                }
        }
        Window("Reopen Probe", id: "main") {
            Text("probe").frame(width: 240, height: 120)
        }
    }
}
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
codesign --force --sign - "$APP"

RECEIPT="$OUT/reopen-receipt.txt"
PROBE_NO_WINDOW=1 PROBE_RECEIPT="$RECEIPT" "$APP/Contents/MacOS/ReopenProbe" >"$OUT/probe.log" 2>&1 &
PID=$!
trap 'kill "$PID" 2>/dev/null || true' EXIT
sleep 1.5
[ ! -e "$RECEIPT" ] || { echo "FAIL: a reopen was recorded before any was sent" >&2; exit 1; }

# open -g sends the reopen without bringing anything to the front.
/usr/bin/open -g "$APP"
for _ in $(seq 1 40); do
  [ -e "$RECEIPT" ] && break
  sleep 0.25
done

if [ -e "$RECEIPT" ] && grep -qx "pid=$PID" "$RECEIPT"; then
  echo "PASS: the app icon's reopen reached the app's own delegate and its window listener (no window shown)"
else
  echo "FAIL: the reopen did not reach the app — receipt: $(cat "$RECEIPT" 2>/dev/null || echo none), probe log: $(head -3 "$OUT/probe.log" | tr '\n' ' ')" >&2
  exit 1
fi
