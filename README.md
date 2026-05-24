# printer-studio

A native macOS print engine that turns USB-tethered legacy printers — starting
with the HP Laser 107a, a rebadged Samsung SL-M2026 with no Mac driver — into
**AirPrint-discoverable network printers** for every device on the LAN.

Architecture (M4 mini as always-on print server):

```
┌──── iPhone, iPad, MacBook ────┐
│  Cmd+P → AirPrint             │  ← Bonjour-discovered as
└─────────────┬─────────────────┘    "HP Laser 107a (Mac mini)"
              │ IPP Everywhere / PWG-Raster
              ▼
┌─── Mac mini (M4) ─────────────────────┐
│  /usr/bin/ippeveprinter (Apple)       │  ← IPP/Bonjour, ships with macOS
│             │                         │
│             │ per-job command         │
│             ▼                         │
│  printer-studio  print-job            │  ← Rust binary
│    ├─ PWG-Raster decoder              │
│    ├─ PrinterEncoder (per-model)      │
│    │   └─ Samsung QPDL  (HP Laser ▒)  │
│    └─ USB transport via nusb          │
│             │                         │
└─────────────┼─────────────────────────┘
              │ USB bulk OUT, EP 0x02
              ▼
       ┌──────────────┐
       │ HP Laser 107a│
       └──────────────┘
```

## Project status

| Phase | Status |
|---|---|
| 0  Validate USB access                                | ✅ done |
| 1a USB transport module                               | ✅ done |
| 1b QPDL encoder (PJL/headers/footers + algo0x11)      | ⚠️  structural parts done; band-encoding awaits real-printer validation |
| 1c PWG-Raster decoder                                 | ✅ done (uncompressed 1-bpp) |
| 1d End-to-end print-job CLI                           | ✅ done (dry-run; transmit gated behind flag) |
| 2  ippeveprinter wrapper + LaunchAgent                | ✅ done; verified via ipptool round-trip |
| 3  SwiftUI menu bar app                               | ⏸  deferred — needs full Xcode (only CLT installed) |
| 4  Multi-model architecture                           | ✅ done — `PrinterEncoder` trait + registry |
| 5  Installer + .app packaging                         | ✅ install/uninstall scripts; .app deferred with #3 |

The single piece holding back a working end-to-end print is the **band encoding
inside the QPDL driver** — see [docs/phase-1b-notes.md](docs/phase-1b-notes.md).
It deliberately needs a real-printer test loop to validate safely; running it
unsupervised risks paper/toner waste or the printer entering an error state.

## Quick start

```bash
# 1. Build
cargo build --release

# 2. Verify the printer is reachable
./target/release/printer-studio probe              # all USB devices
./target/release/printer-studio detect-printers    # devices a registered driver supports
./target/release/printer-studio info               # full identification + endpoint info

# 3. Install the IPP daemon as a LaunchAgent
./scripts/install.sh

# 4. The printer is now advertised on the LAN
dns-sd -B _ipp._tcp local
# You should see: "HP Laser 107a (Mac mini)"

# 5. From your Mac / iPhone / iPad: System Settings → Printers → Add → the new entry appears.
#    Cmd+P from any app submits a job. Currently dry-run: the job is parsed
#    and dumped to ~/Library/Logs/printer-studio/jobs/ but NOT transmitted.
```

## Going live (after Phase 1b is finished)

Once the QPDL band encoder is validated against the physical printer:

```bash
launchctl setenv PRINTER_STUDIO_TRANSMIT 1
./scripts/install.sh    # rebake the plist with the new value
```

Now jobs flow all the way to USB and paper comes out.

## Adding support for another printer model

See [docs/adding-a-new-model.md](docs/adding-a-new-model.md). The short version:

- Same family (another Samsung-engine HP/Samsung model): add the VID:PID to
  `src/encoders/qpdl.rs` `supported_devices()`.
- New family (HP ZjStream, PCL6, ESC/P, etc.): add a new file under
  `src/encoders/`, implement the `PrinterEncoder` trait, register it in
  `src/encoders/mod.rs::registry()`.

## Layout

```
printer-studio-kh/
├── src/
│   ├── main.rs                       CLI entry (clap subcommands)
│   ├── lib.rs                        re-exports
│   ├── usb.rs                        UsbPrinter transport (nusb-based)
│   ├── raster/
│   │   ├── mod.rs                    MonoPage type
│   │   ├── pattern.rs                test-page generator
│   │   └── pwg.rs                    PWG-Raster decoder
│   └── encoders/
│       ├── mod.rs                    PrinterEncoder trait + registry
│       └── qpdl/
│           ├── codec.rs              PJL + page/band wrappers (Phase 1b)
│           └── stream.rs             byte/bit writers
├── scripts/
│   ├── install.sh                    install LaunchAgent + binary
│   ├── uninstall.sh                  remove same
│   ├── printer-studio-ippeveprinter.sh  starts the IPP server
│   ├── printer-studio-print-cmd.sh      per-job dispatch (called by ippeveprinter)
│   ├── com.printer-studio.daemon.plist  reference LaunchAgent (install.sh writes a real one)
│   └── make-test-pwg.py             generate a tiny PWG-Raster file for testing
├── docs/
│   ├── phase-1b-notes.md             how to finish the QPDL encoder safely
│   ├── adding-a-new-model.md         extending to other printer families
│   └── phase-3-menu-bar-app.md       deferred SwiftUI app design
└── Cargo.toml
```

## CLI reference

```
printer-studio probe
    Dump every USB device + descriptors for printer-class ones.

printer-studio info [--vid 0x03F0 --pid 0xE82A]
    Show identification + endpoint info for one device. Confirms which
    registered driver matches it.

printer-studio detect-printers
    Scan the bus for any device a registered driver supports.

printer-studio list-drivers
    Show every PrinterEncoder this build knows about + its VID:PIDs.

printer-studio encode-test-page --out /tmp/out.spl
    Generate the built-in test pattern, encode as QPDL, save to file.
    Currently bails at the band-encoder (Phase 1b).

printer-studio print-job [INPUT] [--dry-run-out PATH] [--i-know-what-im-doing]
    Read PWG-Raster from stdin or INPUT file, parse, encode, optionally
    transmit. This is what ippeveprinter calls per job.

printer-studio send-raw FILE --i-know-what-im-doing
    Lowest-level transmit: send raw bytes from FILE to the printer's
    bulk OUT endpoint. Use only with a known-good QPDL stream.
```

## License

This project is the user's own work. References that informed the byte
layout (splix, foo2zjs) are GPLv2; this Rust port reads but does not
include any source from them.

## Hardware confirmed working

- HP Laser 107a (rebadged Samsung SL-M2026), USB `03F0:E82A`, on macOS 26.4.1
  arm64 (M4 Mac mini).
