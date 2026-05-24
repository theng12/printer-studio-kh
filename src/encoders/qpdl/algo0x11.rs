//! Samsung "algorithm 0x11" compression — dictionary-pointer RLE.
//!
//! Rust port of splix's `src/algo0x11.cpp` (GPLv2, Aurélien Croc 2006-2008).
//! Used by Samsung-engine mono lasers (Samsung ML/SCX/M-series, HP Laser
//! 1xx including HP Laser 107a).
//!
//! ## Wire format
//!
//! ```text
//! [ uncomp_size : u32 LE ]              4 bytes
//! [ ptr_table  : 64 × u16 LE ]         128 bytes
//! [ first uncomp_size bytes verbatim ]
//! [ stream of tokens until input exhausted ]
//! ```
//!
//! Each token is either:
//!
//! - **Literal run** — `len_prefix:u8` followed by `(len_prefix + 1)` raw bytes.
//!   `len_prefix` is in `0..=0x7F` (so up to 128 literal bytes per run).
//!
//! - **Compressed token** — 2 bytes encoding "match (compRange+3) bytes from
//!   `ptr_table[idx]` positions ago":
//!   ```text
//!   byte0 = 0x80 | (compRange & 0x7F)
//!   byte1 = ((compRange >> 1) & 0xC0) | (idx & 0x3F)
//!   ```
//!   `compRange = match_len - 3`, `idx` is one of the 64 dictionary entries.
//!
//! The bit at 0x80 in `byte0` disambiguates compressed from literal runs (a
//! literal-run prefix byte has bit 0x80 clear because lengths cap at 0x7F).
//!
//! ## Dictionary lookup
//!
//! Before compressing, sample the data at `COMPRESS_SAMPLE_RATE`-byte
//! strides and count how often each back-offset `1..=COMPRESS_SAMPLE_RATE`
//! produces a byte match. Take the top `TABLE_PTR_SIZE` offsets as the
//! dictionary, sorted by hit count. Always include offset 1 (covers
//! long runs of the same byte).

const COMPRESS_SAMPLE_RATE: usize = 0x800;
const TABLE_PTR_SIZE: usize = 0x40;
const MAX_UNCOMPRESSED_BYTES: usize = 0x80;
const MAX_COMPRESSED_BYTES: usize = 0x202;
const MIN_COMPRESSED_BYTES: usize = 0x2;
const COMPRESSION_FLAG: u8 = 0x80;

/// Compress a byte buffer using Samsung algorithm 0x11.
///
/// Output is variable-length but always smaller than `input.len() +
/// 4 + TABLE_PTR_SIZE*2 + max_overhead` for typical printer pages
/// (laser pages with large whitespace compress ~10–50x).
pub fn compress(data: &[u8]) -> Vec<u8> {
    let ptr_table = lookup_best_occurs(data);
    encode(data, &ptr_table)
}

/// Scan input at sample strides, tallying matches for each back-offset.
/// Return the top 64 offsets, biggest first (the order matters for the
/// final wire encoding only insofar as smaller indices encode marginally
/// faster, but all 64 are eligible).
fn lookup_best_occurs(data: &[u8]) -> [u16; TABLE_PTR_SIZE] {
    // occurs[i] = (count, offset). offset is the back-distance (1-based:
    // we use `offset + 1` as the actual ptr value to match splix).
    let mut occurs: Vec<(u32, u32)> = (0..COMPRESS_SAMPLE_RATE as u32)
        .map(|i| (0u32, i))
        .collect();

    let mut i = COMPRESS_SAMPLE_RATE;
    while i < data.len() {
        let b = data[i];
        for j in 1..COMPRESS_SAMPLE_RATE {
            if i >= j && data[i - j] == b {
                occurs[j - 1].0 += 1;
            }
        }
        i += COMPRESS_SAMPLE_RATE;
    }

    // Sort by count descending (splix uses qsort with the same comparator).
    occurs.sort_by(|a, b| b.0.cmp(&a.0));

    let mut ptr_array = [0u16; TABLE_PTR_SIZE];
    let mut one_present = false;
    for i in 0..TABLE_PTR_SIZE {
        ptr_array[i] = (occurs[i].1 + 1) as u16;
        if ptr_array[i] == 1 {
            one_present = true;
        }
    }
    // Always include offset 1: covers long runs of the same byte cheaply.
    if !one_present {
        ptr_array[TABLE_PTR_SIZE - 1] = 1;
    }
    ptr_array
}

