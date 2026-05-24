# Phase 1b — QPDL Band Encoding (in progress)

The structural QPDL byte stream (PJL header, document header, page header,
page footer, PJL footer) is implemented and matches splix's reference output.
What remains is the band-data path: the actual page bitmap, compressed with
a Samsung-recognized algorithm and wrapped in the QPDL band frame.

This document is the implementation plan. It is intentionally precise enough
that the encoder can be finished in a single supervised session with the
HP Laser 107a powered on and ready to print a test page.

## Why we stopped here

The compression algorithm is ~244 lines of intricate pointer-table RLE
(splix's `src/algo0x11.cpp`). It's portable, but not testable in isolation:
the only way to confirm a QPDL stream is byte-correct is to feed it to a
real printer. A malformed stream can:

- Put the printer in an error state requiring a power-cycle.
- Cause a paper jam during partial decode.
- Waste toner with garbled output.

We chose not to attempt the port without a test loop.

## What needs to happen, step by step

### 1. Confirm QPDL version for HP Laser 107a

splix's `ml1660.ppd` declares `*QPDL QPDLVersion: "3"`. The HP Laser 107a
shares the Samsung Xpress M2026/M2020 engine. Likely values: **2 or 3**.

The encoder currently hardcodes `QPDL_VERSION = 3` in
`src/encoders/qpdl/codec.rs`. If the first test prints garbage or errors,
flip to 2 and retry.

How to confirm definitively: run `strings` on the foo2qpdl binary from
`printer-driver-foo2zjs` (Debian) and look for `QPDLVersion` references,
or inspect any USB capture from the HP Windows driver.

### 2. Implement the band data pipeline

Pseudocode for one page:

```text
band_height = 128
n_bands = ceil(page.height_px / band_height)

for band_nr in 0..n_bands:
    band_rows  = page.rows[band_nr*128 .. (band_nr+1)*128]  # last band may be short
    band_w     = page.width_px
    band_h     = band_rows.len()
    band_bytes = pack_rows_msb(band_rows)   # already done — this is MonoPage's stride layout

    # Algorithm 0x11 expects:
    # 1. Transposition: rows ↔ columns (`reverseLineColumn() = true`)
    # 2. Byte inversion: each byte is bit-reversed (`inverseByte() = true`)
    transposed = transpose_bitmap(band_bytes, band_w, band_h)
    inverted   = transposed.iter().map(|b| b.reverse_bits()).collect()

    compressed = algo0x11_compress(&inverted)
    checksum   = compressed.iter().map(|b| b as u32).sum::<u32>()
                 + 0x39 + 0xAB + 0xCD + 0xEF      # sub-header sig contribution

    # Build the per-band byte stream:
    band_header(0x0C, band_nr, band_w, band_h, compression=0x11, data_size=...)
    sub_header_signature(0x09, 0xAB, 0xCD, 0xEF)   # little-endian for Samsung
    # For QPDL v3 sub-version 3: extra 7×4 bytes for state machine
    # (see splix qpdl.cpp lines 233–293 — first band, middle band, last band markers)
    write(compressed)
    write(checksum as u32 BE)
```

### 3. Port `algo0x11_compress`

`src/algo0x11.cpp` lines 80–180. The algorithm:

1. **Sample step:** scan the data in `COMPRESS_SAMPLE_RATE = 0x800` strides,
   counting which back-offsets produce byte matches.
2. **Build dictionary:** sort offsets by match count, take the top
   `TABLE_PTR_SIZE = 0x40` as the pointer table.
3. **Header:** emit 4-byte u32 LE of `uncompressed_prefix_len`, then 64×2 bytes
   of pointer values (u16 LE).
4. **Uncompressed prefix:** copy `uncompressed_prefix_len` source bytes verbatim.
5. **Compression loop:** at each position, search the pointer table for the
   longest matching back-reference. If `match_len > MIN_COMPRESSED_BYTES (2)`,
   emit a 2-byte compressed token:
   - `out[w]   = 0x80 | (len-3) & 0x7F`
   - `out[w+1] = ((len-3) >> 1) & 0xC0 | (ptr_idx & 0x3F)`
6. **Raw run:** otherwise, accumulate raw bytes (up to `MAX_UNCOMPRESSED_BYTES = 0x80`),
   prefixed with a length byte.

Translation should be largely mechanical. Keep buffer indices as `usize`,
guard against the `outputSize` overflow path that splix handles.

### 4. Validate against splix's binary output (offline)

Before any USB write:

1. Build splix on Linux or in a UTM Linux VM. (Splix's Makefile is ancient
   but works with `make` on Debian/Ubuntu.)
2. Use `pdftoraster` (CUPS) to convert a known PDF (`docs/test-pattern.pdf`)
   to CUPS-Raster.
3. Feed it through `splix/src/rastertoqpdl` to produce a reference QPDL
   stream.
4. Run our Rust `encode-test-page` with the same input.
5. Byte-diff the two outputs. They should be identical (modulo the
   SERVICEDATE field).

If they match, we're done.

### 5. Single supervised real-printer test

With the user present, paper loaded, toner verified:

```bash
printer-studio encode-test-page --out /tmp/test.spl
printer-studio send-raw /tmp/test.spl --i-know-what-im-doing
```

Watch the printer. If a page comes out and looks like the test pattern,
Phase 1b is done.

## Fallback if 0x11 doesn't work

The HP Laser 107a *may* also accept compression `0x0D` (raw RLE, 474 lines)
or `0x0E` (scan-line RLE, 327 lines). If `0x11` fails after careful porting,
try `0x0E` next — it's simpler to debug because each scan-line is independent.

## References

- splix source: <https://github.com/OpenPrinting/splix>
- Closest PPD analogue: `ppd/ml1660.ppd` (Samsung ML-1660)
- Community confirmation: HP Laser 107a is a rebranded Samsung SL-M2026 and
  accepts QPDL/SPL2 streams when given the CLP-310 or M2010/M2020 PPD on
  Linux via `foo2qpdl`. See <https://www.pierov.org/2023/07/25/hp-laser-107a-linux/>.
