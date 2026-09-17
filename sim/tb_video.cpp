// YGV608 frozen-state bench (docs/core-design.md section 3.3).
//
// Loads a state file written by tools/dump_state.lua into the VDP through
// its 68000 port interface -- register select + register data writes, and the
// four tables through the data ports with auto-increment, the way the game
// itself fills them -- then renders one full frame with the pattern ROM behind
// a memory model of random latency, captures the 288x224 RGB raster during DE,
// writes it as a PPM and reports the renderer's worst line and the FV IRQ
// timing. The comparison against tools/render_model.py is done by
// sim/run_video.sh.
//
//   tb_video <state.txt> <ncv1.rom> <out.ppm>
#include "Vtb_video_top.h"
#include "verilated.h"
#include <cstdio>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>
#include <map>
#include <fstream>
#include <sstream>

static const int W = 288, H = 224;

struct State {
    std::map<std::string, uint32_t> s;
    std::map<std::string, std::vector<uint32_t>> a;
    uint32_t get(const char *n) const { auto it = s.find(n); return it == s.end() ? 0 : it->second; }
};

static bool load_state(const char *path, State &st) {
    std::ifstream f(path);
    if (!f) return false;
    std::string line;
    std::vector<std::string> lines;
    while (std::getline(f, line)) lines.push_back(line);
    size_t i = 0;
    while (i < lines.size()) {
        std::string ln = lines[i++];
        if (ln.empty()) continue;
        size_t sp = ln.find(' ');
        std::string name = ln.substr(0, sp), rest = ln.substr(sp + 1);
        if (name.size() > 2 && name.compare(name.size() - 2, 2, "[]") == 0) {
            std::istringstream is(rest); size_t count, size; is >> count >> size;
            std::vector<uint32_t> vals;
            while (vals.size() < count && i < lines.size()) {
                std::istringstream vs(lines[i++]); std::string tok;
                while (vs >> tok) vals.push_back(strtoul(tok.c_str(), nullptr, 16));
            }
            st.a[name.substr(0, name.size() - 2)] = vals;
        } else if (name == "frame") {
            st.s["frame"] = strtoul(rest.c_str(), nullptr, 10);
        } else st.s[name] = strtoul(rest.c_str(), nullptr, 16);
    }
    return true;
}

static Vtb_video_top *top;
static std::vector<uint8_t> rom;   // 2 MB pattern ROM
static long clocks = 0;
static int pix_div = 0;
static int lat = 0; static bool pat_busy = false; static int pat_n = 0; static bool pat_last = false;
static long pat_units = 0, pat_reqs = 0;
static unsigned rng = 12345;
static unsigned rnd() { rng = rng * 1103515245u + 12345u; return (rng >> 16) & 0x7fff; }

static void tick() {
    // pattern ROM model, SDRAM-like: the first unit 4..12 clocks after the request
    // appears, each further unit of a burst 4 clocks later (two SDRAM words at one
    // READ every 2 clocks), the ack one clock after the last
    top->pat_ack = 0; top->pat_wr = 0;
    if (top->pat_req) {
        if (!pat_busy) { pat_busy = true; lat = 4 + rnd() % 9; pat_n = 0; pat_last = false; pat_reqs++; }
        else if (pat_last) { top->pat_ack = 1; pat_busy = false; }
        else if (--lat == 0) {
            uint32_t a = ((top->pat_addr + pat_n) * 4) & 0x1fffff;
            top->pat_q = ((uint32_t)rom[a] << 24) | ((uint32_t)rom[a + 1] << 16) | ((uint32_t)rom[a + 2] << 8) | rom[a + 3];
            top->pat_wr = 1; top->pat_idx = pat_n; pat_units++;
            if (++pat_n == top->pat_len) pat_last = true; else lat = 4;
        }
    } else pat_busy = false;
    top->cen_pix = (pix_div == 0);
    pix_div = (pix_div + 1) % 15;
    top->clk = 0; top->eval();
    top->clk = 1; top->eval();
    clocks++;
}

