#!/usr/bin/env python3
"""Render the MacMonitor iconset using only Python's standard library.

Each size is rendered independently with signed-distance antialiasing, keeping
the waveform crisp at Dock and Finder sizes without image-processing packages.
Usage: make-icon.py <output.iconset>
"""
import math
import os
import struct
import sys
import zlib

SIZES = {
    "icon_16x16.png": 16,
    "icon_16x16@2x.png": 32,
    "icon_32x32.png": 32,
    "icon_32x32@2x.png": 64,
    "icon_128x128.png": 128,
    "icon_128x128@2x.png": 256,
    "icon_256x256.png": 256,
    "icon_256x256@2x.png": 512,
    "icon_512x512.png": 512,
    "icon_512x512@2x.png": 1024,
}

# Coordinates use the full canvas; PNG rows run from top to bottom.
SHAPES = (
    ((0.060, 0.065, 0.940, 0.945, 0.195), (200, 213, 220)),
    ((0.068, 0.073, 0.932, 0.937, 0.188), (241, 246, 248)),
    ((0.458, 0.670, 0.542, 0.807, 0.014), (99, 121, 133)),
    ((0.352, 0.790, 0.648, 0.827, 0.018), (64, 83, 94)),
    ((0.172, 0.218, 0.828, 0.716, 0.055), (148, 169, 180)),
    ((0.187, 0.233, 0.813, 0.701, 0.044), (29, 39, 45)),
    ((0.245, 0.620, 0.380, 0.645, 0.0125), (80, 159, 231)),
    ((0.412, 0.620, 0.568, 0.645, 0.0125), (57, 202, 174)),
    ((0.600, 0.620, 0.755, 0.645, 0.0125), (237, 180, 76)),
)
WAVE = ((0.243, 0.465), (0.320, 0.465), (0.379, 0.380),
        (0.462, 0.555), (0.552, 0.337), (0.628, 0.465), (0.757, 0.465))
WAVE_COLOR = (70, 218, 190)


def sd_rrect(px, py, x0, y0, x1, y1, radius):
    dx = abs(px - (x0 + x1) * 0.5) - ((x1 - x0) * 0.5 - radius)
    dy = abs(py - (y0 + y1) * 0.5) - ((y1 - y0) * 0.5 - radius)
    return math.hypot(max(dx, 0), max(dy, 0)) + min(max(dx, dy), 0) - radius


def sd_segment(px, py, a, b):
    dx, dy = b[0] - a[0], b[1] - a[1]
    t = max(0, min(1, ((px - a[0]) * dx + (py - a[1]) * dy) / (dx * dx + dy * dy)))
    return math.hypot(px - a[0] - t * dx, py - a[1] - t * dy)


def coverage(distance, size):
    return max(0.0, min(1.0, 0.5 - distance * size))


def render(size):
    rows = []
    wave_segments = tuple(zip(WAVE, WAVE[1:]))
    for y in range(size):
        py = (y + 0.5) / size
        row = bytearray(size * 4)
        for x in range(size):
            px = (x + 0.5) / size
            alpha = coverage(sd_rrect(px, py, *SHAPES[0][0]), size)
            if alpha <= 0:
                continue
            rgb = list(SHAPES[0][1])
            for shape, color in SHAPES[1:]:
                amount = coverage(sd_rrect(px, py, *shape), size)
                if amount > 0:
                    rgb = [c + (target - c) * amount for c, target in zip(rgb, color)]
            if 0.22 < px < 0.78 and 0.31 < py < 0.58:
                distance = min(sd_segment(px, py, a, b) for a, b in wave_segments) - 0.013
                amount = coverage(distance, size)
                rgb = [c + (target - c) * amount for c, target in zip(rgb, WAVE_COLOR)]
            offset = x * 4
            row[offset:offset + 4] = bytes([round(c) for c in rgb] + [round(alpha * 255)])
        rows.append(row)
    return rows


def write_png(path, size, rows):
    raw = b"".join(b"\x00" + bytes(row) for row in rows)

    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xffffffff))

    ihdr = struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)
    with open(path, "wb") as output:
        output.write(b"\x89PNG\r\n\x1a\n")
        output.write(chunk(b"IHDR", ihdr))
        output.write(chunk(b"IDAT", zlib.compress(raw, 9)))
        output.write(chunk(b"IEND", b""))


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: make-icon.py <output.iconset>")
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    rendered = {}
    for name, size in SIZES.items():
        if size not in rendered:
            sys.stderr.write("rendering %dx%d icon...\n" % (size, size))
            rendered[size] = render(size)
        write_png(os.path.join(out, name), size, rendered[size])


if __name__ == "__main__":
    main()
