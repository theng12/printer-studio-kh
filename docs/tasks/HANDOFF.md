## Sidebar, appearance and update controls — 2026-11-12 (in the rebuilt 1.0.16)

Footer is one group (Support, version pill, Check for Updates, one status line); Settings → Appearance
is System/Light/Dark with System as the start; Support page with optional donation; Quit in both menus;
sidebar is one surface. Verified by source tests and a hidden build; on-screen checks paused under the
owner screen rule.

# Printer Studio KH handoff

## Background helper naming — 2026-11-12 (released in 1.0.16)

Every installed background job now runs from a named `.app` bundle. The launchd labels are unchanged, so migration only replaces each job's program.

| Surface | Before | After |
|---|---|---|
| Activity Monitor | `bash` (`airprint-bridge.sh`, `keep-shared-queues-open.sh`, `keep-usb-printer-ready.sh`) plus one `dns-sd` child per shared queue | `Printer Studio KH Helper` (bridge and sharefix); `Printer Studio KH USB Helper` (root USB daemon) |
| Login Items & Extensions → Allow in the Background | `Unknown Developer`, executable `/bin/bash` | Attributed to `com.theng12.printerstudio.helper` (user jobs) or `com.theng12.printerstudio.usbhelper` (USB daemon), executable inside the helper bundle via `AssociatedBundleIdentifiers` |
| BTM row (`sfltool dumpbtm`) | Parent Identifier `Unknown Developer`; Executable Path `/bin/bash` | Parent Identifier `com.theng12.printerstudio.helper` / `com.theng12.printerstudio.usbhelper`; Executable Path inside `Printer Studio KH Helper.app` / `Printer Studio KH USB Helper.app` |
| launchd label | `com.theng12.printerstudio.airprint`, `.sharefix`, `.usb` | unchanged |
| Login item | `com.theng12.printerstudio.app` → `/usr/bin/open` | unchanged |

Migration: AirPrint and ShareFix rewrite their agents at app launch (no admin prompt), copy the user helper into `~/Library/Application Support/PrinterStudio/` and retire the old shell scripts to `_trash/`. A booted-out job is given time to unload before it is restarted, so an upgrade never leaves the AirPrint helper off. The USB daemon needs the existing one-time admin prompt, so its old-style install reports as needing setup and migrates on the next enable. The native Bonjour API replaces the persistent `dns-sd -R` children; transient lookups still use `dns-sd`.

## Release state — 1.0.20 (2026-11-14)

- Product source for 1.0.20 is the release commit that bumps `CFBundleShortVersionString` to
  **1.0.20** / build **21**. It contains `cb34f18` (one combined helper agent, SMAppService login
  item, measured neutral ramp) and the Fleet UI list standard.
- Release record: `/Users/you/Developer/_orchestra/printer-lead/release-120-20261114/` —
  `PLAN.md`, `ACCEPTANCE.md`, `COMPLETENESS.md`, `CRITIC-120.md`, `gate-120.log`,
  `pages/` and `window/` renders, `installed-readback-120.json`, `served-readback-120.json`.
- Page acceptance is offscreen (`app/render-pages.sh`): every page at 375/768/1440 and the window
  at 860/1024/1440, light and dark, with geometry and a corrected alpha-chain contrast probe.
- Still unproven in this record: SMAppService at a real login and the Login Items row (needs a
  logout/reboot), iPhone discovery, a real paper label, and live clicks in the shipped app.
- 1.0.19 remains the installed version on the development Mac until an idle-Mac install of 1.0.20.

## Release state — 2026-11-09

- Product source: `e510375e29f9447836dc1049ecb822d20cff2cf6`, merged and pushed to main.
- Published version: **1.0.14**, build **15**. Primary 1301, legacy, ATLAS, NOVA and UGREEN are verified; **1.0.13** is retained as fallback.
- Final main-built DMG SHA-256: `7d8f7cfe99777e163b61823a2fcb9ca359e24d1aae8722851548cb400b4829ab`, **1,660,371 bytes**.
- This development Mac is installed at **1.0.14/build 15**. All five signed code paths match the main-built app; certificate requirements match the retained installed 1.0.13 rollback. Installed launch health and the enabled bridge refresh passed.
- **Needs owner, through Developer:** confirm one iPhone printer entry with the correct name/label and print a label on the correct stock. The intended iMac/iPhone result is not verified; the duplicate request remains open.

## Proof and retained work

- Full native gate exited **0** on the exact product commit. The main rebuild reused that unchanged regression result and passed fresh artifact/signature/launch checks.
- macOS denied an additional read-only DMG mount. The final proof verifies the exact sealed staging bundle supplied to image creation, its version/build/bridge/notes, plus the signed image checksum. Do not describe this as a mounted-image label readback.
- Local proof: `_orchestra/printer-lead/release-114-gate-20261109/`, including `gate-verified.json`, `main-artifact.json`, `installed-readback.json` and the retirement receipt. Publication proof: `_orchestra/updater-lead/printer-114-publication-20261109/developer-confirmed-readback.json`.
- Owner files: `~/Desktop/All YouTube Stuff/Apps/Printer Studio KH/Release 1.0.14 2026-11-09/`.
- The clean, merged ATLAS test worktree was retired recoverably to `/Volumes/KH-STUDIO-ATLAS/KH-Worktrees/_trash/printer-studio-kh-gate-1.0.14-20261109`. Old build paths in historical receipts refer to this retired copy; no process or linked session used it at retirement.
- Shared `testctl` Printer lanes still target the archived Rust implementation. Developer owns migration to native change-aware lanes. This release ran the established native gate; do not claim the old Cargo lanes prove the macOS app.
