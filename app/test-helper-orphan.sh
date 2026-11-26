#!/bin/bash
#
# The helper must not leave a launchd job behind when the app it ships inside is
# gone. This builds the helper, puts it in a throwaway "app" with a throwaway job
# label, runs it, deletes the app underneath it, and checks it retires the plist
# and exits. Sharing is mocked off so nothing is advertised.
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
ARCH="$(uname -m)"
OUT="$(mktemp -d "${TMPDIR:-/tmp}/test-helper-orphan.XXXXXX")"
mkdir -p "$OUT/tools" "$OUT/home/Library/LaunchAgents" "$OUT/home/Desktop/_trash"
export HOME="$OUT/home"
export PRINTER_STUDIO_TOOL_DIR="$OUT/tools"

printf '#!/bin/bash\nprintf "%%s\\n" "_share_printers=0"\n' > "$OUT/tools/cupsctl"
printf '#!/bin/bash\nexit 0\n' > "$OUT/tools/lpstat"
printf '#!/bin/bash\nexit 0\n' > "$OUT/tools/lpoptions"
chmod +x "$OUT/tools/cupsctl" "$OUT/tools/lpstat" "$OUT/tools/lpoptions"

echo "==> Building the helper"
/usr/bin/swiftc -O -swift-version 5 -target "${ARCH}-apple-macos13.0" \
  -o "$OUT/helper" "$ROOT/Helper/main.swift"

LABEL="com.example.printerstudio.orphantest"

echo "==> Running it inside a throwaway app, then deleting the app"
APP="$OUT/Test App.app"
HELPER="$APP/Contents/Resources/Printer Studio KH Helper.app/Contents/MacOS"
mkdir -p "$HELPER"
cp "$OUT/helper" "$HELPER/Printer Studio KH Helper"
printf '<plist/>' > "$HOME/Library/LaunchAgents/$LABEL.plist"

PRINTER_STUDIO_JOB_LABEL="$LABEL" PRINTER_STUDIO_RESCAN_SECONDS=1 \
  "$HELPER/Printer Studio KH Helper" bridge > "$OUT/run.log" 2>&1 &
PID=$!
sleep 2
rm -rf "$APP"
for _ in 1 2 3 4 5 6 7 8; do
  [ -f "$HOME/Library/LaunchAgents/$LABEL.plist" ] || break
  sleep 1
done
kill "$PID" 2>/dev/null || true
wait "$PID" 2>/dev/null || true

[ ! -f "$HOME/Library/LaunchAgents/$LABEL.plist" ] \
  || { echo "FAIL: the job plist is still in LaunchAgents"; exit 1; }
echo "  ✓ the orphaned plist is gone from LaunchAgents"
grep -q "no longer on this Mac" "$OUT/run.log" \
  || { echo "FAIL: the helper did not say why it stopped"; exit 1; }
echo "  ✓ it says plainly that the app is gone"
find "$HOME/Desktop/_trash" -name "$LABEL.plist" | grep -q . \
  || { echo "FAIL: the plist was not kept recoverably"; exit 1; }
echo "  ✓ the plist is kept in _trash, not deleted"

echo "==> A bundle that still exists keeps its job"
APP2="$OUT/Still Here.app"
HELPER2="$APP2/Contents/Resources/Printer Studio KH Helper.app/Contents/MacOS"
mkdir -p "$HELPER2"
cp "$OUT/helper" "$HELPER2/Printer Studio KH Helper"
printf '<plist/>' > "$HOME/Library/LaunchAgents/$LABEL.plist"
PRINTER_STUDIO_JOB_LABEL="$LABEL" PRINTER_STUDIO_RESCAN_SECONDS=1 \
  "$HELPER2/Printer Studio KH Helper" bridge > "$OUT/run2.log" 2>&1 &
PID2=$!
sleep 3
kill "$PID2" 2>/dev/null || true
wait "$PID2" 2>/dev/null || true
[ -f "$HOME/Library/LaunchAgents/$LABEL.plist" ] \
  || { echo "FAIL: a live app's job was removed"; exit 1; }
echo "  ✓ a live bundle keeps its job"

echo "==> Orphan guard checks passed."
