# Phase 1b — Byte-diff against an official-driver USB capture

The QPDL encoder is end-to-end functional but the M2026 firmware rejects
the byte stream at some position that shifts depending on input content.
We've exhausted the "guess what the firmware wants" strategy. The
definitive way forward is to compare our output byte-for-byte against a
known-good QPDL stream from HP's official Windows driver.

## What we need

One Wireshark `.pcapng` capture from a Windows PC, printing a simple
one-page document to the HP Laser 107a via USB, with HP's official driver
installed.

See README's "What your friend needs to do" section for the user-friendly
walkthrough.

## Extracting the QPDL bytes from the capture

Once we have `hp-laser-107a-hello.pcapng`:

```bash
# Filter to bulk-OUT URBs to the HP Laser 107a
# (VID 0x03F0, PID 0xE82A, endpoint 0x02 OUT).
# tshark is Wireshark's CLI version.

tshark -r hp-laser-107a-hello.pcapng \
    -Y 'usb.endpoint_address.direction == 0 \
        && usb.endpoint_address.number == 2 \
        && usb.idVendor == 0x03f0 \
        && usb.idProduct == 0xe82a' \
    -T fields -e usb.capdata \
    > usb-out-bytes.hex

# Each line is the hex payload of one bulk-OUT URB. Concatenate:
tr -d '\n:' < usb-out-bytes.hex | xxd -r -p > reference.spl

# `reference.spl` should now be the exact bytes HP's driver sent to the printer.
```

## Doing the byte-diff

Generate our encoder's output for the SAME content. The Wireshark capture
should be printing a single line of text. We'd ideally rasterize that exact
text and feed it through our encoder; for the first cut, even a comparison
of just the PJL header + page header + first band's structural bytes is
enough.

```bash
# Generate our equivalent (best effort — the rasterized image won't match
# exactly, but the STRUCTURE — PJL fields, header fields, band layout —
# should be identical).
./target/release/printer-studio encode-test-page --out ours.spl --paper letter

# Side-by-side hex compare:
xxd reference.spl > reference.hex
xxd ours.spl > ours.hex
diff reference.hex ours.hex | head -80

# Or aligned compare at field offsets:
python3 - <<'EOF'
with open("reference.spl","rb") as f: ref = f.read()
with open("ours.spl","rb")     as f: ours = f.read()
# PJL section comparison: dump until ESC after '@PJL ENTER LANGUAGE = QPDL'
# Then locate page header (3 bytes after, 17 bytes long).
# Compare byte-by-byte and report mismatches.
EOF
```

## What we expect the diff to show

Best-case scenarios (single-fix wins):

- **Missing PJL field**: HP's driver emits some `@PJL SET ...` line we don't.
  Adding the line silences the firmware check. Cosmetic-looking lines like
  `@PJL SET MEDIASOURCE`, `@PJL DEFAULT RESOLUTION`, `@PJL SET CMDSET=SPL2`
  are the most likely candidates.
- **Wrong page-header byte**: e.g., paper-type byte 0x00 vs an actual
  paperType ordinal that the firmware validates against the loaded media.
- **QPDL version 2 vs 3**: We use 3; the M2026 may expect 2.
- **Band-header field difference**: e.g., the "unknown byte 1/2/3" positions
  (which splix treats as always-zero) might actually have meaningful values.

Worst case: the algo0x11 compression itself has subtle Samsung-specific
behavior that splix's 2006-era implementation doesn't capture for newer
M2026 firmware. In that case we'd see large byte-level differences in the
compressed payload — and we'd need to study HP's driver more carefully.

## Verifying the fix

Once a candidate fix is in:

1. Generate `ours-fixed.spl` for the same input.
2. Confirm the bytes that previously diffed now match.
3. ONE supervised real-printer test send — paper should come out cleanly,
   no SPL ERROR diagnostic.

After that, flip `PRINTER_STUDIO_TRANSMIT=1` in the LaunchAgent plist and
the whole AirPrint → PWG-Raster → encoder → USB pipeline becomes live.
