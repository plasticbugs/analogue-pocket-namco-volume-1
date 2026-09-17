#!/usr/bin/env python3
"""Straight port of MAME's c352.cpp (sound_stream_update / fetch_sample /
ramp_volume / write) used to check the RTL bench: runs the captured register
log through the model at the chip's 85.333 kHz rate and writes a WAV, or
compares against the RTL's WAV sample by sample.

    c352_model.py rom.rom log.txt out.wav [--f0 A --f1 B] [--rtl rtl.wav]
"""
import sys, struct, wave, argparse

BUSY, KEYON, KEYOFF, LOOPTRG, LOOPHIST, FM = 0x8000, 0x4000, 0x2000, 0x1000, 0x0800, 0x0400
PHASERL, PHASEFL, PHASEFR, LDIR, LINK, NOISE, MULAW, FILTER, LOOP, REVERSE = 0x200, 0x100, 0x80, 0x40, 0x20, 0x10, 0x8, 0x4, 0x2, 0x1
SPF = 1408.0          # samples per frame at the game's CRTC setting (60.6 Hz)
SPF0 = 402 * 261 * 85333.333333 / 6144000.0   # before the game programs the CRTC (58.56 Hz)
FCFG = 42             # frame from which SPF applies
LINES, DOTS = 261, 402

def s8(v): v &= 0xff; return v - 256 if v & 0x80 else v
def s16(v): v &= 0xffff; return v - 65536 if v & 0x8000 else v

def mulaw_table():
    tab = [0] * 256; j = 0
    for i in range(128):
        tab[i] = (j << 5) & 0xffff
        j += 1 if i < 16 else 2 if i < 24 else 4 if i < 48 else 8 if i < 100 else 16
    for i in range(128):
        tab[i + 128] = (~tab[i]) & 0xffe0
    return [s16(v) for v in tab]

class Voice:
    __slots__ = ('pos', 'counter', 'sample', 'last', 'vol_f', 'vol_r', 'cur', 'freq', 'flags', 'bank', 'start', 'end', 'loop')
    def __init__(self):
        self.pos = 0; self.counter = 0; self.sample = 0; self.last = 0
        self.vol_f = 0; self.vol_r = 0; self.cur = [0, 0, 0, 0]
        self.freq = 0; self.flags = 0; self.bank = 0; self.start = 0; self.end = 0; self.loop = 0

REGS = ('vol_f', 'vol_r', 'freq', 'flags', 'bank', 'start', 'end', 'loop')

