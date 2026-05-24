# Linux VM print bridge — tomorrow's checklist

## Current state (tonight)

- ✅ UTM installed at `/Applications/UTM.app` (Homebrew cask)
- ✅ Alpine 3.20.10 VM `PrintBridge` created and installed to disk
- ✅ Networking: Shared NAT, VM at `192.168.64.2`, reachable from this Mac
- ✅ SSH key auth from this Mac to VM (key in `~/.ssh/id_ed25519`)
- ✅ CUPS 2.4.18, splix 2.0.0, avahi running and enabled at boot
- ✅ CUPS listening on `0.0.0.0:631`, web UI accessible at <http://192.168.64.2:631>
- ✅ Available driver: `samsung/ml2010.ppd` (Samsung ML-2010 SpliX — closest match to
   our HP Laser 107a since it's the same QPDL family and the public reference
   capture we used was from an ML-2010)
- ⏸ **Printer not yet added** — needs USB connection
- ⏸ **Mac mini's own Rust ippeveprinter daemon is still running** — we'll disable
   it tomorrow before bringing up the VM-shared printer, to avoid two Bonjour
   advertisements with the same name

## Tomorrow — step by step

### 1. Plug the HP Laser 107a into this Mac mini via USB. Power it on. Wait for "Ready."

Verify it's on the USB bus:

```bash
./target/release/printer-studio detect-printers
# should show 03f0:e82a HP Laser 107a
```

### 2. Disable the old Rust ippeveprinter daemon (to avoid Bonjour name collision)

```bash
launchctl bootout "gui/$(id -u)/com.printer-studio.daemon" 2>/dev/null
# verify it's stopped:
launchctl print "gui/$(id -u)/com.printer-studio.daemon" 2>&1 | head -1
# should say "Could not find service"
```

If you want it permanently removed (not just stopped):
`./scripts/uninstall.sh`

### 3. Boot the PrintBridge VM

Open UTM. Click ▶ on PrintBridge. Wait ~15 seconds for login prompt.

Don't log in via the UTM console — we'll just SSH from this Mac:

```bash
ssh root@192.168.64.2 'echo ok'
```

### 4. Attach the printer's USB to the VM

In UTM's window for the running VM, click the **USB icon** in the top toolbar
(it's the small connector-shaped icon). A dropdown lists available USB devices
on the host. Click **HP Laser 107a** — it'll move from "available on host" to
"attached to VM."

Verify from the host that macOS no longer sees it (it now belongs to the VM):

```bash
ioreg -p IOUSB -l -w 0 -r -c IOUSBHostDevice | grep "HP Laser 107a"
# should be empty
```

And from inside the VM:

```bash
ssh root@192.168.64.2 'lsusb 2>/dev/null || cat /sys/kernel/debug/usb/devices 2>/dev/null | grep -A2 "Vendor=03f0"'
# should show: 03f0:e82a HP Laser 107a
```

### 5. Add the printer in CUPS

Two options — web UI (easier) or command line (faster).

**Web UI** (recommended on first run):

1. Open <http://192.168.64.2:631> in your browser.
2. Administration → Add Printer.
3. Login: `root` + the password you set during Alpine install.
4. Under "Local Printers" pick **HP Laser 107a (HP Laser 107a)**.
5. Continue → Name: `HPLaser107a` · Description: `HP Laser 107a` · Location: `Home` ·
   **Check "Share This Printer"**.
6. Make: **Samsung** · Model: **Samsung ML-2010, SpliX V. 2.0.0**.
7. Set Default Options (Paper Size: A4 or Letter — your default).
8. Done.

**Command line** (alternative):

```bash
ssh root@192.168.64.2 'lpadmin -p HPLaser107a \
    -E \
    -v usb://HP/Laser%20107a?serial=CNB3P899PY \
    -m samsung/ml2010.ppd \
    -D "HP Laser 107a" \
    -L "Home" \
    -o printer-is-shared=true \
    -o media-default=na_letter_8.5x11in'
```

### 6. Verify Bonjour advertisement

```bash
dns-sd -B _ipp._tcp local
# should show: "HPLaser107a @ printbridge" (or similar)
```

### 7. Print a test page

From the VM:

```bash
ssh root@192.168.64.2 'echo "Test print via PrintBridge" | lp -d HPLaser107a'
```

If paper comes out → success. Go to step 8.

If not → check `ssh root@192.168.64.2 'lpstat -W not-completed -l'` and
`ssh root@192.168.64.2 'tail -50 /var/log/cups/error_log'` for hints.

### 8. From your Mac / iPhone

The printer should auto-appear:

- **macOS**: System Settings → Printers & Scanners → Add → "HPLaser107a @ printbridge"
- **iOS**: any app → Share → Print → printer picker

Add it, print to it. Should work.

## When done testing, deploy to another Mac

If you want the VM to live on a different Mac:

1. In UTM, right-click `PrintBridge` → **Move…** — saves a `.utm` bundle.
2. Copy the bundle to the other Mac.
3. Install UTM there (`brew install --cask utm`).
4. Double-click the `.utm` bundle to add it.
5. On the destination Mac: plug in the printer, boot VM, attach USB, you're done.

## Cleanup on THIS Mac mini when ready to remove

```bash
killall UTM 2>/dev/null
brew uninstall --cask utm 2>/dev/null || rm -rf /Applications/UTM.app
rm -rf ~/Library/Containers/com.utmapp.UTM
rm -rf ~/Library/Group\ Containers/group.com.utmapp.UTM
rm -rf ~/Library/Application\ Scripts/com.utmapp.UTM
rm -f ~/Downloads/printer-bridge-setup/alpine-virt-*.iso
rmdir ~/Downloads/printer-bridge-setup 2>/dev/null
# leave SSH key alone (~/.ssh/id_ed25519) — harmless, useful for other VMs
```

## Notes / known issues

- **Alpine's splix 2.0.0 doesn't have the M2026 special-band-width patch** —
  the encoder may send slightly differently-sized bands than the printer
  expects. ml2010.ppd is our best guess. If printing produces garbage / cut-off
  output, the next step is rebuilding splix from the OpenPrinting fork on
  GitHub which has the M2026 patch. ~30 min rebuild inside the VM.

- **The Mac mini's daily Mac and iPhone may show two "HP Laser 107a" printers**
  during the transition (one from our old ippeveprinter daemon, one from the
  new CUPS share). Disable the daemon as step 2 to avoid confusion.

- **Tonight's snapshot point** — VM is in a known-good state. If anything
  goes wrong tomorrow you can revert by reverting to this state (UTM doesn't
  do snapshots by default, but you can just `cp -R` the .utm bundle now).
