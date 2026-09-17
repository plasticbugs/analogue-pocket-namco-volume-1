#!/usr/bin/env python3
"""Verify a built gaiapolis .rom image against MAME's own ROM regions.

docs/rom-regions.sha256 records the SHA-256 of several slices of each region as
MAME 0.288 loads them. This checks the corresponding slices of the built image
hash the same, which is what catches interleave, ordering and endianness
mistakes. Digests rather than bytes, so no ROM content is stored here.

The one region that is not a straight copy is the K056832 tile ROM: MAME
expands it to 5-byte groups whose fifth byte (the unused 5th bitplane) is
always zero for this game, and the image drops that byte. Those slices are
re-expanded from the image before hashing.

To regenerate the manifest from your own romset:
    mame ncv1 -autoboot_script tools/dump_regions.lua ...   # writes artifacts/mame_regions.txt
    python3 tools/make_region_manifest.py

Usage: verify_rom.py <image.rom> [docs/rom-regions.sha256]
"""
import sys, hashlib

# region tag -> (image offset, region length)
LAYOUT = {
    ':maincpu':  (0x0000000, 0x300000),
    ':soundcpu': (0x0300000, 0x040000),
    ':k056832':  (0x0340000, 0x280000),   # 5-byte groups in MAME, 4 in the image
    ':gfx3':     (0x0540000, 0x180000),
    ':gfx4':     (0x06C0000, 0x0A0000),
    ':k054539':  (0x0760000, 0x400000),
    ':k055673':  (0x0B60000, 0x800000),
    ':eeprom':   (0x1360000, 0x000080),
}


def slice_bytes(img, tag, off, length):
    """The image bytes for region `tag` at `off`, rebuilt into region form."""
    base, _ = LAYOUT[tag]
    if tag != ':k056832':
        return img[base + off:base + off + length]
    # region byte r lives in group r//5 at position r%5; position 4 is the
    # unused 5th bitplane, which MAME leaves at zero and the image omits.
    out = bytearray(length)
    for i in range(length):
        r = off + i
        k = r % 5
        if k != 4:
            out[i] = img[base + (r // 5) * 4 + k]
    return bytes(out)


def main():
    img = open(sys.argv[1], 'rb').read()
    manifest = sys.argv[2] if len(sys.argv) > 2 else 'docs/rom-regions.sha256'

    checked = bad = 0
    for line in open(manifest):
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        tag, off, length, want = line.split()
        off, length = int(off), int(length)
        got = slice_bytes(img, tag, off, length)
        have = hashlib.sha256(got).hexdigest()
        ok = have == want
        checked += 1
        print(f"{'OK  ' if ok else 'FAIL'}  {tag:<10} region+{off:#09x} "
              f"-> image+{LAYOUT[tag][0] + off:#09x}  {length} bytes"
              + ('' if ok else f'\n        want {want}\n        got  {have}'))
        if not ok:
            bad += 1

    print()
    if bad:
        sys.exit(f'{bad} slice(s) did not match')
    print(f'all {checked} slices match MAME')


if __name__ == '__main__':
    main()
