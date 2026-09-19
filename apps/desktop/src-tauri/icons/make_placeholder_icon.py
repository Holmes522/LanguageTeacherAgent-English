"""Generate a minimal valid 32x32 32bpp .ico placeholder for tauri-build.

tauri-build always generates a Windows resource file and requires an .ico, even when
bundling is disabled. This produces a real ICO (BMP-format entry, BGRA + AND mask) so no
image library is needed. Real branding replaces this in T050.
"""

import struct
from pathlib import Path

SIZE = 32
BG = (0x2A, 0x17, 0x0F)  # BGR: dark navy #0F172A
FG = (0xF8, 0xBD, 0x38)  # BGR: sky blue  #38BDF8
MARGIN = 6


def pixel(x: int, y: int) -> tuple[int, int, int]:
    inside = MARGIN <= x < SIZE - MARGIN and MARGIN <= y < SIZE - MARGIN
    return FG if inside else BG


xor = bytearray()
# BITMAPINFOHEADER stores rows bottom-up.
for y in range(SIZE - 1, -1, -1):
    for x in range(SIZE):
        b, g, r = pixel(x, y)
        xor += bytes((b, g, r, 0xFF))

# AND mask: 1 bit per pixel, rows padded to 4 bytes. All zero = fully opaque.
and_mask = bytes(SIZE * 4)

bmp_header = struct.pack(
    "<IiiHHIIiiII",
    40,           # biSize
    SIZE,         # biWidth
    SIZE * 2,     # biHeight (XOR + AND)
    1,            # biPlanes
    32,           # biBitCount
    0,            # biCompression
    len(xor) + len(and_mask),
    0, 0, 0, 0,
)

image = bmp_header + bytes(xor) + and_mask

icondir = struct.pack("<HHH", 0, 1, 1)
entry = struct.pack(
    "<BBBBHHII",
    SIZE,   # bWidth
    SIZE,   # bHeight (0 would mean 256)
    0,      # bColorCount (0 for 32bpp)
    0,      # bReserved
    1,      # wPlanes
    32,     # wBitCount
    len(image),
    6 + 16,
)

out = Path(__file__).resolve().parent
(out / "icon.ico").write_bytes(icondir + entry + image)
print(f"wrote {out / 'icon.ico'} ({len(icondir) + len(entry) + len(image)} bytes)")
