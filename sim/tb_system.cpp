// Whole-machine bench: ncv1_core with the ROM image behind latency-modelled
// request/ack ports, running from reset. Captures frames (the DE window, 288x224)
// as PPM files and the C352 output as a WAV, and reports what the machine did.
//
//   tb_system <ncv1.rom> <frames> <outdir> [--input frame:mask:frames,...] [--snap f1,f2,...]
//
// Inputs are the two 16-bit ports (active low); masks name bits of P1P2 (0x0001
// right ... 0x0080 P1 start, 0x1000.. P2) or of DSW with a 'D' prefix (D0x1000 coin).
#include "Vncv1_core.h"
#include "Vncv1_core___024root.h"
#include "verilated.h"
#include <cstdio>
#include <cstdint>
#include <cstring>
#include <string>
#include <vector>
#include <set>

static std::vector<uint8_t> img;
struct Press { long frame; bool dsw; uint16_t mask; long len; };

static void write_ppm(const std::string &path, const std::vector<uint8_t> &rgb, int w, int h) {
    FILE *f = fopen(path.c_str(), "wb"); if (!f) return;
    fprintf(f, "P6\n%d %d\n255\n", w, h); fwrite(rgb.data(), 1, rgb.size(), f); fclose(f);
}
static void write_wav(const std::string &path, const std::vector<int16_t> &pcm, int rate) {
    FILE *f = fopen(path.c_str(), "wb"); if (!f) return;
    uint32_t data_bytes = pcm.size() * 2, fmt_len = 16, riff = 36 + data_bytes;
    uint16_t ch = 2, bits = 16, blk = 4, fmtc = 1; uint32_t brate = rate * 4;
    fwrite("RIFF", 1, 4, f); fwrite(&riff, 4, 1, f); fwrite("WAVEfmt ", 1, 8, f); fwrite(&fmt_len, 4, 1, f);
    fwrite(&fmtc, 2, 1, f); fwrite(&ch, 2, 1, f); fwrite(&rate, 4, 1, f); fwrite(&brate, 4, 1, f); fwrite(&blk, 2, 1, f); fwrite(&bits, 2, 1, f);
    fwrite("data", 1, 4, f); fwrite(&data_bytes, 4, 1, f); fwrite(pcm.data(), 2, pcm.size(), f); fclose(f);
}

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    if (argc < 4) { fprintf(stderr, "usage: tb_system rom frames outdir [--input f:mask:len,...] [--snap f,...]\n"); return 2; }
    std::string outdir = argv[3];
    long nframes = atol(argv[2]);
    std::vector<Press> presses; std::set<long> snaps;
    for (int i = 4; i < argc; i++) {
        if (!strcmp(argv[i], "--input") && i + 1 < argc) {
            char *s = strdup(argv[++i]);
            for (char *tok = strtok(s, ","); tok; tok = strtok(nullptr, ",")) {
                long fr, len; char m[32];
                if (sscanf(tok, "%ld:%31[^:]:%ld", &fr, m, &len) == 3) {
                    bool d = m[0] == 'D'; presses.push_back({fr, d, (uint16_t)strtoul(d ? m + 1 : m, nullptr, 0), len});
                }
            }
        } else if (!strcmp(argv[i], "--snap") && i + 1 < argc) {
            char *s = strdup(argv[++i]);
            for (char *tok = strtok(s, ","); tok; tok = strtok(nullptr, ",")) snaps.insert(atol(tok));
        }
    }
    FILE *f = fopen(argv[1], "rb"); if (!f) { fprintf(stderr, "no rom\n"); return 2; }
    fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET); img.resize(n); fread(img.data(), 1, n, f); fclose(f);
    if (img.size() < 0x780000) { fprintf(stderr, "image too small (7,864,320 bytes expected)\n"); return 2; }

    Vncv1_core *top = new Vncv1_core;
    auto tick = [&]() { top->clk = 0; top->eval(); top->clk = 1; top->eval(); };
    top->reset = 1; top->pix_sync = 0; top->dsw = 0xffff; top->p1p2 = 0xffff;
    top->prog_ack = 0; top->sub_ack = 0; top->pat_ack = 0; top->pcm_ack = 0; top->eep_ld_we = 0; top->eep_rd_addr = 0;
    for (int i = 0; i < 20; i++) tick();
    top->reset = 0;

    // memory ports: each answers a fixed number of clocks after the request rises
    struct Port { int lat; int cnt; bool busy; } prog{9, 0, false}, sub{9, 0, false}, pat{12, 0, false}, pcm{9, 0, false};
    auto word_at = [&](uint32_t byte) -> uint16_t { return ((uint16_t)img[byte] << 8) | img[byte + 1]; };
    int pat_n = 0; bool pat_last = false;

    std::vector<uint8_t> frame(288 * 224 * 3, 0);
    std::vector<int16_t> audio;
    long frames = 0, clocks = 0; int x = 0, y = 0; bool de_d = false, vs_d = false;
    long h8_instr = 0, h8_irqs = 0; bool h8_ran = false, unsup = false, halted = false; int unsup_src = 0; long unsup_frame = -1;
    long pat_fetches = 0, prog_fetches = 0, sub_fetches = 0, pcm_fetches = 0;
    uint32_t last_h8_pc = 0, last_68k = 0;

    while (frames < nframes) {
        // ---- inputs
        uint16_t p = 0xffff, d = 0xffff;
        for (auto &pr : presses) if (frames >= pr.frame && frames < pr.frame + pr.len) { if (pr.dsw) d &= ~pr.mask; else p &= ~pr.mask; }
        top->p1p2 = p; top->dsw = d;
        // ---- memory
        auto serve = [&](Port &pt, bool req, int &ack_out, auto fill) {
            ack_out = 0;
            if (req) { if (!pt.busy) { pt.busy = true; pt.cnt = pt.lat; } else if (pt.cnt > 0 && --pt.cnt == 0) { fill(); ack_out = 1; } }
            else pt.busy = false;
        };
        int a;
        serve(prog, top->prog_req, a, [&]() { top->prog_q = word_at(0x000000 + (top->prog_addr << 1)); prog_fetches++; }); top->prog_ack = a;
        serve(sub,  top->sub_req,  a, [&]() { top->sub_q  = word_at(0x100000 + (top->sub_addr << 1));  sub_fetches++; });  top->sub_ack = a;
        // pattern ROM: bursts of pat_len units, the first after the port latency, then one every 4 clocks
        top->pat_ack = 0; top->pat_wr = 0;
        if (top->pat_req) {
            if (!pat.busy) { pat.busy = true; pat.cnt = pat.lat; pat_n = 0; pat_last = false; }
            else if (pat_last) { top->pat_ack = 1; }
            else if (--pat.cnt == 0) {
                uint32_t u = top->pat_addr + pat_n;
                uint32_t b = ((u >> 20) & 1 ? 0x580000 : 0x180000) + ((u & 0x7ffff) << 2);   // chip u[20], mirrored
                top->pat_q = ((uint32_t)word_at(b) << 16) | word_at(b + 2); pat_fetches++;
                top->pat_wr = 1; top->pat_idx = pat_n;
                if (++pat_n == top->pat_len) pat_last = true; else pat.cnt = 4;
            }
        } else pat.busy = false;
        serve(pcm,  top->pcm_req,  a, [&]() { uint32_t b = top->pcm_addr & 0xffffff; top->pcm_q = b < 0x200000 ? img[0x380000 + b] : 0; pcm_fetches++; }); top->pcm_ack = a;
        if (top->prog_ack) prog.busy = false; if (top->sub_ack) sub.busy = false; if (top->pat_ack) pat.busy = false; if (top->pcm_ack) pcm.busy = false;

        tick(); clocks++;

        // ---- video capture at the pixel enable
        if (top->cen_pix) {
            if (top->de) {
                if (!de_d) x = 0;
                if (x < 288 && y < 224) { size_t o = (y * 288 + x) * 3; frame[o] = top->rgb >> 16; frame[o + 1] = top->rgb >> 8; frame[o + 2] = top->rgb; }
                x++;
            } else if (de_d) y++;
            de_d = top->de;
            if (top->vsync && !vs_d) {
                if (snaps.count(frames) || (snaps.empty() && frames % 60 == 0)) {
                    char name[64]; snprintf(name, sizeof name, "/frame_%05ld.ppm", frames);
                    write_ppm(outdir + name, frame, 288, 224);
                }
                frames++; y = 0;
                if (frames % 10 == 0) {
                    printf("frame %ld: 68k@%06X h8 %s pc %06X instr %ld irqs %ld  fetches prog %ld sub %ld pat %ld pcm %ld%s%s\n",
                           frames, last_68k, top->dbg_h8_run ? "run" : "held", last_h8_pc, h8_instr, h8_irqs,
                           prog_fetches, sub_fetches, pat_fetches, pcm_fetches, unsup ? " UNSUPPORTED-VIDEO" : "", halted ? " 68K-HALTED" : "");
                    fflush(stdout);
                }
            }
            vs_d = top->vsync;
        }
        if (top->snd_valid) { audio.push_back(top->snd_l); audio.push_back(top->snd_r); }
        if (top->dbg_h8_istart) { h8_instr++; last_h8_pc = top->dbg_h8_pc; h8_ran = true; }
        if (top->dbg_h8_irq) h8_irqs++;
        if (top->dbg_video_unsupported) { if (!unsup) unsup_frame = frames; unsup = true; unsup_src |= top->dbg_video_unsup_src; }
        if (top->dbg_68k_halted) halted = true;
        last_68k = top->dbg_68k_addr << 1;
        if (clocks > 4000000000L) break;
    }
    write_wav(outdir + "/audio.wav", audio, 85333);
    printf("done: %ld frames, %ld clocks, h8 %ld instructions %ld irqs, audio %zu samples%s%s\n", frames, clocks, h8_instr, h8_irqs, audio.size() / 2,
           unsup ? " UNSUPPORTED-VIDEO" : "", halted ? " 68K-HALTED" : "");
    printf("C352 sample-tick overrun: %s\n", top->dbg_c352_overrun ? "YES" : "no");
    if (unsup) printf("unsupported video first at frame %ld, sources %s%s%s%s\n", unsup_frame, (unsup_src & 8) ? "rom-dma " : "", (unsup_src & 4) ? "roz-case " : "", (unsup_src & 2) ? "mosaic " : "", (unsup_src & 1) ? "render-overrun " : "");
    delete top;
    return 0;
}
