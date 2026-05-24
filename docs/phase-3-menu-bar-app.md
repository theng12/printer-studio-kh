# Phase 3 — SwiftUI menu bar app (deferred)

## Why deferred

The Mac mini currently has Xcode Command Line Tools but not the full Xcode
app (only `xcode-select -p` → `/Library/Developer/CommandLineTools`).
SwiftUI menu bar apps with status-bar items, Bonjour service browsing, and
a packaged `.app` bundle realistically need full Xcode. The CLT-only path
is technically possible (`swift build` from a Package.swift) but doesn't
produce a properly-signed `.app` that survives `xattr -cr` cleanly.

**Action when you want this**: install Xcode from the App Store (~10 GB,
free), then this design slots in cleanly on top of the existing CLI engine.

## Design

The CLI engine in this repo already does all the heavy lifting. The
menu bar app is a thin **status / control surface** on top:

```
                 ┌───────────────────────────────┐
                 │  🖨 (menu bar icon)            │
                 └─────────────┬─────────────────┘
                               │ click
                               ▼
   ┌────────────────────────────────────────────┐
   │ printer-studio                             │
   │ ──────────────────────────────────────────│
   │ ✓ HP Laser 107a (Mac mini)     Ready      │
   │   Samsung QPDL  ·  3 pages today           │
   │                                            │
   │ Connected USB Printers (1)                 │
   │   HP Laser 107a    03F0:E82A   Active     │
   │                                            │
   │ Recent Jobs                                │
   │   ✓ test-page.pdf (just now)               │
   │   ⚠ from iPhone (yesterday) — encoder stub │
   │                                            │
   │ ─────────────────────────────────────────  │
   │ ☐ Transmit to printer (currently dry-run)  │
   │ Settings…                                  │
   │ View Logs…                                 │
   │ Quit                                       │
   └────────────────────────────────────────────┘
```

## Implementation outline

- **Project structure**: `Package.swift` Swift package, or new Xcode
  project. SwiftUI + AppKit (for NSStatusItem).
- **State**: a Swift actor that watches the LaunchAgent's stdout/err and
  parses our existing log lines.
- **USB device list**: shell out to `printer-studio detect-printers --json`
  (we'd add a `--json` flag) on a timer or NotificationCenter trigger.
- **Job history**: shell out to `printer-studio list-jobs` (new command
  that reads the job dump dir).
- **Settings**: write to `defaults` / a JSON file, regenerate the
  LaunchAgent plist via `scripts/install.sh`.
- **Transmit toggle**: `launchctl setenv PRINTER_STUDIO_TRANSMIT 1/0`
  plus rewriting the plist. The Swift app should NOT poke USB directly
  — the engine binary owns the hardware.

## Why "thin"

The IPP server and USB transport are best left in the Rust binary
running headless under launchd. The menu bar app is a viewer and
configuration UI for that daemon. This separation:

- Lets the daemon run before login (or while the screen is locked).
- Keeps the Rust code purely tested/portable — Linux works too.
- Avoids re-implementing IPP/USB in Swift.
- Means the user can replace the menu bar UI later (CLI-only, web UI,
  ALSA control panel, whatever) without touching the engine.

## Inter-process protocol

A tiny JSON-over-stdout protocol on top of `printer-studio` subcommands:

```
$ printer-studio status --json
{ "daemon": "running", "uptime": 12345, "ipp_port": 8631,
  "transmit_enabled": false, "jobs_today": 3 }

$ printer-studio detect-printers --json
[ { "vid": "03F0", "pid": "E82A", "name": "HP Laser 107a",
    "serial": "CNB3P899PY", "driver": "Samsung QPDL (mono)" } ]

$ printer-studio list-jobs --json --since 1day
[ { "id": 1, "filename": "1-smoketest.pwg", "time": "...",
    "status": "encoded", "pages": 1, "size": 3100 } ]
```

Adding `--json` to existing subcommands is a half-day's work in Rust.
The menu bar app then just shells out and decodes.

## When to do this

After Phase 1b lands and the daemon is reliably printing for a couple of
weeks. Until then the CLI surface is enough — you can verify status
with `tail -f ~/Library/Logs/printer-studio/daemon.err` and toggle
transmit with `launchctl setenv`.
