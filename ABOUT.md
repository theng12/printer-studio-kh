# Printer Studio KH — what it is

Printer Studio KH is a macOS menu-bar app that makes a USB-only legacy printer
usable from phones and computers on the network, and keeps shared printer queues
from silently locking up. It is built to avoid a terminal: install it, click a
button, print from an iPhone.

## What it does

- Sets up an HP Laser 107a (a rebadged Samsung SL-M2026) with a patched splix
  2.0.2 driver, a print queue and AirPrint sharing.
- Handles the four documented failure modes: the firmware's exact band width, the
  300-DPI page header geometry, quarantined driver files and Apple's `ippusbd`
  claiming the USB device.
- Advertises shared queues over Bonjour/AirPrint only while macOS Printer Sharing
  is on, using the queue's stable CUPS UUID; it keeps its bridge when a native
  service cannot be proven locally.
- Keeps shared queues open with `lpadmin -u allow:all`, on demand or through a
  60-second watcher that only changes queues with an actual restriction.
- Adds a label route for TSC TTP-244 Pro and Xprinter XP-D463B printers using
  their legacy vendor drivers, set up once from Sharing → Set up label printing with
  administrator approval.
- Decodes URF jobs with system libcups and renders through existing macOS
  PDF/raster filters; unsupported layouts, corrupt input and missing page sizes fail
  with an explanation.
- Installs an optional boot service that releases only a matching HP Laser 107a
  serial every 15 seconds after restart or USB replug; the menu app starts at login
  by default.
- Does not weaken administrator authentication or change auto-login, FileVault or
  privacy settings.
- Does not claim phone visibility until the owner sees the printers on a phone, or
  physical label output until the owner prints one.

## How it is built

Rust core (`src/`, with `encoders/` and `raster/`), vendored splix driver source
(`vendor/`), app resources and signing information (`app/`), scripts (`scripts/`)
and design notes (`docs/`).

Build and launch the local app with:

    ./app/build.sh --run

## Where it fits

It is a standalone utility for one Mac with a USB printer. It works through CUPS,
Bonjour, a per-user LaunchAgent and an optional LaunchDaemon; it has no Studio Hub,
GatewayKH or job-queue role. Local CUPS printing and USB release work without the
menu app open.

## Current version

1.0.37, from `CFBundleShortVersionString` in `app/Resources/Info.plist`; the newest
`CHANGELOG.md` entry agrees. `Cargo.toml` says 0.1.0, which is the crate version,
not the app release.
