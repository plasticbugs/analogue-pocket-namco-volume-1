#!/usr/bin/env python3
"""Generate the Pocket artwork for this core: the 36x36 core icon and the
521x165 platform banner, raw 16-bit little-endian BGRA5551 (five bits per gun,
top bit unused), after the Time Pilot core's generator.

Greys only: Analogue documents the order of the colour fields but the Time
Pilot core found it only shows up on hardware, and with r == g == b both
candidate orders look the same. Add colour once the order is confirmed.

    tools/make_images.py          # writes into pkg/pocket/
"""
import os, struct

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')

FONT = {
    'A': ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
    'C': ["01110", "10001", "10000", "10000", "10000", "10001", "01110"],
    'E': ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
    'I': ["11111", "00100", "00100", "00100", "00100", "00100", "11111"],
    'L': ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
    'M': ["10001", "11011", "10101", "10101", "10001", "10001", "10001"],
    'N': ["10001", "11001", "10101", "10011", "10001", "10001", "10001"],
    'O': ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
    'S': ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
    'T': ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
    'V': ["10001", "10001", "10001", "10001", "10001", "01010", "00100"],
    '1': ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
    '5': ["11111", "10000", "11110", "00001", "00001", "10001", "01110"],
    '9': ["01110", "10001", "10001", "01111", "00001", "10001", "01110"],
    '.': ["00000", "00000", "00000", "00000", "00000", "01100", "01100"],
    ' ': ["00000"] * 7,
}


def pack(rgb5):
    r, g, b = rgb5
    return struct.pack('<H', (r << 10) | (g << 5) | b)


class Img:
    def __init__(self, w, h, fill=(0, 0, 0)):
        self.w, self.h = w, h
        self.px = [fill] * (w * h)

    def rect(self, x0, y0, x1, y1, c):
        for y in range(max(0, y0), min(self.h, y1)):
            for x in range(max(0, x0), min(self.w, x1)):
                self.px[y * self.w + x] = c

    def text(self, x, y, s, c, scale=1, spacing=1):
        cx = x
        for ch in s.upper():
            g = FONT.get(ch, FONT[' '])
            for row, bits in enumerate(g):
                for col, bit in enumerate(bits):
                    if bit == '1':
                        self.rect(cx + col * scale, y + row * scale, cx + (col + 1) * scale, y + (row + 1) * scale, c)
            cx += (len(g[0]) + spacing) * scale
        return cx

    def save(self, path):
        with open(path, 'wb') as f:
            for c in self.px:
                f.write(pack(c))


W = (31, 31, 31)
G = (20, 20, 20)
D = (9, 9, 9)
K = (0, 0, 0)

FIGHTER = [
    "....X....",
    "....X....",
    "...XXX...",
    "X..XXX..X",
    "X.XXXXX.X",
    "XXXXXXXXX",
    "XXX.X.XXX",
    "XX..X..XX",
    "X.......X",
]


def fighter(img, x, y, s, c):
    for r, row in enumerate(FIGHTER):
        for col, ch in enumerate(row):
            if ch == 'X':
                img.rect(x + col * s, y + r * s, x + (col + 1) * s, y + (r + 1) * s, c)


def main():
    core = os.path.join(ROOT, 'pkg', 'pocket', 'Cores', 'plasticbugs.ncv1')
    plats = os.path.join(ROOT, 'pkg', 'pocket', 'Platforms', '_images')

    icon = Img(36, 36, K)
    for i, (x, y) in enumerate([(3, 30), (11, 26), (29, 32), (22, 3), (5, 8), (31, 14)]):
        icon.rect(x, y, x + 1, y + 1, G if i % 2 else D)
    fighter(icon, 5, 5, 3, W)
    icon.save(os.path.join(core, 'icon.bin'))

    ban = Img(521, 165, K)
    for y in range(165):
        v = 2 + (y * 6) // 165
        ban.rect(0, y, 521, y + 1, (v, v, v))
    for (x, y) in [(12, 20), (70, 140), (500, 12), (460, 150), (300, 8), (110, 60), (95, 118)]:
        ban.rect(x, y, x + 2, y + 2, G)
    ban.rect(0, 126, 521, 128, G)
    fighter(ban, 24, 40, 8, W)
    ban.text(120, 34, 'NAMCO CLASSIC', W, scale=4, spacing=1)
    ban.text(120, 76, 'COLLECTION VOL.1', W, scale=4, spacing=1)
    ban.text(120, 138, 'NAMCO 1995', G, scale=2, spacing=1)
    ban.save(os.path.join(plats, 'ncv1.bin'))

    for p in (os.path.join(core, 'icon.bin'), os.path.join(plats, 'ncv1.bin')):
        print('wrote', p, os.path.getsize(p), 'bytes')


if __name__ == '__main__':
    main()
