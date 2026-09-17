// ncv1_mem bench: load the whole ROM image through the download port at the
// Pocket loader's pace, then read it back through all four core ports at once
// (random addresses, pattern bursts of every tile size) and compare with the
// image. Checks the loader's byte pairing, the SDRAM partition, the arbiter
// with every client busy, and the burst unit framing.
//   tb_mem <ncv1.rom> [reads per port]
#include "Vtb_mem_top.h"
#include "verilated.h"
#include <cstdio>
#include <cstdint>
#include <vector>
#include <algorithm>

static Vtb_mem_top *dut;
static unsigned long long cycles = 0;
static void tick(int n = 1) { while (n--) { dut->clk = 0; dut->eval(); dut->clk = 1; dut->eval(); cycles++; } }
static unsigned rng = 1;
static unsigned rnd() { rng = rng * 1103515245u + 12345u; return (rng >> 1) & 0x7fffffff; }

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    if (argc < 2) { fprintf(stderr, "usage: tb_mem rom [reads]\n"); return 2; }
    long nreads = argc > 2 ? atol(argv[2]) : 3000;
    FILE *f = fopen(argv[1], "rb"); if (!f) return 2;
    std::vector<uint8_t> img(0x780000); if (fread(img.data(), 1, img.size(), f) != img.size()) { fprintf(stderr, "short image\n"); return 2; } fclose(f);
    auto w16 = [&](uint32_t b) -> uint16_t { return ((uint16_t)img[b] << 8) | img[b + 1]; };

    dut = new Vtb_mem_top;
    dut->init = 1; dut->dl_we = 0; dut->prog_req = dut->sub_req = dut->pat_req = dut->pcm_req = 0; tick(8); dut->init = 0;
    long w = 0; while (!dut->ready && w++ < 200000) tick();
    if (!dut->ready) { printf("FAIL: SDRAM never ready\n"); return 1; }
    // the APF loader (data_io, DELAY 7, HOLD 4): a byte every 8 clocks, the strobe held 4
    for (uint32_t a = 0; a < img.size(); a++) {
        dut->dl_we = 1; dut->dl_addr = a; dut->dl_data = img[a]; tick(4);
        dut->dl_we = 0; tick(4);
    }
    w = 0; while (dut->dl_busy && w++ < 1000000) tick();
    printf("image loaded: %zu bytes, %llu clocks\n", img.size(), cycles);

    // every port busy at once
    long errors = 0, done_prog = 0, done_sub = 0, done_pat = 0, done_pcm = 0, units = 0;
    uint32_t pa = 0, sa = 0, ca = 0, ta = 0; int tl = 1; bool pb = false, sb = false, cb = false, tb = false;
    int seen_units = 0;
    const int lens[] = {1, 8, 16, 32, 64};
    unsigned long long t0 = cycles, max_wait = 0, req_t = 0, pcm_t = 0;
    std::vector<unsigned> pcm_lat;
    while (done_prog < nreads || done_sub < nreads || done_pat < nreads / 4 || done_pcm < nreads) {
        if (!pb && done_prog < nreads) { pa = rnd() % 0x80000; dut->prog_addr = pa; dut->prog_req = 1; pb = true; }
        if (!sb && done_sub < nreads)  { sa = rnd() % 0x40000; dut->sub_addr = sa; dut->sub_req = 1; sb = true; }
        if (!cb && done_pcm < nreads)  { ca = rnd() % 0x200000; dut->pcm_addr = ca; dut->pcm_req = 1; cb = true; pcm_t = cycles; }
        if (!tb && done_pat < nreads / 4) {
            tl = lens[rnd() % 5]; ta = rnd() % (0x80000 - tl);
            dut->pat_addr = ta | ((rnd() % 4) << 19); dut->pat_len = tl; dut->pat_req = 1; tb = true; seen_units = 0; req_t = cycles;
        }
        tick();
        if (dut->prog_ack && pb) { if (dut->prog_q != w16(pa * 2)) { if (errors++ < 10) printf("prog %05X: %04X want %04X\n", pa, dut->prog_q, w16(pa * 2)); } dut->prog_req = 0; pb = false; done_prog++; }
        if (dut->sub_ack && sb)  { if (dut->sub_q != w16(0x100000 + sa * 2)) { if (errors++ < 10) printf("sub %05X: %04X want %04X\n", sa, dut->sub_q, w16(0x100000 + sa * 2)); } dut->sub_req = 0; sb = false; done_sub++; }
        if (dut->pcm_ack && cb)  { if (dut->pcm_q != img[0x380000 + ca]) { if (errors++ < 10) printf("pcm %06X: %02X want %02X\n", ca, dut->pcm_q, img[0x380000 + ca]); } dut->pcm_req = 0; cb = false; done_pcm++; pcm_lat.push_back((unsigned)(cycles - pcm_t)); }
        if (dut->pat_wr && tb) {
            uint32_t b = (dut->pat_addr >> 20 & 1 ? 0x580000 : 0x180000) + (ta + dut->pat_idx) * 4;
            uint32_t want = ((uint32_t)w16(b) << 16) | w16(b + 2);
            if (dut->pat_idx != seen_units || dut->pat_q != want) { if (errors++ < 10) printf("pat %05X+%d (len %d): idx %d q %08X want %08X\n", ta, seen_units, tl, dut->pat_idx, dut->pat_q, want); }
            seen_units++; units++;
        }
        if (dut->pat_ack && tb) {
            if (seen_units != tl) { if (errors++ < 10) printf("pat %05X len %d: %d units before ack\n", ta, tl, seen_units); }
            if (cycles - req_t > max_wait) max_wait = cycles - req_t;
            dut->pat_req = 0; tb = false; done_pat++;
        }
        if (cycles - t0 > 400000000ULL) { printf("FAIL: timeout\n"); return 1; }
    }
    printf("reads: prog %ld sub %ld pcm %ld, pattern bursts %ld (%ld units, longest %llu clocks), %llu clocks\n",
           done_prog, done_sub, done_pcm, done_pat, units, max_wait, cycles - t0);
    std::sort(pcm_lat.begin(), pcm_lat.end());
    if (!pcm_lat.empty()) printf("sample-ROM read latency with every client busy: median %u, 99%% %u, max %u clocks\n",
        pcm_lat[pcm_lat.size() / 2], pcm_lat[pcm_lat.size() * 99 / 100], pcm_lat.back());
    printf(errors ? "FAIL: %ld mismatches\n" : "PASS\n", errors);
    return errors ? 1 : 0;
}
