#!/usr/bin/env python3
"""Generate MacMonitor.icns from scratch.

There is no Pillow on a stock macOS, so the PNG is written by hand (zlib +
struct) and the shapes are anti-aliased with a signed distance field rather than
by supersampling -- one sample per pixel instead of sixteen, which is what makes
a pure-Python renderer fast enough to be worth running on every build. The
remaining sizes in the iconset come from sips, which is part of macOS.

Only the 1024px master is rendered here; everything else is a downscale of it.

Usage: make-icon.py <output.iconset>
"""
import math
import os
import shutil
import struct
import subprocess
import sys
import zlib

MASTER = 1024

# --- palette -----------------------------------------------------------------
# Kept in step with the colours ui.c asks ncurses for, so the icon reads as the
# same product: green / yellow / red for the meter fills.
BG_TOP = (32, 40, 54)
BG_BOT = (18, 23, 33)
TRACK = (46, 54, 70)
GREEN = (76, 195, 138)
YELLOW = (232, 184, 75)
RED = (229, 72, 77)

# --- geometry, in fractions of the canvas -------------------------------------
CARD = (0.10, 0.10, 0.90, 0.90)
CARD_R = 0.180

TRACK_X0, TRACK_X1 = 0.235, 0.765
BAR_H = 0.082
BAR_R = BAR_H / 2.0
BAR_CENTRES = (0.335, 0.500, 0.665)
# (fill fraction, colour) top to bottom
BARS = (
    (0.40, GREEN),
    (0.65, YELLOW),
    (0.85, RED),
)

SS = 1.0 / MASTER   # one pixel, in the same fractional units


def sd_rrect(px, py, x0, y0, x1, y1, r):
    """Signed distance to a rounded rectangle: negative inside."""
    dx = abs(px - (x0 + x1) * 0.5) - ((x1 - x0) * 0.5 - r)
    dy = abs(py - (y0 + y1) * 0.5) - ((y1 - y0) * 0.5 - r)
    ax = dx if dx > 0.0 else 0.0
    ay = dy if dy > 0.0 else 0.0
    return math.hypot(ax, ay) + min(max(dx, dy), 0.0) - r


def sd_box(px, py, x0, y0, x1, y1):
    """Signed distance to a plain rectangle, for the flat end of a meter fill."""
    dx = max(x0 - px, px - x1)
    dy = max(y0 - py, py - y1)
    ax = dx if dx > 0.0 else 0.0
    ay = dy if dy > 0.0 else 0.0
    return math.hypot(ax, ay) + min(max(dx, dy), 0.0)


def coverage(d):
    """Distance -> alpha. The 0.5 puts the shape's edge at half coverage."""
    a = 0.5 - d / SS
    if a < 0.0:
        return 0.0
    return 1.0 if a > 1.0 else a


def render():
    cx0, cy0, cx1, cy1 = CARD
    span = cy1 - cy0
    rows = []

    bars = []
    for centre, (frac, colour) in zip(BAR_CENTRES, BARS):
        y0 = centre - BAR_H * 0.5
        y1 = centre + BAR_H * 0.5
        bars.append((y0, y1, TRACK_X0 + (TRACK_X1 - TRACK_X0) * frac, colour))

    for y in range(MASTER):
        py = (y + 0.5) / MASTER
        row = bytearray(MASTER * 4)
        for x in range(MASTER):
            px = (x + 0.5) / MASTER

            a_card = coverage(sd_rrect(px, py, cx0, cy0, cx1, cy1, CARD_R))
            if a_card <= 0.0:
                continue        # transparent: everything else lives inside the card

            t = (py - cy0) / span
            r = BG_TOP[0] + (BG_BOT[0] - BG_TOP[0]) * t
            g = BG_TOP[1] + (BG_BOT[1] - BG_TOP[1]) * t
            b = BG_TOP[2] + (BG_BOT[2] - BG_TOP[2]) * t

            for y0, y1, fill_x1, colour in bars:
                d_track = sd_rrect(px, py, TRACK_X0, y0, TRACK_X1, y1, BAR_R)
                a_track = coverage(d_track)
                if a_track > 0.0:
                    r += (TRACK[0] - r) * a_track
                    g += (TRACK[1] - g) * a_track
                    b += (TRACK[2] - b) * a_track

                    # Intersecting a flat box with the track keeps the fill's
                    # right end square and its left end rounded, which is what
                    # a meter looks like.
                    d_fill = max(sd_box(px, py, TRACK_X0, y0, fill_x1, y1),
                                 d_track)
                    a_fill = coverage(d_fill)
                    if a_fill > 0.0:
                        r += (colour[0] - r) * a_fill
                        g += (colour[1] - g) * a_fill
                        b += (colour[2] - b) * a_fill

            o = x * 4
            row[o] = int(r + 0.5)
            row[o + 1] = int(g + 0.5)
            row[o + 2] = int(b + 0.5)
            row[o + 3] = int(a_card * 255.0 + 0.5)

        rows.append(row)
    return rows


def write_png(path, size, rows):
    raw = b"".join(b"\x00" + bytes(r) for r in rows)

    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xffffffff))

    ihdr = struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)   # 8-bit RGBA
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", ihdr))
        f.write(chunk(b"IDAT", zlib.compress(raw, 9)))
        f.write(chunk(b"IEND", b""))


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: make-icon.py <output.iconset>")

    out = sys.argv[1]
    if os.path.isdir(out):
        shutil.rmtree(out)
    os.makedirs(out)

    master = os.path.join(out, "_master.png")
    sys.stderr.write("rendering %dx%d master...\n" % (MASTER, MASTER))
    write_png(master, MASTER, render())

    # Every entry iconutil insists on. Each name maps to the pixel size sips
    # should produce for it; 1024 is the master itself.
    wanted = {
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
    for name, size in wanted.items():
        dst = os.path.join(out, name)
        if size == MASTER:
            shutil.copyfile(master, dst)
        else:
            subprocess.run(["sips", "-z", str(size), str(size), master,
                            "--out", dst],
                           check=True, stdout=subprocess.DEVNULL,
                           stderr=subprocess.DEVNULL)
    os.remove(master)


if __name__ == "__main__":
    main()
