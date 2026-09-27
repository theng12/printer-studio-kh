#!/usr/bin/env python3
"""
Generates a one-page test PDF with a large solid black rectangle.

Why this exists: diagnosing "paper feeds but nothing is printed" needs a page
whose output cannot be misread. Text alone is ambiguous — a faint or partial
render still looks like "something". A big black bar is unambiguous:

    full black bar, correct text   -> printing works
    blank page                     -> nothing is reaching the drum
    bar present but shifted/cut    -> page geometry or band width is wrong
    stripes / partial bar          -> band encoding or decompression problem

Written without any PDF library, because the whole point is to have no
dependencies. CUPS on macOS has no PostScript -> raster filter, so a .ps file
is rejected by a PPD that only declares a raster filter; a PDF is accepted via
Apple's own cgpdftoraster.

Usage:  ./app/Tools/make-test-page.py [output.pdf]
"""

import sys

WIDTH, HEIGHT = 612, 792          # US Letter, points
BAR_X, BAR_Y, BAR_W, BAR_H = 72, 400, 420, 200


def build() -> bytes:
    # Content stream: a filled rectangle, then three lines of text.
    content = (
        f"0 0 0 rg\n"
        f"{BAR_X} {BAR_Y} {BAR_W} {BAR_H} re f\n"
        f"BT /F1 48 Tf 72 700 Td (PRINTER STUDIO) Tj ET\n"
        f"BT /F1 20 Tf 72 660 Td (HP Laser 107a - test page) Tj ET\n"
        f"BT /F1 22 Tf 72 330 Td (Black bar above means printing works) Tj ET\n"
    ).encode("ascii")

    objects = [
        b"<< /Type /Catalog /Pages 2 0 R >>",
        b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        (b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 %d %d] "
         b"/Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>"
         % (WIDTH, HEIGHT)),
        b"<< /Length %d >>\nstream\n" % len(content) + content + b"endstream",
        b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    ]

    out = bytearray(b"%PDF-1.4\n")
    offsets = []
    for number, body in enumerate(objects, start=1):
        offsets.append(len(out))
        out += b"%d 0 obj\n" % number + body + b"\nendobj\n"

    xref_at = len(out)
    out += b"xref\n0 %d\n" % (len(objects) + 1)
    out += b"0000000000 65535 f \n"
    for offset in offsets:
        out += b"%010d 00000 n \n" % offset
    out += (b"trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n"
            % (len(objects) + 1, xref_at))
    return bytes(out)


if __name__ == "__main__":
    path = sys.argv[1] if len(sys.argv) > 1 else "/tmp/pstest.pdf"
    data = build()
    with open(path, "wb") as handle:
        handle.write(data)
    print(f"wrote {path} ({len(data)} bytes)")
