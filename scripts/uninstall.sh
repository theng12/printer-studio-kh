#!/bin/sh
# uninstall.sh — remove printer-studio LaunchAgent and installed files.
#
# Does not delete logs (~/Library/Logs/printer-studio/) — those are
# preserved in case you want to review past job dumps.

set -eu

INSTALL_DIR="${PRINTER_STUDIO_INSTALL_DIR:-$HOME/Library/Application Support/printer-studio}"
LAUNCH_AGENT_PLIST="$HOME/Library/LaunchAgents/com.printer-studio.daemon.plist"
LABEL="com.printer-studio.daemon"

echo "==> Unloading LaunchAgent ($LABEL)"
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true

echo "==> Removing files"
rm -f "$LAUNCH_AGENT_PLIST"
rm -rf "$INSTALL_DIR"

echo "Done. Logs preserved at: $HOME/Library/Logs/printer-studio/"
