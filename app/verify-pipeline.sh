#!/bin/bash
#
# End-to-end check of the whole print path, short of the USB cable:
#
#   a real PDF  ->  CUPS's own rasteriser (cgpdftoraster)  ->  the shipped
#   splix driver  ->  printer-ready QPDL / SPL2
#
# This is the closest thing to a real print job that can be done without a
# printer attached. It exercises CUPS's actual filter, not a synthetic raster,
# so it would catch a PPD that CUPS cannot parse, a resolution the driver does
# not handle, or a document type that breaks the chain.
#
# Run:  ./app/verify-pipeline.sh [some.pdf]
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PPD="$ROOT/vendor/splix/ppd/laser10x.ppd"
FILTER="$ROOT/vendor/splix/bin/rastertoqpdl"
INPUT="${1:-/usr/share/cups/ipptool/document-letter.pdf}"

for file in "$PPD" "$FILTER" "$INPUT"; do
  if [ ! -f "$file" ]; then
    echo "!! Missing: $file" >&2
    exit 1
  fi
done

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# A PPD's *cupsFilter line is whitespace-separated, so the filter must sit at a
# path containing no spaces. (The real install sidesteps this by putting the
# filter in CUPS's own directory and referencing it by bare name.)
mkdir -p "$WORK/bin"
cp "$FILTER" "$WORK/bin/"
sed "s|application/vnd.cups-raster 0 rastertoqpdl|application/vnd.cups-raster 0 $WORK/bin/rastertoqpdl|" \
  "$PPD" > "$WORK/test.ppd"

echo "==> Input: $(basename "$INPUT")"
echo "==> Stage 1: PDF -> CUPS raster, via CUPS's own cgpdftoraster"
/usr/sbin/cupsfilter -p "$WORK/test.ppd" -m application/vnd.cups-raster \
  "$INPUT" > "$WORK/page.rast" 2>"$WORK/raster.log" || {
    echo "!! CUPS could not rasterise the document:" >&2
    grep -E "^ERROR" "$WORK/raster.log" >&2 || true
    exit 1
  }
echo "    $(wc -c < "$WORK/page.rast" | tr -d ' ') bytes of CUPS raster"

echo "==> Stage 2: CUPS raster -> QPDL, via the shipped splix driver"
PPD="$PPD" "$FILTER" 1 verify doc 1 "PageSize=Letter" \
  "$WORK/page.rast" > "$WORK/page.qpdl" 2>"$WORK/qpdl.log" || {
    echo "!! The driver rejected the raster:" >&2
    tail -5 "$WORK/qpdl.log" >&2
    exit 1
  }
echo "    $(wc -c < "$WORK/page.qpdl" | tr -d ' ') bytes of QPDL"
echo

/usr/bin/python3 - "$WORK/page.qpdl" <<'PYTHON'
import sys

data = open(sys.argv[1], "rb").read()
ok = True

def check(label, passed, detail):
    global ok
    print(("PASS: " if passed else "FAIL: ") + label + (f" — {detail}" if detail else ""))
    if not passed:
        ok = False

check("output is a QPDL job", data[:2] == b"\x1b%", "PJL UEL header present")

marker = b"@PJL ENTER LANGUAGE = QPDL\n"
index = data.find(marker)
check("declares QPDL", index >= 0, f"marker at offset {index}")

if index >= 0:
    header = data[index + len(marker):][:17]
    width = (header[5] << 8) | header[6]
    height = (header[7] << 8) | header[8]
    check(
        "page header on the 300-DPI grid",
        (width, height) == (2550, 3300),
        f"{width} x {height} (expected 2550 x 3300 for US Letter)",
    )

# Walk the band headers: [0]=0x0C, [1]=band no, [2..3]=width in bits (BE),
# [4..5]=height in bits, [6]=compression.
bands = []
for i in range(len(data) - 7):
    if data[i] != 0x0C:
        continue
    w = (data[i + 2] << 8) | data[i + 3]
    h = (data[i + 4] << 8) | data[i + 5]
    if h == 128 and data[i + 6] == 0x11 and 0 < w <= 8192:
        bands.append(w)

check("bands emitted", len(bands) > 0, f"{len(bands)} bands of 128 rows")
widths = sorted(set(bands))
check(
    "every band is 640 bytes",
    widths == [5120],
    ", ".join(f"{w} bits = {w // 8} bytes" for w in widths) or "none",
)

sys.exit(0 if ok else 1)
PYTHON
