#!/usr/bin/env python3
"""Generate a minimal valid PWG-Raster file for testing the IPP pipeline.

Output: a single 100×100 px, 1-bit monochrome page with a diagonal line.
Uses no compression (the format our decoder supports).
"""
import struct
import sys

WIDTH = 100
HEIGHT = 100
DPI = 600

# Build the 1796-byte page header (all fields big-endian per PWG-Raster spec).
header = bytearray(1796)


def write_str(off, val, max_len):
    b = val.encode("ascii")[: max_len - 1]
    header[off : off + len(b)] = b


def write_u32(off, val):
    header[off : off + 4] = struct.pack(">I", val)


write_str(0, "PwgRaster", 64)
write_str(64, "white", 64)
write_str(128, "stationery", 64)
write_str(192, "auto", 64)
# 256..271: reserved (16 zero bytes), already zero
write_u32(272, 0)  # CutMedia
write_u32(276, 0)  # Duplex
write_u32(280, DPI)  # HWResolution X
write_u32(284, DPI)  # HWResolution Y
# 288..303: ImagingBoundingBox (4 zero u32s for "full page")
write_u32(304, 0)  # InsertSheet
write_u32(308, 0)  # Jog
write_u32(312, 0)  # LeadingEdge
write_u32(316, 0)  # Margins[0]
write_u32(320, 0)  # Margins[1]
write_u32(324, 0)  # ManualFeed
write_u32(328, 0)  # MediaPosition (auto)
write_u32(332, 75)  # MediaWeight g/m²
write_u32(336, 0)  # MirrorPrint
write_u32(340, 0)  # NegativePrint
write_u32(344, 1)  # NumCopies
write_u32(348, 0)  # Orientation (portrait)
write_u32(352, 0)  # OutputFaceUp
write_u32(356, 0)  # PageSize[0]
write_u32(360, 0)  # PageSize[1]
write_u32(364, 0)  # Separations
write_u32(368, 0)  # TraySwitch
write_u32(372, 0)  # Tumble
write_u32(376, WIDTH)  # cupsWidth (px)
write_u32(380, HEIGHT)  # cupsHeight (px)
write_u32(384, 0)  # cupsMediaType
write_u32(388, 1)  # cupsBitsPerColor
write_u32(392, 1)  # cupsBitsPerPixel
stride = (WIDTH + 7) // 8
write_u32(396, stride)  # cupsBytesPerLine
write_u32(400, 0)  # cupsColorOrder (Chunky)
write_u32(404, 18)  # cupsColorSpace = Black (1-bit, "1=black")
write_u32(408, 1)  # cupsNumColors
# 412..415: cupsBorderlessScalingFactor (float) — leave 0
# 416..423: cupsPageSize floats — leave 0
write_u32(424, 0)  # cupsCompression = 0 (uncompressed)
# ...rest stays zero...

# Page data: diagonal line.
data = bytearray(stride * HEIGHT)
for y in range(HEIGHT):
    x = y  # diagonal
    if 0 <= x < WIDTH:
        byte_idx = y * stride + (x // 8)
        bit_pos = 7 - (x % 8)
        data[byte_idx] |= 1 << bit_pos

out = sys.stdout.buffer
out.write(b"RaS2")  # sync word, big-endian
out.write(bytes(header))
out.write(bytes(data))
