//! QPDL job stream encoder.
//!
//! This is a port (in progress) of splix's `rastertoqpdl.cpp` + `qpdl.cpp` +
//! `printer.cpp::sendPJLHeader/Footer` from C++ to Rust.
//!
//! ## Byte layout of a complete QPDL job
//!
//! ```text
//! <PJL HEADER (text, ASCII)>
//!   ESC %-12345X                 // UEL: Universal Exit Language. 9 bytes.
//!   @PJL DEFAULT SERVICEDATE=YYYYMMDD\n
//!   @PJL SET USERNAME="..."\n
//!   @PJL SET JOBNAME="..."\n
//!   @PJL SET DUPLEX=OFF\n
//!   @PJL SET JAMRECOVERY=OFF\n
//!   @PJL SET PAPERTYPE=OFF\n
//!   @PJL SET ALTITUDE=LOW\n
//!   @PJL SET DENSITY=3\n
//!   @PJL SET RET=NORMAL\n
//!   @PJL ENTER LANGUAGE = QPDL\n
//!
//! <DOCUMENT HEADER (binary, 3 bytes)>
//!   00 00 01                     // Per PPD: *General DocHeaderValues: "<0><0><1>"
//!
//! <FOR EACH PAGE>
//!   <PAGE HEADER (binary, 17 bytes)>
//!     00                         // Signature
//!     YY                         // Y resolution / 100  (e.g. 06 for 600 DPI)
//!     CCCC                       // Copies (big-endian u16)
//!     PT                         // Paper type byte (0 for default)
//!     WWWW                       // Printable width in px (big-endian u16)
//!     HHHH                       // Printable height in px (big-endian u16)
//!     PS                         // Paper source (1 = auto)
//!     00                         // Unknown byte 1 (always 0 in ULD)
//!     00                         // Duplex (0 = off)
//!     00                         // Tumble (0 = off)
//!     00                         // Unknown byte 2 (always 0 in ULD)
//!     VV                         // QPDL version (2 or 3 typical for HP Laser 1xx)
//!     00                         // Unknown byte 3 (colorplanes — 0 for mono)
//!     XX                         // X resolution / 100  (e.g. 06 for 600 DPI)
//!
//!   <FOR EACH BAND in the page>     (band = BAND_HEIGHT rows, e.g. 128)
//!     <BAND HEADER (binary, 12 bytes for compression != 0x0D/0x0E)>
//!       0C                       // Signature
//!       NN                       // Band number (0-based)
//!       WWWW                     // Band width in px (big-endian u16)
//!       HHHH                     // Band height in px (big-endian u16)
//!       AA                       // Compression algorithm (0x11 etc.)
//!       SSSSSSSS                 // Data size (compressed bytes + 4-byte signature + 4-byte checksum)
//!     <SUB-HEADER (4 bytes — present for compression 0x11, omitted for 0x0D/0x0E)>
//!       09 AB CD EF              // QPDL "sub-header signature" (also 09|(sub<<4))
//!     <if QPDL subVersion==3: extra 7×4 bytes for state machine>
//!     <DATA>
//!       <... `dataSize` bytes of compressed band data ...>
//!     <CHECKSUM (4 bytes)>
//!       CCCCCCCC                 // Sum of all data bytes (incl. sub-header signature) as u32 BE
//!
//!   <PAGE FOOTER (binary, 3 bytes)>
//!     01 CC CC                   // 01 + copies u16 BE
//!
//! <PJL FOOTER (binary, 10 bytes)>
//!   09 1B %-12345X               // 0x09 + UEL
//! ```
//!
//! Reference: https://github.com/OpenPrinting/splix
//!   - `src/qpdl.cpp::renderPage`
//!   - `src/printer.cpp::sendPJLHeader/Footer`
//!   - `ppd/ml1660.ppd` (close analogue for HP Laser 1xx)
//!
//! ## What's done
//! - PJL header/footer ([`pjl_header`], [`pjl_footer`])
//! - Document header ([`document_header`])
//! - Page header ([`page_header`])
//! - Page footer ([`page_footer`])
//! - Band header structural wrapper ([`band_header`])
//!
//! ## What's NOT done (Phase 1b — needs physical-printer validation)
//! - Compression algorithm 0x11 (Samsung dictionary-pointer RLE)
//!     - Source: splix `src/algo0x11.cpp`, 244 lines
//!     - Requires: byte transposition (`reverseLineColumn`), bit inversion
//!       (`inverseByte`), banding (`splitIntoBands` with band_height = 128)
//! - End-to-end checksum verification against splix's binary output
//! - Confirmation of which QPDL version (2 vs 3) the HP Laser 107a wants
//! - Confirmation that the printer accepts the format (one test page)
//!
//! Until these land, [`encode_job`] returns an explicit error rather than
//! risk a malformed job.

