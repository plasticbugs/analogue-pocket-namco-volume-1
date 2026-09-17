#!/usr/bin/env python3
"""Compare the C352 bench output (85.333 kHz stereo WAV) with MAME's WAV
(48 kHz stereo) of the same run.

Resamples the RTL output to 48 kHz by linear interpolation, aligns the two by
cross-correlation of the left channel (the run starts with a stretch of silence
and MAME's frame period before the game programs the CRTC differs from the
period the bench assumes, so a constant lag is expected), then reports per
channel: RMS, peak, and the RMS ratio RTL/MAME per 100 ms block for blocks
with signal. PASS if the median block ratio is within TOL of 1 and no more
than a small fraction of blocks fall outside 2*TOL.

    c352_compare.py rtl.wav mame.wav [--frames N] [--tol 0.06]
"""
import sys, wave, struct, math, argparse

def read_wav(path):
    w = wave.open(path, 'rb')
    ch, sw, rate, n = w.getnchannels(), w.getsampwidth(), w.getframerate(), w.getnframes()
    raw = w.readframes(n)
    w.close()
    assert sw == 2 and ch == 2, path
    data = struct.unpack('<%dh' % (n * 2), raw)
    return rate, data[0::2], data[1::2]

def resample(x, src, dst):
    n = int(len(x) * dst / src)
    out = [0.0] * n
    step = src / dst
    for i in range(n):
        p = i * step
        k = int(p)
        f = p - k
        if k + 1 < len(x):
            out[i] = x[k] * (1 - f) + x[k + 1] * f
        elif k < len(x):
            out[i] = x[k]
    return out

def rms(x):
    return math.sqrt(sum(v * v for v in x) / len(x)) if x else 0.0

def find_lag(a, b, rate, max_lag_s=0.2, coarse=8):
    """lag (samples) such that b[i] ~ a[i - lag]; positive = b is later than a."""
    n = min(len(a), len(b))
    # decimate for the coarse search
    ad = [sum(a[i:i + coarse]) / coarse for i in range(0, n, coarse)]
    bd = [sum(b[i:i + coarse]) / coarse for i in range(0, n, coarse)]
    maxl = int(max_lag_s * rate / coarse)
    best, bestl = -1e300, 0
    m = len(ad)
    for lag in range(-maxl, maxl + 1):
        s = 0.0
        if lag >= 0:
            for i in range(lag, m):
                s += ad[i - lag] * bd[i]
        else:
            for i in range(0, m + lag):
                s += ad[i - lag] * bd[i]
        if s > best:
            best, bestl = s, lag
    # refine at full rate around the coarse result
    best, fine = -1e300, bestl * coarse
    for lag in range(bestl * coarse - coarse, bestl * coarse + coarse + 1):
        s = 0.0
        if lag >= 0:
            for i in range(lag, n, 4):
                s += a[i - lag] * b[i]
        else:
            for i in range(0, n + lag, 4):
                s += a[i - lag] * b[i]
        if s > best:
            best, fine = s, lag
    return fine

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('rtl'); ap.add_argument('mame')
    ap.add_argument('--frames', type=int, default=0)
    ap.add_argument('--tol', type=float, default=0.06)
    ap.add_argument('--block', type=float, default=0.1)
    args = ap.parse_args()

    rr, rl, rrt = read_wav(args.rtl)
    mr, ml, mrt = read_wav(args.mame)
    rl = resample(rl, rr, mr); rrt = resample(rrt, rr, mr)
    n = min(len(rl), len(ml))
    if args.frames:
        n = min(n, int(args.frames * 101376 / 6144000 * mr))
    rl, rrt, ml, mrt = rl[:n], rrt[:n], ml[:n], mrt[:n]
    lag = find_lag(rl, ml, mr)
    print('length %.2f s, lag %d samples (%.2f ms; positive = MAME later)' % (n / mr, lag, 1000.0 * lag / mr))
    if lag >= 0:
        rl, rrt = rl[:n - lag], rrt[:n - lag]; ml, mrt = ml[lag:], mrt[lag:]
    else:
        rl, rrt = rl[-lag:], rrt[-lag:]; ml, mrt = ml[:n + lag], mrt[:n + lag]
    n = min(len(rl), len(ml))
    ok = True
    for name, r, m in (('L', rl, ml), ('R', rrt, mrt)):
        r, m = r[:n], m[:n]
        print('%s: RTL rms %.1f peak %d | MAME rms %.1f peak %d' % (name, rms(r), int(max(abs(v) for v in r)), rms(m), max(abs(v) for v in m)))
        blk = int(args.block * mr)
        ratios = []
        silent_mame_loud_rtl = 0
        for i in range(0, n - blk, blk):
            rb, mb = rms(r[i:i + blk]), rms(m[i:i + blk])
            if mb > 200:
                ratios.append((i / mr, rb / mb))
            elif rb > 400:
                silent_mame_loud_rtl += 1
        if not ratios:
            print('  no blocks with signal'); continue
        vals = sorted(x[1] for x in ratios)
        med = vals[len(vals) // 2]
        bad = [x for x in ratios if abs(x[1] - 1) > 2 * args.tol]
        print('  %d blocks with signal: ratio median %.3f min %.3f max %.3f; %d outside +-%.0f%%; %d blocks RTL loud while MAME silent'
              % (len(ratios), med, vals[0], vals[-1], len(bad), 200 * args.tol, silent_mame_loud_rtl))
        for t, v in bad[:8]:
            print('    t=%.2fs ratio %.3f' % (t, v))
        if abs(med - 1) > args.tol or len(bad) > max(2, len(ratios) // 20) or silent_mame_loud_rtl > 2:
            ok = False
    print('PASS' if ok else 'FAIL')
    sys.exit(0 if ok else 1)

if __name__ == '__main__':
    main()
