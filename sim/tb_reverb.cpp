// Impulse and full-scale tests of the cabinet reverb (rtl/nc_reverb.sv): tail
// envelope per 50 ms at each mode, that mode 0 is a pure one-sample delay, that
// a left-only impulse keeps the dry image on the left while the tail lands on
// both, and that a full-scale square never overflows.
#include "Vnc_reverb.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <vector>
static Vnc_reverb *dut;
static void tick() { dut->clk = 0; dut->eval(); dut->clk = 1; dut->eval(); }
static void sample(short l, short r, short *ol, short *orr) {   // one 48 kHz period
    dut->in_l = l; dut->in_r = r; dut->ce = 1; tick(); dut->ce = 0;
    for (int i = 0; i < 60; i++) tick();
    *ol = (short)dut->out_l; *orr = (short)dut->out_r;
    for (int i = 0; i < 963; i++) tick();
}
int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    dut = new Vnc_reverb;
    int fail = 0;
    for (int mode = 0; mode <= 3; mode++) {
        dut->reset = 1; dut->ce = 0; dut->mode = mode; tick(); tick(); dut->reset = 0; tick();
        // reset clears the pointers and filter states but not the block RAM
        // delay lines: flush the previous test's history with 2 s of silence
        { short a, b; for (int n = 0; n < 96000; n++) sample(0, 0, &a, &b); }
        std::vector<int> L, R;
        for (int n = 0; n < 48000; n++) { short a, b; sample(n == 0 ? 16384 : 0, 0, &a, &b); L.push_back(a); R.push_back(b); }
        // the output read 60 clocks after a sample's ce is that sample, processed
        int tailL = 0, tailR = 0;
        for (int n = 1; n < 48000; n++) { tailL = std::max(tailL, abs(L[n])); tailR = std::max(tailR, abs(R[n])); }
        // integer damping settles at a few LSB of DC after silence (the same
        // rounding limit cycle as in the Punch-Out!! and Pole Position cores, about -76 dB): ignore |v| <= 16
        int first = 0; for (int n = 1; n < 48000; n++) if (abs(L[n]) > 16) { first = n; break; }
        printf("mode %d: left impulse 16384 -> dry L[0]=%d R[0]=%d, tail starts at sample %d (%.1f ms), peak L %d R %d\n",
               mode, L[0], R[0], first, first / 48.0, tailL, tailR);
        if (abs(L[0] - 16384) > 16 || abs(R[0]) > 16) { printf("  FAIL: dry path\n"); fail = 1; }
        if (mode != 0 && first != 1426) { printf("  FAIL: first echo should be at sample 1426 (29.7 ms)\n"); fail = 1; }
        if (mode == 0 && (tailL || tailR)) { printf("  FAIL: mode 0 must have no tail\n"); fail = 1; }
        if (mode != 0 && (tailL <= 16 || tailL != tailR)) { printf("  FAIL: tail must be the same on both sides\n"); fail = 1; }
        for (int w = 0; w < 12 && mode; w++) {
            int peak = 0; for (int n = w * 2400; n < (w + 1) * 2400; n++) if (n > 0 && abs(L[n]) > peak) peak = abs(L[n]);
            printf("  %3d-%3d ms: tail peak %5d\n", w * 50, w * 50 + 50, peak);
        }
        dut->reset = 1; tick(); dut->reset = 0; tick();
        int mx = 0, mn = 0;
        for (int n = 0; n < 48000; n++) {
            short v = ((n / 240) & 1) ? 32767 : -32768, a, b;
            sample(v, v, &a, &b);
            if (a > mx) mx = a; if (a < mn) mn = a;
        }
        printf("mode %d full-scale square: output range %d .. %d\n", mode, mn, mx);
    }
    printf(fail ? "reverb: FAIL\n" : "reverb: ok\n");
    delete dut;
    return fail;
}
