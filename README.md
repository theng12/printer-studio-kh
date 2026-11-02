# Printer Studio KH

A macOS menu-bar app that makes a USB-only legacy printer usable from every
device on your network, and keeps shared printers from silently locking up.

Built so that **no terminal is ever required**: install it, click a button,
print from your iPhone.

## Status

**Working** — verified on 2026-09-27, macOS 27, HP Laser 107a.

The printer prints, and it appears on the LAN as a normal AirPrint printer.
Four separate problems had to be solved to get there, all documented in
[docs/root-cause-and-fix.md](docs/root-cause-and-fix.md):

1. **Band width.** The firmware demands exactly one of a fixed set of values,
   taken from Samsung's own driver. A naive width is accepted without error and
   silently produces nothing.
2. **Page header geometry.** It must sit on ULD's 300-DPI grid. Still broken in
   splix 2.0.2 and in master; patched here.
3. **Quarantine.** A driver that arrived by AirDrop or a download inherits
   `com.apple.quarantine`, and Gatekeeper then refuses to run it.
4. **`ippusbd`.** Apple's IPP-over-USB daemon claims the printer, so CUPS's
   `usb` backend cannot open it and the queue sits at "The printer is offline"
   forever. Releasing the device is what makes it work at all.

## What it does

### 1. Sets up the HP Laser 107a
The HP Laser 107a is a rebadged Samsung SL-M2026 with no Apple driver and no
AirPrint. It speaks Samsung's QPDL language over USB. This app installs a real
driver for it, creates the print queue, and shares it — after which the printer
appears to every iPhone, iPad and Mac on the network as a normal AirPrint
printer.

