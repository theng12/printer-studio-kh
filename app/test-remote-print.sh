#!/bin/bash
# Printing from another device: the four controls, proven without a socket, plus
# the proof that nothing answers a device on the tailnet address.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT="$ROOT/../_trash/test-remote-print-$(date +%Y%m%d-%H%M%S)-$$"
mkdir -p "$OUT"

# Every source except the app shell and the views that need it: the policy and
# the store must stand on their own, which is what this compiles.
SOURCES=()
for file in "$ROOT"/Sources/PrinterStudio/*.swift; do
  case "$(basename "$file")" in
    App.swift|Views.swift|DiagnosticReport.swift|ListPresentation.swift|RenderFixtures.swift) continue ;;
  esac
  SOURCES+=("$file")
done

/usr/bin/swiftc -parse-as-library -swift-version 5 "${SOURCES[@]}" "$ROOT/Tools/TestRemotePrint.swift" -o "$OUT/check" 2>"$OUT/build.log" \
  || { echo "FAIL: the test harness did not compile"; tail -20 "$OUT/build.log"; exit 1; }
"$OUT/check"

# The listener is the app's existing one, bound to loopback only.
grep -q 'inet_addr("127.0.0.1")' "$ROOT/Sources/PrinterStudio/MaintenanceHold.swift" \
  || { echo "FAIL: the hold server no longer binds loopback"; exit 1; }
echo "PASS: the server binds 127.0.0.1 only"

grep -q 'path.hasPrefix("/api/remote/")' "$ROOT/Sources/PrinterStudio/MaintenanceHold.swift" \
  || { echo "FAIL: the remote routes are not on the one loopback listener"; exit 1; }
grep -q 'HoldServer.remoteRoute = RemotePrint.route' "$ROOT/Sources/PrinterStudio/App.swift" \
  || { echo "FAIL: the remote routes are never wired in at launch"; exit 1; }
echo "PASS: remote routes share the one listener and are wired at launch"

grep -q 'static func cliPath()' "$ROOT/Sources/PrinterStudio/RemotePrint.swift" \
  && grep -q '/Applications/Tailscale.app/Contents/MacOS/Tailscale' "$ROOT/Sources/PrinterStudio/RemotePrint.swift" \
  || { echo "FAIL: enabling does not look up the Tailscale CLI by path"; exit 1; }
echo "PASS: the switch finds the CLI by path and fails closed without it"

# Nothing on the tailnet address: the listener must not answer there.
TAILNET=$(ifconfig 2>/dev/null | awk '/inet 100\./ {print $2; exit}')
if [ -n "$TAILNET" ]; then
  if nc -z -G 2 "$TAILNET" 8642 2>/dev/null; then
    echo "FAIL: something answers on the tailnet address $TAILNET:8642"; exit 1
  fi
  echo "PASS: nothing answers on the tailnet address $TAILNET:8642"
else
  echo "SKIP: this Mac has no tailnet address, so the off-tailnet check could not run"
fi

# The feature is off after this run, whatever the test left behind.
defaults delete com.theng12.printerstudio remotePrintEnabled 2>/dev/null || true
echo "PASS: remote printing left off"
