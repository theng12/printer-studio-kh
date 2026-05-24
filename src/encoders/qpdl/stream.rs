//! Small byte/bit-writing helpers used by the QPDL encoder.
#![allow(dead_code)] // members used by Phase 1b encoder still in progress

/// Big-endian byte writer that appends to an owned buffer.
pub struct BeWriter<'a> {
    buf: &'a mut Vec<u8>,
}

impl<'a> BeWriter<'a> {
    pub fn new(buf: &'a mut Vec<u8>) -> Self {
        BeWriter { buf }
    }

    pub fn u8(&mut self, v: u8) {
        self.buf.push(v);
    }

    pub fn u16(&mut self, v: u16) {
        self.buf.extend_from_slice(&v.to_be_bytes());
    }

    pub fn u32(&mut self, v: u32) {
        self.buf.extend_from_slice(&v.to_be_bytes());
    }

    pub fn bytes(&mut self, v: &[u8]) {
        self.buf.extend_from_slice(v);
    }

    pub fn zeros(&mut self, n: usize) {
        self.buf.extend(std::iter::repeat(0u8).take(n));
    }

    pub fn position(&self) -> usize {
        self.buf.len()
    }

    /// Overwrite a previously-reserved 4 bytes with a big-endian u32. Used to
    /// patch length fields after the data has been written.
    pub fn patch_u32_be(&mut self, offset: usize, v: u32) {
        let bytes = v.to_be_bytes();
        self.buf[offset..offset + 4].copy_from_slice(&bytes);
    }
}
