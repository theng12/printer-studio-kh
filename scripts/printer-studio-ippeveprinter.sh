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

# ippeveprinter listens on all interfaces by default. -A enables auth (off here).
# -f restricts accepted input MIME types — pwg-raster covers AirPrint cleanly.
exec /usr/bin/ippeveprinter \
    -p "$PORT" \
    -M "$MFG" \
    -m "$MODEL" \
    -l "$LOCATION" \
    -f "image/pwg-raster,image/urf" \
    -s "10,0" \
    -c "$CMD_SCRIPT" \
    "$SERVICE_NAME"