use anyhow::{Result, bail};

use super::stream::BeWriter;
use crate::encoders::{Duplex, JobOptions, PaperSize};
use crate::raster::MonoPage;

const QPDL_VERSION: u8 = 3; // Default version. Per ml1660.ppd. May need to be 2 for HP Laser 107a.
#[allow(dead_code)] // Will be consumed by Phase 1b band writer.
const BAND_HEIGHT: u32 = 128; // Per most Samsung mono PPDs (*QPDL BandSize: "128").

pub fn encode_job(pages: &[MonoPage], opts: &JobOptions) -> Result<Vec<u8>> {
    if pages.is_empty() {
        bail!("encode_job called with zero pages");
    }

    let mut out = Vec::with_capacity(1024 * 1024);
    let mut w = BeWriter::new(&mut out);

    pjl_header(&mut w, opts);
    document_header(&mut w);

    for (page_idx, page) in pages.iter().enumerate() {
        page_header(&mut w, page, opts);

        // Drive band encoding. With compression-algorithm-0x11 still
        // unimplemented, this is the line that aborts the job rather than
        // emitting half-formed bytes.
        let _ = page_idx;
        encode_page_bands(&mut w, page, opts)?;

        page_footer(&mut w, opts);
    }

    pjl_footer(&mut w);

    Ok(out)
}

fn pjl_header(w: &mut BeWriter, opts: &JobOptions) {
    // UEL — Universal Exit Language. Resets the printer to PJL state.
    w.bytes(b"\x1B%-12345X");

    // Identification
    let date = today_yyyymmdd();
    w.bytes(format!("@PJL DEFAULT SERVICEDATE={date}\n").as_bytes());
    w.bytes(format!("@PJL SET USERNAME=\"{}\"\n", opts.user_name).as_bytes());
    w.bytes(format!("@PJL SET JOBNAME=\"{}\"\n", opts.job_name).as_bytes());

    // Defaults known-safe for Samsung mono engines (from ml1660.ppd defaults).
    w.bytes(b"@PJL SET JAMRECOVERY=OFF\n");
    w.bytes(b"@PJL SET PAPERTYPE=OFF\n");
    w.bytes(b"@PJL SET ALTITUDE=LOW\n");
    w.bytes(b"@PJL SET DENSITY=3\n");
    w.bytes(b"@PJL SET RET=NORMAL\n");

    // Duplex
    match opts.duplex {
        Duplex::None => w.bytes(b"@PJL SET DUPLEX=OFF\n"),
        Duplex::LongEdge => {
            w.bytes(b"@PJL SET DUPLEX=ON\n");
            w.bytes(b"@PJL SET BINDING=LONGEDGE\n");
        }
        Duplex::ShortEdge => {
            w.bytes(b"@PJL SET DUPLEX=ON\n");
            w.bytes(b"@PJL SET BINDING=SHORTEDGE\n");
        }
    }

    w.bytes(b"@PJL ENTER LANGUAGE = QPDL\n");
}

