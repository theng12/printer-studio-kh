//! Samsung QPDL (Quietly-named-but-Public Data Language) encoder.
//!
//! QPDL is the byte format used by Samsung-engine mono lasers, including the
//! HP Laser 100/107/108 family (HP rebadged Samsung's printer division in 2017).
//! It is *not* PCL, *not* PostScript, and *not* documented by HP — this encoder
//! is a Rust port of the open-source `rastertoqpdl.c` filter from the `splix`
//! project (https://github.com/llocoaster/splix), GPLv2.
//!
//! See `Phase 1b` in TASKS for the work-in-progress.

use anyhow::Result;

use crate::raster::MonoPage;
use super::{JobOptions, PrinterEncoder};

pub struct QpdlEncoder;

impl PrinterEncoder for QpdlEncoder {
    fn name(&self) -> &'static str {
        "Samsung QPDL (mono)"
    }

    fn supported_devices(&self) -> &'static [(u16, u16)] {
        &[
            (0x03F0, 0xE82A), // HP Laser 107a
            // Add other HP Laser 1xx / Samsung Xpress mono models here as confirmed.
        ]
    }

    fn encode(&self, pages: &[MonoPage], opts: &JobOptions) -> Result<Vec<u8>> {
        encode_job(pages, opts)
    }
}

mod codec;
mod stream;

pub use codec::encode_job;
