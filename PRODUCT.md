# Product

<!-- impeccable:product-schema 1 -->

## Platform

ios

macOS-only SwiftUI app (the Apple-native platform bucket). No web view, no Tauri.

## Stack

Swift 5 + SwiftUI + AppKit on macOS 13+, a SwiftPM app bundle. Rust is not used
here; the printer core is Swift plus a bundled splix/CUPS driver. Portfolio rule:
Printer keeps this shell, and only moves when Windows or a major feature forces
it.

## Users

People who own a USB-only legacy printer — here the HP Laser 107a — and want to
print from an iPhone, iPad or Mac. The README's stated bar is that no terminal is
ever required: install, click a button, print. Assumed (confirm): the primary
person is a non-technical Mac owner, and one Mac in the household runs the app
while the others only consume the shared printer.

## Product Purpose

Make a USB-only printer usable from every device on the local network, and keep
already-shared printers from silently locking up. Success is a print that comes
out of the printer from another device without a terminal step, and shared queues
that stay shared without supervision.

## Positioning

It solves the four concrete failure layers of this printer class in one app —
firmware band width, ULD page-header grid, quarantine on AirDropped drivers, and
Apple's `ippusbd` claiming the device — instead of telling the person to pick a
driver or run commands. The bundled, patched splix driver is the mechanism a
neighbouring utility would not have.

## Operating Context

- One Mac has the printer on USB. Setup installs a driver, creates the CUPS
  queue, shares it, and starts an AirPrint advertisement so iOS devices see a
  normal printer.
- Two background helpers keep it working: an AirPrint bridge and a share-fix
  watcher; a root USB helper keeps the device released after restarts when the
  owner enables it.
- The app is a menu-bar app with a window; it also ships a Read Me, an Activity
  log, a diagnostic error report and saved sticker/paper sizes.
- Releases run through the portfolio Updater/Launcher feed; the app checks the
  signed feed and hands off, never installing itself.

## Capabilities and Constraints

- Capabilities: driver/queue setup and repair, sharing, AirPrint advertisement,
  USB release, sticker and paper sizes, activity log, diagnostics.
- Constraints: macOS 13+; universal binary so Intel Macs work; the splix version
  and its patches are load-bearing; the printer must be released from `ippusbd`
  to work at all.
- Undecided (confirm): whether Windows is ever in scope for this app.

## Brand Commitments

The name is "Printer Studio KH". Helper surfaces are named "Printer Studio KH
Helper" / "Printer Studio KH USB Helper" by portfolio rule. The app is free with
every feature unlocked; support is an optional one-time donation through the
shared NOWPayments page. No logo changes.

## Evidence on Hand

- `README.md` and `docs/root-cause-and-fix.md`: the four failure layers and the
  driver story, with the real printer model.
- `CHANGELOG.md`: shipped behaviour per version.
- `docs/tasks/HANDOFF.md`: current migration state.
- Real hardware on this Mac: HP Laser 107a, verified 2026-09-27.

## Product Principles

1. No terminal, ever: every step is a button with a plain-language result.
2. Fix the cause, not the symptom: the four layers are handled in code, and the
   reasons stay documented.
3. Honest state: "not checked" never reads as passed, and a failure says why.
4. Nothing deleted for good: retired scripts, installers and settings stay
   recoverable.
5. The app is free and unlocked; support never nags.

## Accessibility & Inclusion

Native AppKit/SwiftUI controls, keyboard reachability, VoiceOver labels on the
footer and nav, and legible text in every appearance mode (System, Light, Dark). Assumed (confirm): no stricter standard than the macOS defaults.
