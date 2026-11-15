#!/bin/bash
# Compiles and runs the focused update-hold suite: the pause, the real in-flight count, the
# bounded settle, the release, an abandoned hold expiring, a fresh start opening, the action
# path's gate, and the loopback route over real HTTP. No window, no desktop, no printer.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT="$ROOT/../_trash/test-maintenance-hold-$(date +%Y%m%d-%H%M%S)-$$"
mkdir -p "$OUT"

# The suite would pass with the wiring deleted, so the wiring itself is checked here: every
# action path claims through the gate that refuses in plain words.
python3 -I - "$ROOT/Sources/PrinterStudio/App.swift" <<'PY'
import sys
source = open(sys.argv[1]).read()
for needed in ['MaintenanceHold.shared.claimOrRefuse(message)',
               'MaintenanceHold.shared.claimOrRefuse(label)',
               'MaintenanceHold.shared.claim("Checking the AirPrint bridge…")',
               'MaintenanceHold.shared.register(']:
    assert needed in source, f'the action path lost its claim gate: {needed}'
print('PASS: every action path passes the hold gate')
PY

/usr/bin/swiftc -parse-as-library -swift-version 5 \
  "$ROOT/Sources/PrinterStudio/MaintenanceHold.swift" "$ROOT/Tools/TestMaintenanceHold.swift" \
  -o "$OUT/check"
"$OUT/check"