class C352:
    def __init__(self, rom):
        self.rom = rom; self.v = [Voice() for _ in range(32)]; self.mulaw = mulaw_table()
        self.random = 0x1234; self.control = 0; self.fetches = 0
    def read_byte(self, a):
        a &= 0xffffff
        return self.rom[a] if a < len(self.rom) else 0
    def read(self, off):
        if off < 0x100: return getattr(self.v[off // 8], REGS[off % 8]) & 0xffff
        if off == 0x200: return self.control
        return 0
    def write(self, off, data):
        if off < 0x100:
            setattr(self.v[off // 8], REGS[off % 8], data & 0xffff)
        elif off == 0x200:
            self.control = data & 0xffff
        elif off == 0x202:
            for v in self.v:
                if v.flags & KEYON:
                    v.pos = ((v.bank << 16) | v.start) & 0xffffffff
                    v.sample = 0; v.last = 0; v.counter = 0xffff
                    v.flags |= BUSY; v.flags &= ~(KEYON | LOOPHIST); v.flags &= 0xffff
                    v.cur = [0, 0, 0, 0]
                if v.flags & KEYOFF:
                    v.flags &= ~(BUSY | KEYOFF); v.flags &= 0xffff
                    v.counter = 0xffff
    def fetch(self, v):
        v.last = v.sample
        if v.flags & NOISE:
            self.random = ((self.random >> 1) ^ ((-(self.random & 1)) & 0xfff6)) & 0xffff
            v.sample = s16(self.random)
        else:
            s = s8(self.read_byte(v.pos)); self.fetches += 1
            v.sample = self.mulaw[s & 0xff] if v.flags & MULAW else s16(s << 8)
            pos = v.pos & 0xffff
            if (v.flags & LOOP) and (v.flags & REVERSE):
                if (v.flags & LDIR) and pos == v.loop: v.flags &= ~LDIR
                elif not (v.flags & LDIR) and pos == v.end: v.flags |= LDIR
                v.pos = (v.pos + (-1 if v.flags & LDIR else 1)) & 0xffffffff
            elif pos == v.end:
                if (v.flags & LINK) and (v.flags & LOOP):
                    v.pos = (v.start << 16) | v.loop; v.flags |= LOOPHIST
                elif v.flags & LOOP:
                    v.pos = (v.pos & 0xff0000) | v.loop; v.flags |= LOOPHIST
                else:
                    v.flags |= KEYOFF; v.flags &= ~BUSY; v.flags &= 0xffff; v.sample = 0
            else:
                v.pos = (v.pos + (-1 if v.flags & REVERSE else 1)) & 0xffffffff
    def step(self):
        out = [0, 0]
        for v in self.v:
            s = 0
            if v.flags & BUSY:
                nxt = v.counter + v.freq
                if nxt & 0x10000: self.fetch(v)
                if (nxt ^ v.counter) & 0x18000:
                    for ch, val in ((0, v.vol_f >> 8), (1, v.vol_f & 0xff)):
                        d = v.cur[ch] - val
                        if d != 0: v.cur[ch] += -1 if d > 0 else 1
                v.counter = nxt & 0xffff
                s = v.sample
                if not (v.flags & FILTER):
                    # u32 * int in C: unsigned product, logical shift; then s16 truncation
                    prod = (v.counter * ((v.sample - v.last) & 0xffffffff)) & 0xffffffff
                    s = s16(v.last + (prod >> 16))
            out[0] += ((-s if v.flags & PHASEFL else s) * v.cur[0]) >> 8
            out[1] += ((-s if v.flags & PHASEFR else s) * v.cur[1]) >> 8
        return s16(out[0] >> 3), s16(out[1] >> 3)

def event_time(fr, by, bx):
    frac = (by * DOTS + bx) / float(LINES * DOTS)
    if fr < FCFG: return (fr + frac) * SPF0
    return FCFG * SPF0 + (fr - FCFG + frac) * SPF

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('rom'); ap.add_argument('log'); ap.add_argument('out')
    ap.add_argument('--f0', type=int, default=0); ap.add_argument('--f1', type=int, default=400)
    ap.add_argument('--rtl', help='RTL wav (85333 Hz) to compare sample by sample')
    ap.add_argument('--rtl-cps', type=int, default=768, help='bench clocks per sample, for its event timing')
    args = ap.parse_args()
    img = open(args.rom, 'rb').read(); rom = img[0x380000:0x580000]
    evs = []
    with open(args.log) as f:
        for line in f:
            if line.startswith('C352W'):
                p = line.split(); fr, by, bx = int(p[1]), int(p[2]), int(p[3])
                evs.append((event_time(fr, by, bx), (int(p[4], 16) - 0xa00000) // 2, int(p[5], 16)))
    evs.sort(key=lambda e: e[0])
    chip = C352(rom)
    t_end = event_time(args.f1, 0, 0)
    n = int(t_end)
    out = []
    ei = 0
    for i in range(n):
        while ei < len(evs) and evs[ei][0] <= i:
            chip.write(evs[ei][1], evs[ei][2]); ei += 1
        out.append(chip.step())
    w = wave.open(args.out, 'wb'); w.setnchannels(2); w.setsampwidth(2); w.setframerate(85333)
    w.writeframes(struct.pack('<%dh' % (2 * len(out)), *[x for lr in out for x in lr])); w.close()
    print('model: %d samples, %d fetches (%.2f/sample), %d events' % (n, chip.fetches, chip.fetches / n, ei))
    if args.rtl:
        r = wave.open(args.rtl); rn = r.getnframes(); rd = struct.unpack('<%dh' % (2 * rn), r.readframes(rn))
        m = min(rn, n); diff = 0; first = None; maxd = 0
        for i in range(m):
            dl = abs(rd[2 * i] - out[i][0]); dr = abs(rd[2 * i + 1] - out[i][1])
            if dl or dr:
                diff += 1
                if first is None: first = i
                maxd = max(maxd, dl, dr)
        print('rtl vs model: %d of %d samples differ (first at %s, max |diff| %d)' % (diff, m, first, maxd))
        if first is not None:
            for i in range(max(0, first - 3), min(m, first + 12)):
                print('  %7d rtl %6d %6d  model %6d %6d' % (i, rd[2 * i], rd[2 * i + 1], out[i][0], out[i][1]))

if __name__ == '__main__':
    main()