fn pjl_footer(w: &mut BeWriter) {
    // 0x09 (tab) + UEL. Exact bytes per ml1660.ppd: *PJL EndPJL: "<09><1B>%-12345X"
    w.bytes(b"\x09\x1B%-12345X");
}

fn document_header(w: &mut BeWriter) {
    // Per ml1660.ppd: *General DocHeaderValues: "<0><0><1>"
    w.bytes(&[0x00, 0x00, 0x01]);
}

fn page_header(w: &mut BeWriter, page: &MonoPage, opts: &JobOptions) {
    let (paper_w, paper_h) = opts.paper.pixels(page.dpi);
    let _ = (paper_w, paper_h); // currently we trust page.{width,height}_px

    let y_res = (page.dpi / 100) as u8;
    let x_res = y_res; // square pixels for the common 600/1200 modes

    w.u8(0x00); // Signature
    w.u8(y_res); // Y resolution / 100
    w.u16(opts.copies); // Number of copies
    w.u8(paper_type_byte(opts.paper)); // Paper type
    w.u16(page.width_px as u16); // Printable width (px)
    w.u16(page.height_px as u16); // Printable height (px)
    w.u8(1); // Paper source = auto
    w.u8(0); // unknownByte1 (always 0 in ULD)
    w.u8(match opts.duplex {
        Duplex::None => 0,
        _ => 1,
    }); // Duplex
    w.u8(0); // Tumble (TODO: for duplex jobs, alternate per page)
    w.u8(0); // unknownByte2 (always 0 in ULD)
    w.u8(QPDL_VERSION); // QPDL version
    w.u8(0); // unknownByte3 / colorplanes (0 for mono)
    w.u8(x_res); // X resolution / 100
}

fn page_footer(w: &mut BeWriter, opts: &JobOptions) {
    w.u8(0x01); // Signature
    w.u16(opts.copies); // Number of copies
}

fn paper_type_byte(paper: PaperSize) -> u8 {
    // Reverse-engineered values would go here; PPD currently encodes paper
    // size as 0 meaning "use the page's printable area". Setting 0 keeps
    // the driver matching whatever the printer's panel/firmware default is.
    let _ = paper;
    0
}

fn today_yyyymmdd() -> String {
    // We don't want to add the `time` or `chrono` crates just for this. PJL's
    // SERVICEDATE field is informational; HP's reference drivers use the
    // system date but the printer never reads it back. Static placeholder.
    "20260524".to_string()
}

/// Encode the bands of a single page.
///
/// Right now this bails out unconditionally — the compression algorithm
/// (`algo0x11`) and the transpose/bit-invert pipeline that feeds it are
/// the missing pieces of Phase 1b. When a real-printer test loop is
/// available, the implementation slots in here.
fn encode_page_bands(_w: &mut BeWriter, _page: &MonoPage, _opts: &JobOptions) -> Result<()> {
    bail!(
        "QPDL band encoding (Phase 1b) is not yet implemented. \n\
         The PJL header, document header, page header, and page footer are all \n\
         ready and validated against splix's reference (ml1660.ppd, qpdl.cpp). \n\
         What's left: port `splix/src/algo0x11.cpp` (244 lines of Samsung \n\
         dictionary-pointer RLE) and the band-data transpose/bit-invert step. \n\
         This requires a real-printer test loop to validate safely — running \n\
         a malformed job risks the printer entering an error state. \n\
         See `docs/phase-1b-notes.md` for the implementation plan."
    )
}

#[allow(dead_code)] // Helper kept ready for the Phase 1b band writer.
fn band_header(w: &mut BeWriter, band_nr: u8, width: u16, height: u16, compression: u8, data_size: u32) {
    w.u8(0x0C); // Signature
    w.u8(band_nr); // Band number
    w.u16(width); // Band width (px)
    w.u16(height); // Band height (px)
    w.u8(compression); // Compression algorithm
    w.u32(data_size); // Data size (incl. sub-header signature + checksum, per spec)
}
