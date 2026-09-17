// C352 replay bench: feeds the RTL the register writes MAME's H8 made
// (artifacts/c352/*_log.txt, "C352W frame beamy beamx addr data"), at the same
// moments in sample time, with the sample ROM from the image, and writes the
// RTL's audio as a 16-bit stereo WAV at the chip's 85.333 kHz rate for
// tools/c352_compare.py. Reads in the log ("C352R") are replayed too and the
// value the RTL returns is compared (reported, not fatal: a flags read races
// the sample engine by design).
//
//   tb_c352 <rom.rom> <log.txt> <out.wav> [frames] [clocks_per_sample]
#include "Vc352.h"
#include "Vc352___024root.h"
#include "verilated.h"
#include <cstdio>
#include <cstdint>
#include <cstring>
#include <string>
#include <vector>
#include <fstream>

struct Ev { double t; bool wr; uint16_t addr; uint16_t data; };

// MAME's screen runs 402 x 261 dots at 6.144 MHz (58.56 Hz, 1457.4 samples per
// frame) until the game programs the YGV608 CRTC in frame 41, after which the
// frame is 264 x 384 dot clocks (60.6 Hz, exactly 1408 samples).
static const double SAMPLES_PER_FRAME = 1408.0;
static const double SAMPLES_PER_FRAME0 = 402.0 * 261.0 * (85333.333333 / 6144000.0);
static const int FRAME_CFG = 42;
static const int LINES = 261, DOTS = 402;
static double event_time(unsigned long fr, unsigned long by, unsigned long bx) {
    double frac = (double)(by * DOTS + bx) / (double)(LINES * DOTS);
    if (fr < (unsigned long)FRAME_CFG) return ((double)fr + frac) * SAMPLES_PER_FRAME0;
    return FRAME_CFG * SAMPLES_PER_FRAME0 + ((double)(fr - FRAME_CFG) + frac) * SAMPLES_PER_FRAME;
}

