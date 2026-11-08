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

Shared queues use the working 1.0.4-style Bonjour registration:
`<description> (AirPrint)`, `_ipp._tcp,_universal`, port 631, the original
PDF/JPEG/URF format list and `URF=none` marker, plus the queue's stable CUPS UUID.
The bridge omits its copy only when the native service named by CUPS resolves
locally on port 631 with the exact queue and UUID, a usable format and URF field,
and appears in the AirPrint subtype. A plain IPP record, a remote service or an
unconfirmed lookup never hides a legacy label printer. Local DNS-SD lookups have
a two-second limit (`PRINTER_STUDIO_DNSSD_SECONDS` can adjust it); an unavailable
native proof keeps the bridge. A printer advertised by a different Mac or through
multiple independently configured queues can still need separate diagnosis.

The bridge publishes only while macOS Printer Sharing is on. It refreshes when
a saved name or advertised capability changes, reads each queue's own options,
and an installed bridge is refreshed when the app supplies a different script.
It performs no LAN scan or native-record classification.

Jobs travel CUPS → the queue’s own driver → the printer. Version 1.0.9 restored
discovery; the separate label conversion setup is prepared for 1.0.10 below.
**iPhone visibility is not checked until the owner sees the printers on the
phone.** Local Bonjour replies do not establish that result.

Turning on AirPrint also turns on Printer Sharing if needed, using macOS's
administrator approval. A failed or cancelled approval stops setup and explains
why. The advertisement runs as a per-user LaunchAgent at login rather than boot.

For a **TSC TTP-244 Pro or Xprinter XP-D463B using its legacy vendor driver**,
open **Sharing → Set up label printing** once and approve the administrator
request. Updating the app alone does not install these privileged filters.
Existing driver routes for other printers are preserved.

The label route decodes genuine URF with system libcups, writes PDF using
CoreGraphics, then uses macOS's existing PDF-to-raster filter and the original
vendor raster driver. It maps the job's `media-col` dimensions to a valid PPD
PageSize and PageRegion before rendering both PDF and URF. Missing or invalid
sizes fail with an explanation; they do not become a zero-size page.

The decoder supports chunked 1/8-bit grayscale and supported 8-bit RGB layouts.
Unsupported layouts, corrupt or truncated input and failed output writes fail
loudly. A decoded page has a 1 GiB memory limit. Multi-page jobs retain their
pages; the app's test page remains one page.

Offline tests use URF generated by Apple's native encoder and check geometry,
resolution, pixels, orientation, polarity and one-page output. The vendor input
is captured in tests because the proprietary label binaries are unavailable on
the development Mac. **Physical iPhone output is not checked until the owner
prints a label after setup.** The historical job 2244 was not replayed.

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

For KH Updater: `./app/build.sh --dmg` builds the universal app, signs nested
binaries and then the app, verifies each signature, and builds the signed DMG.
Stable bundle ID: `com.theng12.printerstudio`. Prepared version: **1.0.14**, build
**15** (not published). Requires macOS 13+ (Apple Silicon or Intel). Old builds
go into `_trash`; nothing is published by the build.

Packaging defaults to the existing `KH Studio Local Signing` identity in this
Mac's Keychain. `PRINTER_STUDIO_SIGNING_IDENTITY` selects a different certificate
name when needed; an existing certificate identity on the installed app or prior
build is preserved. Missing keys and signing failures stop packaging. No keys
are created, exported or copied, and no trust settings are changed. This local
signature is not an Apple Developer ID or notarization.

After a normal build, `bash app/test-signing.sh` builds a private second version,
checks that the app and bundled binaries keep the same certificate-based designated
requirements, and launches both packaged apps in isolated launchd jobs. It needs
the assigned heavy-job slot. The launch fixture skips preferences, login items,
printer-service setup and print jobs, and removes only its own test jobs.

For every release, bump the version and build in `app/Resources/Info.plist`
and add a matching `## <version> — <date>` section to the root `CHANGELOG.md`.
The sidebar shows the version and opens What's New in its own window. The build
bundles matching notes and fails if they are missing or empty. Check extraction
with `bash app/Tools/test-release-notes.sh`.

## Sending it to another Mac

```bash
./app/build.sh --dmg
```

produces `dist/Printer Studio KH-<version>.dmg` — a single file to AirDrop or Telegram. It
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

If printing fails, open **Settings → Copy error report**, then paste it when
asking Developer for help. It includes the app and macOS versions, whether the
USB printer is seen, the USB helper's status and last result, and recent app
and helper log lines. Unavailable logs are marked as unavailable. Copying the
report needs no administrator password and does not upload anything.


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

## Paper and sticker sizes

Version 1.0.3 includes editable 30 × 40, 50 × 70 and 70 × 100 mm presets,
plus A5 (148 × 210 mm) and A4 (210 × 297 mm), alongside the existing label
presets. The list and generated printer labels show both millimetres and inches
(1 inch = 25.4 mm); editable width and height remain in millimetres. Existing saved sizes and switches are kept when the new presets are
added. Width and height describe the stock's feed orientation.

On each Mac, install the label printer's driver and queue, open **Paper &
Sticker Sizes**, review the enabled sizes and each queue's limits, then use
**Apply to printers**. Administrator approval is needed to change the queue.
The app only adds sizes that fit the driver’s declared bounds; native choices
are kept without adding duplicates. Unknown limits need a suitable driver
before custom sizes can be applied. Reopen the iPhone/iPad print dialog after
applying; size choices can vary with the source app and iOS version.

A4 and A5 are already advertised by the HP Laser queue. The HP Laser 107a's
[manufacturer specifications](https://www.hp.com/ph-en/products/printers/product-details/product-specifications/24494357)
allow custom loose sheets from 76 × 127 to 216 × 356 mm: it cannot directly
feed the three small label formats. For that printer, use laser-compatible
label sheets in a supported sheet size. A thermal label printer needs stock
that matches its width, length and sensing mode; a valid driver size is not
proof of a successful physical print.

The sidebar footer shows the bundle version and a **What's new** link to the
current release notes in Settings. DMG builds use `Printer Studio KH-<version>.dmg`;
after successful signature verification, only the newest two release versions
remain in `dist`. Superseded images are moved into `_trash` for recovery.
