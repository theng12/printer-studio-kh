//! Minimal PWG-Raster decoder.
//!
//! PWG-Raster is the wire format that AirPrint / IPP Everywhere clients use
//! to submit jobs. Each file is:
//!
//! ```text
//! +----+----+----+----+
//! | 'R'| 'a'| 'S'| '2' |   <- sync word: "RaS2" (BE) or "2SaR" (LE) or "RaS3"/"3SaR"
//! +----+----+----+----+
//! | per-page record: 1796-byte header + raster data |
//! | per-page record: 1796-byte header + raster data |
//! | ...                                              |
//! +--------------------------------------------------+
//! ```
//!
//! The page header is 1796 bytes of fixed-layout fields. We only extract
//! the handful needed to drive the printer (width, height, dpi, bpp,
//! compression, color space). Compression 0 (uncompressed) is the only
//! mode handled — IPP Everywhere clients are allowed but not required to
//! use the PackBits variants; we ask ippeveprinter to negotiate uncompressed.
//!
//! Reference: PWG 5102.4-2012, "PWG Raster Format".

use std::io::Read;

use anyhow::{Context, Result, bail};

use super::MonoPage;

const HEADER_SIZE: usize = 1796;

/// Read the sync word at the start of a PWG-Raster stream and report
/// whether the byte order is big-endian (the normal case for IPP).
pub fn read_sync_word<R: Read>(r: &mut R) -> Result<bool> {
    let mut sync = [0u8; 4];
    r.read_exact(&mut sync).context("reading PWG sync word")?;
    match &sync {
        b"RaS2" | b"RaS3" => Ok(true),  // big-endian
        b"2SaR" | b"3SaR" => Ok(false), // little-endian
        other => bail!(
            "not a PWG-Raster stream — expected RaS2/RaS3/2SaR/3SaR, got {:?}",
            other
        ),
    }
}

#[derive(Debug, Clone)]
pub struct PageHeader {
    pub width_px: u32,
    pub height_px: u32,
    pub x_dpi: u32,
    pub y_dpi: u32,
    pub bits_per_color: u32,
    pub bits_per_pixel: u32,
    pub bytes_per_line: u32,
    pub color_space: u32,
    pub compression: u32,
    pub num_copies: u32,
}

/// Read one 1796-byte PWG-Raster page header and extract the fields we care
/// about. The header layout is the CUPS-Raster v2/PWG-Raster v1 fixed
/// 1796-byte struct — strings up front, then a long run of u32 fields.
pub fn read_page_header<R: Read>(r: &mut R, big_endian: bool) -> Result<PageHeader> {
    let mut buf = [0u8; HEADER_SIZE];
    r.read_exact(&mut buf).context("reading PWG page header")?;

    let read_u32 = |offset: usize| -> u32 {
        let bytes = [buf[offset], buf[offset + 1], buf[offset + 2], buf[offset + 3]];
        if big_endian {
            u32::from_be_bytes(bytes)
        } else {
            u32::from_le_bytes(bytes)
        }
    };

    // Per CUPS-Raster v3 / PWG-Raster v1 page-header layout (cups_page_header2_s).
    // Offsets verified against real cgpdftoraster|rastertopwg output:
    //   bytes 0..256   = 4 × 64-byte strings (MediaClass, Color, Type, OutputType)
    //   bytes 256..272 = AdvanceDistance/Media + Collate + CutMedia (per CUPS-Raster v3)
    //                    or "reserved" per PWG-Raster v1 (same byte range, zeros).
    //   bytes 272+     = u32 fields, big-endian.
    let hw_res_x = read_u32(276);
    let hw_res_y = read_u32(280);
    let num_copies = read_u32(340);
    let width = read_u32(372);
    let height = read_u32(376);
    let bits_per_color = read_u32(384);
    let bits_per_pixel = read_u32(388);
    let bytes_per_line = read_u32(392);
    let _color_order = read_u32(396);
    let color_space = read_u32(400);
    let compression = read_u32(404);

    Ok(PageHeader {
        width_px: width,
        height_px: height,
        x_dpi: hw_res_x,
        y_dpi: hw_res_y,
        bits_per_color,
        bits_per_pixel,
        bytes_per_line,
        color_space,
        compression,
        num_copies,
    })
}

/// Read one page's raster data into a [`MonoPage`], given its header.
///
/// Only supports `compression = 0` (uncompressed) and 1-bit monochrome
/// (`bits_per_pixel == 1`). The IPP server is configured to negotiate
/// this format with clients.
pub fn read_page_data<R: Read>(r: &mut R, hdr: &PageHeader) -> Result<MonoPage> {
    if hdr.compression != 0 {
        bail!(
            "PWG-Raster compression {} not supported (only uncompressed PackBits=0)",
            hdr.compression
        );
    }
    if hdr.bits_per_pixel != 1 {
        bail!(
            "PWG-Raster bpp={} not supported (only monochrome 1-bit)",
            hdr.bits_per_pixel
        );
    }
    let expected_stride = (hdr.width_px + 7) / 8;
    if hdr.bytes_per_line != expected_stride {
        bail!(
            "PWG-Raster bytes_per_line {} doesn't match width {} (expected stride {})",
            hdr.bytes_per_line,
            hdr.width_px,
            expected_stride
        );
    }

    let n_bytes = (hdr.bytes_per_line as usize) * (hdr.height_px as usize);
    let mut data = vec![0u8; n_bytes];
    r.read_exact(&mut data).context("reading PWG raster body")?;

    // PWG-Raster uses "black is 0, white is 1" for Black color space (18),
    // but "white is 0, black is 1" for sGray (3) and other. The HP Laser
    // wants "black is 1". Match by inverting if the source isn't already.
    //
    // ColorSpace values per PWG 5102.4:
    //   3  = sGray  (white=0, black=255 → bit 1 = white) — invert
    //   18 = Black  (white=0, black=1   → bit 1 = black) — no invert
    let needs_invert = match hdr.color_space {
        18 => false,             // Black 1-bit — already aligned
        3 | 8 | 19 => true,      // sGray / Gray / sRGB — invert to printer's "1=black"
        _ => true,               // assume invert as the safer default
    };
    if needs_invert {
        for b in data.iter_mut() {
            *b = !*b;
        }
    }

    let dpi = hdr.x_dpi; // assume square pixels; encoder accepts non-square via separate y_dpi later

    Ok(MonoPage {
        width_px: hdr.width_px,
        height_px: hdr.height_px,
        dpi,
        data,
    })
}

/// Read every page from a PWG-Raster stream until EOF.
///
/// Note: PWG-Raster has no "end of stream" marker — pages just keep coming
/// until the read returns 0 bytes. This function detects EOF between page
/// records and stops cleanly.
pub fn read_all_pages<R: Read>(r: &mut R) -> Result<Vec<MonoPage>> {
    let big_endian = read_sync_word(r)?;
    let mut pages = Vec::new();
    loop {
        let mut peek = [0u8; 1];
        match r.read(&mut peek) {
            Ok(0) => break, // clean EOF
            Ok(1) => {
                let chain = std::io::Cursor::new(peek).chain(&mut *r);
                let mut chain = chain;
                let header = read_page_header(&mut chain, big_endian)?;
                let page = read_page_data(&mut chain, &header)?;
                pages.push(page);
            }
            Ok(_) => unreachable!(),
            Err(e) => return Err(e).context("reading next page record"),
        }
    }
    Ok(pages)
}