fn encode(data: &[u8], ptr_table: &[u16; TABLE_PTR_SIZE]) -> Vec<u8> {
    // We can't quite predict output size — for highly-compressible inputs
    // we shrink a lot, for uncompressible inputs we add ~1 byte per
    // 128 bytes overhead. Reserve a generous starting capacity.
    let mut out = Vec::with_capacity(data.len() + 4 + TABLE_PTR_SIZE * 2 + 64);

    // Header: uncomp_size (u32 LE) + 64 × u16 LE pointers.
    // uncomp_size = min(max ptr value, MAX_UNCOMPRESSED_BYTES).
    let mut uncomp_size = ptr_table.iter().copied().max().unwrap_or(0) as usize;
    if uncomp_size > MAX_UNCOMPRESSED_BYTES {
        uncomp_size = MAX_UNCOMPRESSED_BYTES;
    }
    out.extend_from_slice(&(uncomp_size as u32).to_le_bytes());
    for &p in ptr_table {
        out.extend_from_slice(&p.to_le_bytes());
    }

    // First `uncomp_size` bytes go in verbatim.
    let prefix_len = uncomp_size.min(data.len());
    out.extend_from_slice(&data[..prefix_len]);

    // Compression loop.
    let mut r = prefix_len;
    let mut raw_count: usize = 0;
    let mut raw_count_pos: usize = 0;

    loop {
        let remaining = data.len().saturating_sub(r);
        let max_comp_size = remaining.min(MAX_COMPRESSED_BYTES);

        if max_comp_size == 0 {
            // End of input — flush any pending raw-run length.
            if raw_count > 0 {
                out[raw_count_pos] = (raw_count - 1) as u8;
            }
            break;
        }

        if max_comp_size >= 2 {
            // Find the dictionary entry that yields the longest back-reference match.
            let mut best_count = 0usize;
            let mut best_ptr = 0usize;
            for i in 0..TABLE_PTR_SIZE {
                let ptr = ptr_table[i] as usize;
                if ptr > r {
                    continue;
                }
                let r_tmp = r - ptr;
                let mut counter = 0;
                while counter < max_comp_size {
                    if data[r + counter] != data[r_tmp + counter] {
                        break;
                    }
                    counter += 1;
                }
                if counter > best_count {
                    best_count = counter;
                    best_ptr = i;
                }
            }
            if best_count > MIN_COMPRESSED_BYTES {
                r += best_count;
                let comp_range = (best_count - 3) as u16; // 0..=0x1FF since MAX_COMPRESSED_BYTES=0x202
                let b0 = COMPRESSION_FLAG | ((comp_range as u8) & 0x7F);
                let b1 = (((comp_range >> 1) as u8) & 0xC0) | ((best_ptr as u8) & 0x3F);
                out.push(b0);
                out.push(b1);
                if raw_count > 0 {
                    out[raw_count_pos] = (raw_count - 1) as u8;
                    raw_count = 0;
                }
                continue;
            }
        }

        // No good back-reference — emit a raw byte.
        raw_count += 1;
        if raw_count == 1 {
            raw_count_pos = out.len();
            out.push(0); // placeholder for length, patched when run ends
        } else if raw_count == MAX_UNCOMPRESSED_BYTES {
            out[raw_count_pos] = 0x7F;
            raw_count = 0;
        }
        out.push(data[r]);
        r += 1;
    }

    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn header_layout() {
        let data = [0u8; 200];
        let compressed = compress(&data);
        // 4 bytes uncomp_size + 128 bytes ptr_table = 132 byte header
        assert!(compressed.len() >= 132);
        // ptr_table should contain offset 1 (for runs of same byte)
        let mut found_one = false;
        for i in 0..TABLE_PTR_SIZE {
            let off = 4 + i * 2;
            let v = u16::from_le_bytes([compressed[off], compressed[off + 1]]);
            if v == 1 {
                found_one = true;
                break;
            }
        }
        assert!(found_one, "ptr_table must contain offset 1");
    }

    #[test]
    fn empty_input_works() {
        let compressed = compress(&[]);
        // Header only, no body.
        assert_eq!(compressed.len(), 4 + TABLE_PTR_SIZE * 2);
    }

    #[test]
    fn highly_compressible_input_shrinks() {
        // 10 KB of zeros should compress dramatically.
        let data = vec![0u8; 10_000];
        let compressed = compress(&data);
        assert!(
            compressed.len() < data.len() / 2,
            "10k zeros compressed to {} bytes (expected <5000)",
            compressed.len()
        );
    }
}
