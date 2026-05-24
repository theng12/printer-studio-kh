#!/bin/sh
# printer-studio-ippeveprinter.sh
#
# Launch the IPP Everywhere server that advertises our printer on the LAN
# and routes each job through printer-studio-print-cmd.sh.
#
# Run from the LaunchAgent (see scripts/com.printer-studio.daemon.plist)
# or by hand for testing.

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CMD_SCRIPT="$SCRIPT_DIR/printer-studio-print-cmd.sh"
[ -x "$CMD_SCRIPT" ] || chmod +x "$CMD_SCRIPT"

# Service name shown to clients (Bonjour). Override with PRINTER_STUDIO_NAME.
SERVICE_NAME="${PRINTER_STUDIO_NAME:-HP Laser 107a (Mac mini)}"
MFG="${PRINTER_STUDIO_MANUFACTURER:-HP}"
MODEL="${PRINTER_STUDIO_MODEL:-Laser 107a}"
LOCATION="${PRINTER_STUDIO_LOCATION:-Home}"
PORT="${PRINTER_STUDIO_PORT:-8631}"

# DNS-SD subtypes that AirPrint clients (iOS / iPadOS / macOS) look for.
# `_universal` is THE AirPrint marker — without it, iOS won't show the
# printer and macOS falls back to "Choose a Driver..." in the Add dialog.
# `_print` keeps generic IPP browsers happy.
SUBTYPES="${PRINTER_STUDIO_SUBTYPES:-_print,_universal}"

# AirPrint negotiates PDF first when possible, falls back to PWG-Raster
# or URF (Apple Raster). Accepting all three covers iOS, macOS, and
# generic IPP Everywhere clients.
ACCEPT_FORMATS="${PRINTER_STUDIO_FORMATS:-application/pdf,image/pwg-raster,image/urf,image/jpeg}"

# Output MIME type our `-c` command expects. Everything coming in (PDF, URF,
# JPEG) gets converted by ippeveprinter to PWG-Raster before being handed
# to our Rust binary — which only knows how to decode PWG-Raster today.
OUTPUT_FORMAT="${PRINTER_STUDIO_OUTPUT:-image/pwg-raster}"

# ippeveprinter listens on all interfaces by default. -A enables auth (off here).
exec /usr/bin/ippeveprinter \
    -p "$PORT" \
    -M "$MFG" \
    -m "$MODEL" \
    -l "$LOCATION" \
    -f "$ACCEPT_FORMATS" \
    -F "$OUTPUT_FORMAT" \
    -r "$SUBTYPES" \
    -s "10,0" \
    -c "$CMD_SCRIPT" \
    "$SERVICE_NAME"
