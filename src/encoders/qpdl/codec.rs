//! QPDL job stream encoder — Phase 1b is implemented here.
//!
//! Public entry: [`encode_job`].

use anyhow::{Result, bail};

use crate::encoders::JobOptions;
use crate::raster::MonoPage;

/// Encode a full print job (one or more raster pages) into the QPDL byte stream
/// that the HP Laser 107a (and other Samsung-engine mono lasers) expects on
/// its bulk OUT endpoint.
pub fn encode_job(_pages: &[MonoPage], _opts: &JobOptions) -> Result<Vec<u8>> {
    // TODO(Phase 1b): replace this stub with the actual port of
    // splix's rastertoqpdl.c. The shape will be:
    //
    //   1. write_job_header(&mut out, opts)
    //   2. for page in pages: write_page(&mut out, page, opts)
    //   3. write_job_trailer(&mut out)
    //
    // The internals (band compression, page header format, magic bytes) are
    // the work of Phase 1b.
    bail!("QPDL encoder not yet implemented (Phase 1b in progress)")
}