The driver is [splix](https://github.com/OpenPrinting/splix) 2.0.2, built from
source for Apple Silicon. **See [docs/root-cause-and-fix.md](docs/root-cause-and-fix.md)
for why this specific driver and version matter** — it is the whole story of
the project.

### 2. Printer Share Fix

When you share a printer from a Mac, macOS pins a per-printer user ACL onto the
queue. Other Macs then submit as an unmatched user, and the job parks with
**"Job held for authentication"**.

The app keeps every shared queue open with `lpadmin -u allow:all`, either on
demand or continuously via a background watcher that re-checks every 60
seconds. It is idempotent — it only touches a queue when a restriction is
actually present — and discovers printers dynamically, so nothing is
hardcoded. This does not weaken administrator authentication; it only widens
who may submit jobs, and `cupsd.conf` still limits that to the local network.

### 3. AirPrint for iPhone and iPad

macOS Printer Sharing publishes shared queues over Bonjour, but it does **not**
publish the two things iOS AirPrint discovery actually requires:

- the `_universal` service subtype, and
- a `URF=` key in the TXT record.

Without them an iPhone or iPad ignores the printer completely. That is why a
Mac-shared printer never appears in the iOS print dialog — even a printer that
is natively AirPrint-capable, and even though it works perfectly from other
Macs on the same network.

The app publishes a second Bonjour record per shared printer, carrying those
markers and pointing at the same CUPS queue. **Nothing is proxied:** jobs still
travel CUPS → the queue's own driver → the printer. It re-scans every minute, so
printers shared later are picked up without a restart, and it skips queues that
are already AirPrint-capable.

It installs as a per-user LaunchAgent, so it needs **no administrator
password** — publishing a Bonjour service requires no privileges. The trade-off
is that it starts at login rather than at boot.

Two things worth knowing:

- macOS cannot decode URF, the raster format iOS prefers. The advertisement
  therefore lists `application/pdf` in its `pdl`, which iOS can send and macOS
  can convert.
- The fix is at the CUPS level and per-printer, so it covers *every* shared
  queue, not just the 107a.

## Install

```bash
./app/build.sh --run
```

That produces `dist/Printer Studio KH.app` and launches it. Drag it to
`/Applications` if you want to keep it.

It lives in the menu bar. The window opens on first launch; afterwards, click
the printer icon in the menu bar and choose **Open Printer Studio KH**.

To set up the printer: plug the HP Laser 107a into this Mac by USB, switch it
on, open the **HP Laser 107a** tab, and press **Set up the printer**. macOS
will ask for your password once, because installing a print driver needs
administrator rights.

## After a restart

In **Settings**, turn on **Keep the USB printer ready after restarts** once.
macOS asks for administrator approval to install a fixed-purpose background
service. No password is saved. New driver setup installs this service using the
same approval. Existing driver installations need this one-time switch.

The service runs at boot and checks every 15 seconds, including after a USB
replug. It releases only an HP Laser 107a whose serial matches an already
configured USB queue. Other IPP-over-USB devices are left alone. The menu bar
app starts at login by default; its Settings switch can turn that off without
stopping the USB service. AirPrint advertisements and the shared-queue watcher
still start when their user logs in, independently of the app.

No auto-login, FileVault, or privacy setting is changed. Network AirPrint from
this Mac still needs the sharing user to log in. Local CUPS and USB release do
not need the menu bar app open.

The USB switch can turn the service off with administrator approval; its
LaunchDaemon is moved into `/Library/Application Support/PrinterStudio/_trash`.
Errors are in `/var/log/printer-studio-usb.err.log`. A missing printer is not a
successful paper test.

For KH Updater: `./app/build.sh --dmg` builds the universal app, verifies its
ad-hoc signature, then builds and signs the DMG. Stable bundle ID:
`com.theng12.printerstudio`. Version: **1.0.1**, build **2**. Requires macOS 13+
(Apple Silicon or Intel). Old builds go into `_trash`; nothing is published by
the build. The signature is ad-hoc, not an Apple Developer ID or notarization.

For every release, bump the version and build in `app/Resources/Info.plist`
and add a matching `## <version>` section to the root `CHANGELOG.md`. Settings
shows that version and its What's New notes. The build bundles the matching
notes and fails if they are missing or empty. Check extraction with
`bash app/Tools/test-release-notes.sh`.

## Sending it to another Mac

```bash
./app/build.sh --dmg
```

produces `dist/Printer-Studio-KH-1.0.1.dmg` — a single file to AirDrop or Telegram. It
holds the app, an Applications shortcut, and the Read Me.

The app also carries the Read Me inside itself, so sending the app on its own
is enough. Read it from the menu bar under **Read Me First…**.

**The one thing macOS will not let the app do for itself.** An app that
arrives over AirDrop, Telegram or a download is blocked on first launch,
because it is not notarized by Apple — and notarization requires a paid
Developer ID. The recipient has to **right-click the app and choose Open**,
once per Mac. Nothing inside the app can prevent that, because the warning
appears before the app is allowed to run at all.

What the app *does* handle is the consequence, and this part matters more
than it sounds. The driver ships inside the app bundle, so it inherits that
same "downloaded from the internet" flag — and a flagged driver makes
Gatekeeper stall every print job rather than run it, which looks exactly like
printing doing nothing at all. The installer clears the flag with `xattr -c`,
along with setting the ownership, mode and code signature that CUPS requires
of a filter. Without those steps the printer would appear installed and
simply never work.

## Diagnostics

```bash
./app/report.sh && ./dist/printer-studio-report
```

Prints everything the app knows: queues, states, sharing, whether the ACL is
locking a queue, USB devices, driver presence, and the watcher's log.

To confirm the driver emits the byte stream this printer requires:

```bash
./app/verify-bandwidth.sh
```

This is an offline test — no printer and no paper needed. It is the regression
test for the bug that stalled the project for months.

## Layout

```
app/
├── build.sh                    build the .app (Command Line Tools only)
├── report.sh                   build the diagnostic CLI
├── verify-bandwidth.sh         prove the driver's band width is correct
├── Resources/Info.plist
├── Tools/Report.swift          the diagnostic CLI
└── Sources/PrinterStudio/
    ├── App.swift               menu bar entry point + app state
    ├── Views.swift             all screens
    ├── Models.swift            Printer, USBDevice, LogEntry
    ├── Shell.swift             process running, admin escalation
    ├── CUPS.swift              lpstat / lpadmin / ipptool
    ├── ShareFix.swift          the "held for authentication" fix
    ├── Driver.swift            HP Laser 107a detection, USB parsing
    └── DriverInstaller.swift   installs the filter, PPD and queue
vendor/splix/
├── bin/rastertoqpdl            built for arm64, bundled into the app
├── ppd/laser10x.ppd            the correct PPD — SpecialBandWidth: True
└── reference/                  a known-good raster for the regression test
src/                            the original Rust encoder — archived, see below
docs/root-cause-and-fix.md      why the first attempt failed
```

## Requirements

- **macOS 13 (Ventura) or later**, on **Apple Silicon or Intel**.
  The app, the diagnostic tool and the bundled driver are all universal
  binaries (`arm64` + `x86_64`), so an older Intel Mac works.
- Command Line Tools only — **full Xcode is not required**.
- Administrator rights on first setup, to install the print driver.

The macOS 13 floor comes from SwiftUI's `MenuBarExtra` and `Window` scenes.
`defaultLaunchBehavior` — which would keep the window shut until you ask for it
— needs macOS 15, and it cannot be applied conditionally: SwiftUI has no
type-erased `Scene`, and `SceneBuilder` rejects `if #available` (unlike
`ViewBuilder`). So the window opens at launch on every version, rather than
raising the floor to 15 to suppress it.

Anything below macOS 13 would mean dropping `MenuBarExtra` for an AppKit
`NSStatusItem` and `NavigationSplitView` for an `NSSplitView`. That is a real
rewrite of the UI layer, not a flag, so it has not been done speculatively.

## Notes on the build

Two things are unusual here, both deliberate:

- **No SwiftPM.** Its manifest API is broken in a Command Line Tools-only
  install, so `build.sh` drives `swiftc` directly.
- **No `@State`.** SwiftUI's `@State` is a macro, and the macro plugin ships
  only with full Xcode. Every other property wrapper works, so view state lives
  in the observable model instead. If you add a view, do not reach for `@State`.

## The original Rust encoder

`src/` holds the first attempt: a native print engine with a USB transport, a
PWG-Raster decoder, an IPP/AirPrint wrapper and a hand-written QPDL encoder.
Everything works except the encoder's band width, which is what defeated it.
It is kept for reference and is not on the print path. See
[docs/root-cause-and-fix.md](docs/root-cause-and-fix.md).

## Licence

This project is the user's own work. splix is GPLv2 and is used as a separate
binary; its source is not included here. `vendor/splix/bin/rastertoqpdl` is a
build of OpenPrinting/splix and carries that licence.
