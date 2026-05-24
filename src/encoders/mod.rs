pub mod qpdl;

use anyhow::Result;

use crate::raster::MonoPage;

/// Job-level options handed to an encoder.
#[derive(Debug, Clone)]
pub struct JobOptions {
    pub copies: u16,
    pub paper: PaperSize,
    pub duplex: Duplex,
    pub job_name: String,
    pub user_name: String,
}

impl Default for JobOptions {
    fn default() -> Self {
        Self {
            copies: 1,
            paper: PaperSize::Letter,
            duplex: Duplex::None,
            job_name: "printer-studio".to_string(),
            user_name: "user".to_string(),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PaperSize {
    Letter,
    A4,
    Legal,
}

impl PaperSize {
    /// Returns (width_in, height_in) at the requested DPI, rounded to integer pixels.
    pub fn pixels(self, dpi: u32) -> (u32, u32) {
        let (w_in, h_in) = match self {
            PaperSize::Letter => (8.5, 11.0),
            PaperSize::A4 => (8.27, 11.69),
            PaperSize::Legal => (8.5, 14.0),
        };
        ((w_in * dpi as f32) as u32, (h_in * dpi as f32) as u32)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Duplex {
    None,
    LongEdge,
    ShortEdge,
}

/// Per-model raster-to-protocol encoder.
pub trait PrinterEncoder {
    /// Human-readable name of the encoder (e.g. "Samsung QPDL").
    fn name(&self) -> &'static str;

    /// USB VID:PID pairs this encoder claims to support.
    fn supported_devices(&self) -> &'static [(u16, u16)];

    /// Encode a sequence of pages into the printer's native byte stream.
    fn encode(&self, pages: &[MonoPage], opts: &JobOptions) -> Result<Vec<u8>>;
}

/// All encoders the binary knows about. Used by the runtime to match a USB device
/// to a driver.
pub fn registry() -> Vec<Box<dyn PrinterEncoder>> {
    vec![Box::new(qpdl::QpdlEncoder)]
}

pub fn find_encoder_for(vid: u16, pid: u16) -> Option<Box<dyn PrinterEncoder>> {
    for enc in registry() {
        if enc.supported_devices().iter().any(|&(v, p)| v == vid && p == pid) {
            return Some(enc);
        }
    }
    None
}
