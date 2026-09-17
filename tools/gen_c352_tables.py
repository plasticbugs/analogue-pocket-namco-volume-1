#!/usr/bin/env python3
"""Generate rtl/data/c352_mulaw.hex: the C352's 8-bit mu-law to 16-bit table,
exactly as MAME's c352_device::device_start builds it (256 entries, 16-bit,
one per line, for $readmemh)."""
import os, sys

def mulaw_table():
    tab = [0] * 256
    j = 0
    for i in range(128):
        tab[i] = (j << 5) & 0xffff
        if i < 16:
            j += 1
        elif i < 24:
            j += 2
        elif i < 48:
            j += 4
        elif i < 100:
            j += 8
        else:
            j += 16
    for i in range(128):
        tab[i + 128] = (~tab[i]) & 0xffe0
    return tab

def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), '..', 'rtl', 'data', 'c352_mulaw.hex')
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, 'w') as f:
        for v in mulaw_table():
            f.write('%04x\n' % v)
    print('wrote', out)

if __name__ == '__main__':
    main()
