pub mod pattern;
pub mod pwg;

/// A monochrome raster page, 1 bit per pixel, packed MSB-first.
///
/// `width` and `height` are in pixels. `dpi` is the resolution at which the
/// page was rasterized (the printer's QPDL header needs to match).
///
/// The data is stored as a flat `Vec<u8>` of length `stride * height`, where
/// `stride = (width + 7) / 8` — i.e. one row per `stride` bytes, with any
/// padding bits at the right edge zero.
#[derive(Debug, Clone)]
pub struct MonoPage {
    pub width_px: u32,
    pub height_px: u32,
    pub dpi: u32,
    pub data: Vec<u8>,
}

impl MonoPage {
    pub fn stride(&self) -> usize {
        ((self.width_px + 7) / 8) as usize
    }

    pub fn blank(width_px: u32, height_px: u32, dpi: u32) -> Self {
        let stride = ((width_px + 7) / 8) as usize;
        Self {
            width_px,
            height_px,
            dpi,
            data: vec![0; stride * height_px as usize],
        }
    }

    /// Set a single pixel to black (1) or white (0). Out-of-bounds is silently ignored.
    pub fn set_pixel(&mut self, x: u32, y: u32, black: bool) {
        if x >= self.width_px || y >= self.height_px {
            return;
        }
        let stride = self.stride();
        let byte = (y as usize) * stride + (x as usize) / 8;
        let bit = 7 - ((x as usize) % 8);
        if black {
            self.data[byte] |= 1 << bit;
        } else {
            self.data[byte] &= !(1 << bit);
        }
    }
}