static void port_write(int sel, int data) {
    top->port_sel = sel; top->port_wdata = data & 0xff; top->port_wr = 1;
    tick();
    top->port_wr = 0;
    tick(); tick();
}
static void reg_write(int rn, int data) { port_write(5, rn & 0x3f); port_write(4, data); }

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    if (argc < 4) { fprintf(stderr, "usage: tb_video state.txt ncv1.rom out.ppm\n"); return 2; }
    State st;
    if (!load_state(argv[1], st)) { fprintf(stderr, "cannot read %s\n", argv[1]); return 2; }
    {
        FILE *f = fopen(argv[2], "rb"); if (!f) { fprintf(stderr, "cannot read %s\n", argv[2]); return 2; }
        fseek(f, 0x180000, SEEK_SET); rom.resize(0x200000);
        if (fread(rom.data(), 1, rom.size(), f) != rom.size()) { fprintf(stderr, "short rom\n"); return 2; }
        fclose(f);
    }
    top = new Vtb_video_top;
    top->reset = 1; top->port_wr = 0; top->port_rd = 0; top->pat_ack = 0; top->gfxbank = st.get("m_namcond1_gfxbank") & 3;
    for (int i = 0; i < 8; i++) tick();
    top->reset = 0;
    for (int i = 0; i < 4; i++) tick();

    // ---- registers (mode first, since R#0/1 masks depend on the page size)
    reg_write(7, (st.get("m_dckm") << 7) | (st.get("m_flip") << 6) | (st.get("m_zron") << 3) | (st.get("m_md") << 1) | st.get("m_dspe"));
    reg_write(8, (st.get("m_h_display_size") << 6) | (st.get("m_v_display_size") << 4) | (st.get("m_roz_wrap_disable") << 3) |
                 (st.get("m_scroll_wrap_disable") << 2) | st.get("m_page_size"));
    reg_write(9, (st.get("m_pattern_size") << 6) | (st.get("m_h_div_size") << 3) | st.get("m_v_div_size"));
    reg_write(10, (st.get("m_sprite_aux_reg") << 6) | (st.get("m_sprite_aux_mode") << 5) | (st.get("m_sprite_disable") << 4) |
                  (st.get("m_mosaic_bplane") << 2) | st.get("m_mosaic_aplane"));
    reg_write(11, (st.get("m_scm") << 6) | (st.get("m_yse") << 5) | (st.get("m_cbdr") << 4) | (st.get("m_priority_mode") << 2) |
                  (st.get("m_planeB_trans_enable") << 1) | st.get("m_planeA_trans_enable"));
    reg_write(12, (st.get("m_sprite_color_fetch") << 6) | (st.get("m_planeB_color_fetch") << 3) | st.get("m_planeA_color_fetch"));
    reg_write(13, st.get("m_border_color"));
    // the vblank IRQ is always enabled here so its timing can be checked (it does not affect the picture)
    reg_write(14, (st.get("m_raster_irq_mask") << 1) | 1);
    reg_write(15, st.get("m_raster_irq_vpos") & 0xff);
    reg_write(16, (st.get("m_raster_irq_mode") << 7) | (((st.get("m_raster_irq_vpos") >> 8) & 1) << 6) | ((st.get("m_raster_irq_hpos") / 32) & 0x1f));
    reg_write(6, st.get("m_sprite_bank"));
    // ROZ: R#25-27 AX, 28-29 DX, 30-31 DXY, 32-34 AY, 35-36 DY, 37-38 DYX, low byte first (MAME m_raw_*)
    {
        uint32_t ax = st.get("m_raw_ax"), dx = st.get("m_raw_dx"), dxy = st.get("m_raw_dxy");
        uint32_t ay = st.get("m_raw_ay"), dy = st.get("m_raw_dy"), dyx = st.get("m_raw_dyx");
        reg_write(25, ax & 0xff); reg_write(26, (ax >> 8) & 0xff); reg_write(27, (ax >> 16) & 0xff);
        reg_write(28, dx & 0xff); reg_write(29, (dx >> 8) & 0xff);
        reg_write(30, dxy & 0xff); reg_write(31, (dxy >> 8) & 0xff);
        reg_write(32, ay & 0xff); reg_write(33, (ay >> 8) & 0xff); reg_write(34, (ay >> 16) & 0xff);
        reg_write(35, dy & 0xff); reg_write(36, (dy >> 8) & 0xff);
        reg_write(37, dyx & 0xff); reg_write(38, (dyx >> 8) & 0xff);
    }
    const auto &ba = st.a["m_base_addr"];
    for (int k = 0; k < 8; k++) reg_write(17 + k, (ba[2 * k] & 7) | ((ba[2 * k + 1] & 7) << 4));
    {
        uint32_t htotal = st.get("m_crtc.htotal"), vtotal = st.get("m_crtc.vtotal");
        reg_write(39, ((st.get("m_crtc.display_hsync") / 16) << 5) | (st.get("m_crtc.border_width") / 16));
        reg_write(40, ((htotal >> 3) & 0xc0) | (st.get("m_crtc.display_width") / 16));
        reg_write(41, (st.get("m_crtc.display_hstart") >> 1) & 0xff);
        reg_write(42, (htotal >> 1) & 0xff);
        reg_write(43, (st.get("m_crtc.display_vsync") << 5) | (st.get("m_crtc.border_height") / 8));
        reg_write(44, st.get("m_crtc.display_height") / 8);
        reg_write(45, (((vtotal >> 8) & 1) << 7) | st.get("m_crtc.display_vstart"));
        reg_write(46, vtotal & 0xff);
    }
    // ---- tables through the data ports with auto-increment
    reg_write(2, 0xcf);                       // all auto-increments on, scroll plane A
    reg_write(3, 0); reg_write(4, 0); reg_write(5, 0);
    const auto &sdt = st.a["m_scroll_data_table"];
    for (size_t i = 0; i < 512; i++) port_write(2, sdt[i]);
    const auto &sat = st.a["m_sprite_attribute_table.b"];
    for (size_t i = 0; i < 256; i++) port_write(1, sat[i]);
    const auto &pal = st.a["m_colour_palette"];
    for (size_t i = 0; i < 768; i++) port_write(3, pal[i]);
    reg_write(0, 0x00);                       // y = 0, no y auto-increment, plane A
    reg_write(1, 0x80);                       // x = 0, x auto-increment
    const auto &pnt = st.a["m_pattern_name_table"];
    for (size_t i = 0; i < 4096; i++) port_write(0, pnt[i]);
    // the game's own pointer/flag state (not needed for rendering, kept for the port read-backs)
    reg_write(2, (st.get("m_cpaw") << 7) | (st.get("m_cpar") << 6) | (st.get("m_ba_plane_scroll_select") << 4) |
                 (st.get("m_scaw") << 3) | (st.get("m_scar") << 2) | (st.get("m_saaw") << 1) | st.get("m_saar"));

    // ---- wait for the frame start, then clear the FV the raster raised while loading
    while (!(top->line == 0 && top->dot == 0 && top->cen_pix)) tick();
    port_write(6, 0x18);
    // ---- capture one frame
    std::vector<uint8_t> img(W * H * 3, 0);
    int px = 0, py = 0; long npix = 0; bool overflow = false;
    int fv_line = -1, fv_dot = -1; bool fv_seen = false; bool prev_irq = top->irq_vblank;
    bool started = false;
    while (true) {
        tick();
        if (top->cen_pix) {
            // outputs now describe the dot processed at the previous cen_pix
            if (top->de) {
                if (!started) { started = true; px = 0; py = 0; }
                if (py < H) { img[(py * W + px) * 3] = top->r; img[(py * W + px) * 3 + 1] = top->g; img[(py * W + px) * 3 + 2] = top->b; }
                npix++;
                if (++px == W) { px = 0; py++; }
                if (py > H) overflow = true;
            }
            if (top->irq_vblank && !prev_irq && !fv_seen) { fv_seen = true; fv_line = top->line; fv_dot = top->dot; }
            prev_irq = top->irq_vblank;
            // the picture is complete after line 249; run on to see the FV at line 250
            if (started && py >= H && (fv_seen || (top->line == 0 && top->dot == 0))) break;
        }
        if (clocks > 20000000L) { printf("FAIL: timeout\n"); return 1; }
    }
    // the FV line clears with a status write
    port_write(6, 0x08);
    bool fv_cleared = !top->irq_vblank;

    FILE *o = fopen(argv[3], "wb");
    fprintf(o, "P6\n%d %d\n255\n", W, H);
    fwrite(img.data(), 1, img.size(), o);
    fclose(o);
    printf("frame: %ld pixels captured%s, worst line %u clocks (last %u), overrun %d, unsupported %d, pattern requests %ld units %ld\n",
           npix, overflow ? " (OVERFLOW)" : "", top->max_clocks, top->line_clocks, top->overrun, top->unsupported, pat_reqs, pat_units);
    printf("FV irq: asserted at line %d dot %d (expect 250, 0), cleared by status write: %s\n", fv_line, fv_dot, fv_cleared ? "yes" : "NO");
    bool ok = (npix == (long)W * H) && !overflow && fv_line == 250 && fv_dot == 0 && fv_cleared && !top->overrun && !top->unsupported;
    printf("%s\n", ok ? "BENCH-OK" : "BENCH-FAIL");
    delete top;
    return ok ? 0 : 1;
}
