#!/bin/bash
# Runs the built app hidden for 30 seconds, then proves the bundle seal still
# holds and nothing inside it moved. A file written beside the code gets the app
# SIGKILLed as "code signature invalid" on a later launch, which no source scan
# can see. On the shipping build this is the manual step the gate asks for.
#
#   app/test-bundle-seal.sh ["dist/Printer Studio KH.app"]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="${1:-$ROOT/../dist/Printer Studio KH.app}"
OUT="$(mktemp -d "${TMPDIR:-/tmp}/printer-bundle-seal.XXXXXX")"
mkdir -p "$OUT/support"

snapshot() { find "$APP" -print0 | xargs -0 stat -f '%N %z %m' | sort; }

codesign --verify --deep --strict "$APP"
snapshot > "$OUT/before.txt"

PRINTER_STUDIO_SIGNING_SMOKE="$OUT/receipt.json" \
PRINTER_STUDIO_SUPPORT_DIR="$OUT/support" \
  "$APP/Contents/MacOS/PrinterStudio" >"$OUT/run.log" 2>&1 &
PID=$!
trap 'kill "$PID" 2>/dev/null || true' EXIT
for _ in $(seq 1 200); do [ -s "$OUT/receipt.json" ] && break; sleep 0.1; done
[ -s "$OUT/receipt.json" ] || { echo "FAIL: the app never reported ready" >&2; exit 1; }
echo "ready: $(cat "$OUT/receipt.json")"
sleep 30
kill "$PID" 2>/dev/null || true
wait "$PID" 2>/dev/null || true
trap - EXIT

snapshot > "$OUT/after.txt"
if ! diff -u "$OUT/before.txt" "$OUT/after.txt" > "$OUT/bundle.diff"; then
  echo "FAIL: something inside the bundle changed during the run:" >&2
  cat "$OUT/bundle.diff" >&2
  exit 1
fi
codesign --verify --deep --strict "$APP"
echo "PASS: 30 s run, bundle unchanged, seal still valid"