static void wav_write(const char *path, const std::vector<int16_t> &lr, int rate) {
    FILE *f = fopen(path, "wb");
    uint32_t datasz = lr.size() * 2, riffsz = 36 + datasz;
    uint16_t ch = 2, bps = 16, align = 4; uint32_t byterate = rate * 4, fmtsz = 16; uint16_t fmt = 1;
    fwrite("RIFF", 1, 4, f); fwrite(&riffsz, 4, 1, f); fwrite("WAVEfmt ", 1, 8, f);
    fwrite(&fmtsz, 4, 1, f); fwrite(&fmt, 2, 1, f); fwrite(&ch, 2, 1, f); fwrite(&rate, 4, 1, f);
    fwrite(&byterate, 4, 1, f); fwrite(&align, 2, 1, f); fwrite(&bps, 2, 1, f);
    fwrite("data", 1, 4, f); fwrite(&datasz, 4, 1, f);
    fwrite(lr.data(), 2, lr.size(), f); fclose(f);
}

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    if (argc < 4) { fprintf(stderr, "usage: tb_c352 rom log out.wav [frames] [cps]\n"); return 2; }
    long frames = argc > 4 ? atol(argv[4]) : 2400;
    int cps = argc > 5 ? atoi(argv[5]) : 512;

    std::vector<uint8_t> img;
    { FILE *f = fopen(argv[1], "rb"); if (!f) { fprintf(stderr, "no rom\n"); return 2; }
      fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET); img.resize(n); (void)!fread(img.data(), 1, n, f); fclose(f); }
    if (img.size() < 0x580000) { fprintf(stderr, "image too small\n"); return 2; }
    const uint8_t *rom = img.data() + 0x380000;
    const uint32_t rom_size = 0x200000;

    std::vector<Ev> evs;
    {
        std::ifstream f(argv[2]); std::string line;
        while (std::getline(f, line)) {
            bool wr;
            if (!line.compare(0, 5, "C352W")) wr = true; else if (!line.compare(0, 5, "C352R")) wr = false; else continue;
            unsigned long fr, by, bx, addr, data;
            if (sscanf(line.c_str() + 5, "%lu %lu %lu %lx %lx", &fr, &by, &bx, &addr, &data) != 5) continue;
            double t = event_time(fr, by, bx);
            evs.push_back({t, wr, (uint16_t)((addr - 0xa00000) / 2), (uint16_t)data});
        }
    }
    printf("%zu events, %ld frames, %d clocks/sample\n", evs.size(), frames, cps);

    Vc352 *top = new Vc352;
    top->clk = 0; top->reset = 1; top->cen_sample = 0; top->reg_wr = 0; top->reg_rd = 0; top->reg_addr = 0; top->reg_wdata = 0;
    top->rom_ack = 0; top->rom_q = 0;
    auto tick = [&]() { top->clk = 0; top->eval(); top->clk = 1; top->eval(); };
    for (int i = 0; i < 8; i++) tick();
    top->reset = 0;

    std::vector<int16_t> out;
    long total_samples = (long)event_time(frames, 0, 0);
    long clocks = 0, samples = 0;
    size_t ei = 0;
    long fetches = 0, read_checks = 0, read_mismatch = 0, samples_with_fetch = 0;
    int rom_delay = 0; bool rom_busy = false; uint32_t rom_a = 0;
    bool check_read = false; uint16_t exp_read = 0, read_addr = 0;
    bool fetched_this_sample = false;
    int overrun_reported = 0;

    while (samples < total_samples) {
        // a sample tick
        bool sample_tick = (clocks % cps) == 0;
        top->cen_sample = sample_tick ? 1 : 0;
        // register events due in this sample-time window (one per clock, in order)
        double now = (double)clocks / cps;
        top->reg_wr = 0; top->reg_rd = 0;
        if (check_read) {
            read_checks++;
            if (top->reg_q != exp_read) {
                if (read_mismatch < 10) printf("read mismatch addr %03X: rtl %04X mame %04X (sample %ld)\n", read_addr, top->reg_q, exp_read, samples);
                read_mismatch++;
            }
            check_read = false;
        } else if (ei < evs.size() && evs[ei].t <= now) {
            const Ev &e = evs[ei++];
            top->reg_addr = e.addr; top->reg_wdata = e.data;
            if (e.wr) top->reg_wr = 1; else { top->reg_rd = 1; check_read = true; exp_read = e.data; read_addr = e.addr; }
        }
        // sample ROM: ack a few clocks after the request
        top->rom_ack = 0;
        if (top->rom_req && !rom_busy) { rom_busy = true; rom_delay = 6; rom_a = top->rom_addr; }
        if (rom_busy) {
            if (--rom_delay == 0) {
                top->rom_q = (rom_a < rom_size) ? rom[rom_a] : 0;
                top->rom_ack = 1; rom_busy = false; fetches++; fetched_this_sample = true;
            }
        }
        tick();
        clocks++;
        if (top->rom_ack) rom_busy = false;
        if (top->sample_valid) {
            out.push_back((int16_t)top->out_l); out.push_back((int16_t)top->out_r);
            samples++;
            if (fetched_this_sample) samples_with_fetch++;
            fetched_this_sample = false;
        }
        if (top->rootp->c352__DOT__overrun && overrun_reported < 3) { printf("engine overrun at sample %ld\n", samples); overrun_reported++; }
    }
    wav_write(argv[3], out, 85333);
    printf("%ld samples, %ld clocks, %ld rom fetches (%.2f per sample, %.1f%% of samples fetch), %ld reads checked, %ld mismatched\n",
           samples, clocks, fetches, (double)fetches / samples, 100.0 * samples_with_fetch / samples, read_checks, read_mismatch);
    printf("events consumed %zu of %zu\n", ei, evs.size());
    delete top;
    return 0;
}
