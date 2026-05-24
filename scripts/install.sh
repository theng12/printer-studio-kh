#!/bin/sh
# install.sh — set up printer-studio on this Mac.
#
# Installs the binary, scripts, and LaunchAgent so the IPP server runs
# at login and the printer is advertised on the LAN as an AirPrint
# printer.
#
# Idempotent: re-run safely after a `cargo build --release`.

set -eu

REPO_DIR="$(cd "$(dirname "$0")"/.. && pwd)"
INSTALL_DIR="${PRINTER_STUDIO_INSTALL_DIR:-$HOME/Library/Application Support/printer-studio}"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
LAUNCH_AGENT_PLIST="$LAUNCH_AGENTS_DIR/com.printer-studio.daemon.plist"
LABEL="com.printer-studio.daemon"

echo "==> Installing printer-studio"
echo "    Source:      $REPO_DIR"
echo "    Install to:  $INSTALL_DIR"
echo

# 1. Ensure binary is built.
BINARY_SRC="$REPO_DIR/target/release/printer-studio"
if [ ! -x "$BINARY_SRC" ]; then
    echo "Release binary not found at $BINARY_SRC."
    echo "Run \`cargo build --release\` first."
    exit 1
fi

# 2. Copy binary + scripts into the install dir.
mkdir -p "$INSTALL_DIR/scripts"
cp "$BINARY_SRC" "$INSTALL_DIR/printer-studio"
cp "$REPO_DIR/scripts/printer-studio-ippeveprinter.sh" "$INSTALL_DIR/scripts/"
cp "$REPO_DIR/scripts/printer-studio-print-cmd.sh"    "$INSTALL_DIR/scripts/"
chmod +x "$INSTALL_DIR/scripts/"*.sh "$INSTALL_DIR/printer-studio"

# 3. Generate the LaunchAgent plist with the install dir baked in.
mkdir -p "$LAUNCH_AGENTS_DIR"
cat > "$LAUNCH_AGENT_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$INSTALL_DIR/scripts/printer-studio-ippeveprinter.sh</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PRINTER_STUDIO_NAME</key>
        <string>HP Laser 107a (Mac mini)</string>
        <key>PRINTER_STUDIO_MANUFACTURER</key><string>HP</string>
        <key>PRINTER_STUDIO_MODEL</key><string>Laser 107a</string>
        <key>PRINTER_STUDIO_LOCATION</key><string>Home</string>
        <key>PRINTER_STUDIO_PORT</key><string>8631</string>
        <key>PRINTER_STUDIO_DRY_RUN_DIR</key>
        <string>$HOME/Library/Logs/printer-studio/jobs</string>
        <key>PRINTER_STUDIO_TRANSMIT</key><string>0</string>
    </dict>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
    <key>ThrottleInterval</key><integer>5</integer>
    <key>StandardOutPath</key>
    <string>$HOME/Library/Logs/printer-studio/daemon.log</string>
    <key>StandardErrorPath</key>
    <string>$HOME/Library/Logs/printer-studio/daemon.err</string>
</dict>
</plist>
EOF

# 4. Log dir
mkdir -p "$HOME/Library/Logs/printer-studio/jobs"

# 5. (Re)load the agent.
echo "==> Loading LaunchAgent ($LABEL)"
if launchctl print "gui/$(id -u)/$LABEL" >/dev/null 2>&1; then
    launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
fi
launchctl bootstrap "gui/$(id -u)" "$LAUNCH_AGENT_PLIST"
launchctl enable    "gui/$(id -u)/$LABEL"
echo "==> Agent loaded."

cat <<EOF

Done.

Verify with:
  printer-studio detect-printers
  log show --predicate 'process == "ippeveprinter"' --last 1m
  tail -f $HOME/Library/Logs/printer-studio/daemon.err

The printer should now appear in System Settings → Printers (and on iPhone /
iPad AirPrint) as: "HP Laser 107a (Mac mini)".

Currently the daemon is in DRY-RUN mode (PRINTER_STUDIO_TRANSMIT=0) — jobs
are received and parsed but not transmitted to the physical printer. Once
the QPDL encoder is finished (Phase 1b), flip:

  launchctl setenv PRINTER_STUDIO_TRANSMIT 1
  ./scripts/install.sh   # re-run to bake the change into the plist

Uninstall: ./scripts/uninstall.sh
EOF
