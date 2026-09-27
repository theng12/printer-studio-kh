#!/bin/bash
#
# Proves that the driver Printer Studio KH ships emits the band width this
# printer actually requires.
#
# Background: the Samsung M2026 engine in the HP Laser 107a silently discards
# a page whose band width is not exactly one of a fixed set of values taken
# from Samsung's own driver. It reports no error and never feeds paper. The
# splix PPD gates that table behind `*QPDL SpecialBandWidth: True`.
#
# This script runs the same CUPS raster through the shipped filter twice —
# once with the gate, once without — and decodes the band width out of the
# resulting QPDL band headers. Run it after touching the driver or the PPD.
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FILTER="$ROOT/vendor/splix/bin/rastertoqpdl"
PPD="$ROOT/vendor/splix/ppd/laser10x.ppd"
RASTER="$ROOT/vendor/splix/reference/testpage-600.rast"

for file in "$FILTER" "$PPD" "$RASTER"; do
  if [ ! -f "$file" ]; then
    echo "!! Missing: $file" >&2
    exit 1
  fi
done

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# A copy of the PPD with the band-width gate removed.
grep -v 'SpecialBandWidth' "$PPD" > "$TMP/without-gate.ppd"

echo "==> Rendering a test page through the shipped filter"
PPD="$PPD" "$FILTER" 1 verify verify 1 "PageSize=Letter" "$RASTER" > "$TMP/with-gate.qpdl" 2>/dev/null
PPD="$TMP/without-gate.ppd" "$FILTER" 1 verify verify 1 "PageSize=Letter" "$RASTER" > "$TMP/without-gate.qpdl" 2>/dev/null

echo "    with gate: $(wc -c < "$TMP/with-gate.qpdl" | tr -d ' ') bytes"
echo "    no gate:   $(wc -c < "$TMP/without-gate.qpdl" | tr -d ' ') bytes"
echo

/usr/bin/python3 - "$TMP/with-gate.qpdl" "$TMP/without-gate.qpdl" <<'PYTHON'
import sys

# From splix src/qpdl.cpp: a band header is
#   [0]=0x0C signature, [1]=band number, [2..3]=width in BITS (big endian),
#   [4..5]=height in BITS, [6]=compression algorithm.
def band_widths(path):
    data = open(path, "rb").read()
    found = []
    for i in range(len(data) - 7):
        if data[i] != 0x0C:
            continue
        width = (data[i + 2] << 8) | data[i + 3]
        height = (data[i + 4] << 8) | data[i + 5]
        # 128-row bands compressed with algo 0x11 are the M2020/M2026 signature.
        if height == 128 and data[i + 6] == 0x11 and 0 < width <= 8192:
            found.append((i, data[i + 1], width))
    return found

ok = True
for label, path in (("with gate (shipped)", sys.argv[1]), ("without gate", sys.argv[2])):
    bands = band_widths(path)
    if not bands:
        print(f"{label:22} no band headers found")
        ok = False
        continue
    widths = sorted({w for _, _, w in bands})
    rendered = ", ".join(f"{w} bits = {w // 8} bytes" for w in widths)
    print(f"{label:22} {len(bands)} bands, width {rendered}")

with_bands = sorted({w for _, _, w in band_widths(sys.argv[1])})
without_bands = sorted({w for _, _, w in band_widths(sys.argv[2])})

print()
# Letter at 600 dpi must be exactly 640 bytes (5120 bits) per the table.
if with_bands == [5120]:
    print("PASS: the shipped driver emits 640-byte bands — Letter @ 600 dpi.")
else:
    print(f"FAIL: expected 5120 bits (640 bytes), got {with_bands}.")
    ok = False

if with_bands != without_bands:
    print("PASS: removing the gate changes the band width, confirming it is the switch.")
else:
    print("NOTE: the gate made no difference in this run.")
    ok = False

sys.exit(0 if ok else 1)
PYTHON
