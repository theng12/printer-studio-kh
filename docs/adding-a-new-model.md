# Adding support for a new printer model

`printer-studio` is built around a plugin trait `PrinterEncoder`. Each printer
family (Samsung QPDL, HP ZjStream, Brother PCL, etc.) is one implementor of
this trait. Adding a new model is a localized, ~3-step change.

## Step 1 — Find out what protocol the printer speaks

USB-class 0x07 printers fall into a handful of byte-format families:

| Family | Identifying clue | Notes |
|---|---|---|
| **Samsung SPL / QPDL** | HP Laser 1xx series, Samsung Xpress, older Samsung ML | Reference driver: [splix](https://github.com/OpenPrinting/splix) — already wired in this repo |
| **HP ZjStream / GDI** | HP LaserJet 1018 / 1020 / 1022 | Reference driver: [foo2zjs](https://www.cups.org/) |
| **HP PCL5 / PCL6** | Most HP LaserJet 2xxx and up, HP OfficeJet | Reference driver: HPLIP / cupsHPLIP |
| **Brother PCL** | Brother HL-/MFC- series | Brother's PPDs in CUPS, mostly PCL6 |
| **Zenographics ZJS** | Konica-Minolta, Lexmark consumer | foo2zjs covers these |
| **ESC/P, ESC/P-R** | Epson dot-matrix and inkjet | Native Linux drivers via printer-driver-escpr |

Easiest way to identify: plug the printer in, run `printer-studio probe`, copy
the `USB Product Name` / VID:PID into a web search with "Linux driver" or "CUPS".

If the printer is a Samsung-engine rebadge (very common for HP Laser 1xx), the
existing **QPDL encoder** should already work once Phase 1b is finished — you
may just need to add its VID:PID to the existing encoder's list.

## Step 2 — Add the VID:PID (if same family) OR write a new encoder

### Same family

Edit `src/encoders/qpdl.rs`:

```rust
fn supported_devices(&self) -> &'static [(u16, u16)] {
    &[
        (0x03F0, 0xE82A), // HP Laser 107a
        (0x03F0, 0x????), // HP Laser 108a  ← add the new one here
    ]
}
```

Build, run `printer-studio detect-printers`, you should see it pick up the
new device. Done.

### New family — add a new encoder

1. **Create the encoder file**, e.g. `src/encoders/foo2zjs.rs`:

   ```rust
   use anyhow::Result;
   use crate::raster::MonoPage;
   use super::{JobOptions, PrinterEncoder};

   pub struct Foo2ZjsEncoder;

   impl PrinterEncoder for Foo2ZjsEncoder {
       fn name(&self) -> &'static str {
           "HP ZjStream (mono)"
       }
       fn supported_devices(&self) -> &'static [(u16, u16)] {
           &[
               (0x03F0, 0x1612), // HP LaserJet 1020
               (0x03F0, 0x1F12), // HP LaserJet 1022
           ]
       }
       fn encode(&self, pages: &[MonoPage], opts: &JobOptions) -> Result<Vec<u8>> {
           // ... port from foo2zjs's foo2zjs.c ...
           todo!()
       }
   }
   ```

2. **Register it** in `src/encoders/mod.rs`:

   ```rust
   pub mod foo2zjs;   // new

   pub fn registry() -> Vec<Box<dyn PrinterEncoder>> {
       vec![
           Box::new(qpdl::QpdlEncoder),
           Box::new(foo2zjs::Foo2ZjsEncoder),  // new
       ]
   }
   ```

3. **Port the encoder logic** from the open-source reference driver.

   The shape of every encoder is the same:
   ```
   write_job_header(opts);
   for page in pages {
       write_page_header(page, opts);
       for band in page.bands() {
           write_band(band, compressed);
       }
       write_page_footer(opts);
   }
   write_job_footer();
   ```

   The work is in three pieces:
   - **Wire format** (job/page/band byte headers) — small, mechanical.
   - **Compression algorithm** — biggest piece, varies by family.
   - **Validation** — feed identical input through the reference C driver
     and your Rust port, byte-diff the output. They should match exactly.

## Step 3 — Verify

```bash
cargo build --release
./target/release/printer-studio detect-printers
```

If your new printer shows up with the correct driver name, you're done.

## When in doubt

`printer-studio probe` dumps every USB device and its interface/endpoint
descriptors. That's usually enough to confirm USB-Printer-Class compatibility
and identify the bulk OUT endpoint. The encoder is the only model-specific
piece — everything else (IPP, USB transport, app shell) reuses the existing
machinery.
