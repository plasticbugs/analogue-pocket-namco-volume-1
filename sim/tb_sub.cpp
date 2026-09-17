// Trace-replay bench for the whole sub CPU side: ncv1_sub (H8/3002 with its
// on-chip RAM, timers, interrupt controller, and the ND-1 address decode)
// against the same MAME capture as tb_h8, but with the on-chip parts modelled
// instead of replayed:
//   - internal RAM / I/O accesses are checked against the log (same address,
//     same data for reads AND writes) but served by the RTL;
//   - external accesses (shared RAM, C352, inputs) are replayed from the log;
//   - IRQ5 is driven on the pin where MAME's trace shows it being taken;
//     timer interrupts come from the RTL's own ITU, and are matched to the
//     trace's "(interrupted ...)" entries with a tolerance: while both sides
//     sit in the same spin loop, extra or missing loop iterations before the
//     interrupt are counted as drift and reported, not failed.
//
//   tb_sub <rom.rom> <artifacts/h8 dir> [max_instructions]
#include "Vncv1_sub.h"
#include "Vncv1_sub___024root.h"
#include "verilated.h"
#include <cstdio>
#include <cstdint>
#include <cstring>
#include <string>
#include <vector>
#include <deque>
#include <fstream>

struct Access { char dir; uint32_t addr; uint32_t data; };
struct TraceEnt { bool irq; uint32_t pc; int irqnum; };

static std::vector<uint8_t> rom;
static std::vector<TraceEnt> trace;
static std::vector<Access> accesses;

static bool load_file(const char *p, std::vector<uint8_t> &v) {
    FILE *f = fopen(p, "rb"); if (!f) return false;
    fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
    v.resize(n); size_t r = fread(v.data(), 1, n, f); fclose(f); return r == (size_t)n;
}
static bool is_internal(uint32_t a) { return a >= 0xfffd10; }

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    if (argc < 3) { fprintf(stderr, "usage: tb_sub rom dir [max]\n"); return 2; }
    std::string dir = argv[2];
    long max_instr = argc > 3 ? atol(argv[3]) : -1;

    std::vector<uint8_t> img;
    if (!load_file(argv[1], img) || img.size() < 0x180000) { fprintf(stderr, "bad rom image\n"); return 2; }
    rom.assign(img.begin() + 0x100000, img.begin() + 0x180000);
    {
        std::ifstream f(dir + "/h8trace.log"); std::string line;
        while (std::getline(f, line)) {
            if (line.empty()) continue;
            size_t p = line.find("(interrupted at ");
            if (p != std::string::npos) {
                uint32_t npc = strtoul(line.c_str() + p + 16, nullptr, 16);
                size_t q = line.find("IRQ ");
                int n = q != std::string::npos ? atoi(line.c_str() + q + 4) : -1;
                trace.push_back({true, npc, n});
            } else if (line.size() > 7 && line[6] == ':') trace.push_back({false, (uint32_t)strtoul(line.c_str(), nullptr, 16), 0});
        }
    }
    {
        std::ifstream f(dir + "/h8_access_log.txt"); std::string line;
        while (std::getline(f, line)) {
            if (line.compare(0, 3, "H8R") && line.compare(0, 3, "H8W")) continue;
            char tag[8]; unsigned long cyc, addr, data;
            if (sscanf(line.c_str(), "%7s %lu %lx %lx", tag, &cyc, &addr, &data) == 4)
                accesses.push_back({tag[2], (uint32_t)addr, (uint32_t)data});
        }
    }
    uint32_t er[8] = {0}; uint32_t ccr = 0;
    {
        std::ifstream f(dir + "/h8_regs.txt"); std::string name, val;
        while (f >> name >> val) {
            uint32_t v = strtoul(val.c_str(), nullptr, 16);
            if (name == "CCR") ccr = v;
            else if (name.size() == 3 && name[0] == 'E' && name[1] == 'R') er[name[2] - '0'] = v;
        }
    }
    std::vector<uint16_t> iram; { std::ifstream f(dir + "/h8_iram.txt"); std::string v; while (f >> v) iram.push_back(strtoul(v.c_str(), nullptr, 16)); }
    std::vector<uint8_t> io;    { std::ifstream f(dir + "/h8_io.txt");   std::string v; while (f >> v) io.push_back(strtoul(v.c_str(), nullptr, 16)); }
    printf("%zu trace entries, %zu accesses, iram %zu words, io %zu bytes\n", trace.size(), accesses.size(), iram.size(), io.size());
    if (trace.empty() || iram.size() != 256 || io.size() != 0xe0) { printf("FAIL: bad capture\n"); return 1; }

    Vncv1_sub *top = new Vncv1_sub;
    auto r = top->rootp;
    auto tick = [&](bool cen) { top->cen_h8 = cen; top->clk = 0; top->eval(); top->clk = 1; top->eval(); };
    top->reset = 1; top->rom_ack = 0; top->sh_ack = 0; top->c352_q = 0; top->dsw = 0xffff; top->p1p2 = 0xffff; top->irq5_n = 1;
    for (int i = 0; i < 4; i++) tick(true);
    top->reset = 0;
    // machine state
    uint32_t start_pc = trace[0].pc;
    for (int i = 0; i < 8; i++) r->ncv1_sub__DOT__mcu__DOT__cpu__DOT__core__DOT__er[i] = er[i];
    r->ncv1_sub__DOT__mcu__DOT__cpu__DOT__core__DOT__ccr = ccr;
    r->ncv1_sub__DOT__mcu__DOT__cpu__DOT__core__DOT__pc = start_pc;
    r->ncv1_sub__DOT__mcu__DOT__cpu__DOT__core__DOT__state = 3;
    for (int i = 0; i < 256; i++) { r->ncv1_sub__DOT__mcu__DOT__ram_hi[i] = iram[i] >> 8; r->ncv1_sub__DOT__mcu__DOT__ram_lo[i] = iram[i] & 0xff; }
    auto IO = [&](int a) { return io[a - 0x20]; };
    r->ncv1_sub__DOT__mcu__DOT__tstr = IO(0x60) & 0x1f;
    r->ncv1_sub__DOT__mcu__DOT__syscr = IO(0xf2); r->ncv1_sub__DOT__mcu__DOT__iscr = IO(0xf4);
    r->ncv1_sub__DOT__mcu__DOT__ier = IO(0xf5); r->ncv1_sub__DOT__mcu__DOT__isr = IO(0xf6);
    r->ncv1_sub__DOT__mcu__DOT__icr = (IO(0xf9) << 8) | IO(0xf8);
    r->ncv1_sub__DOT__mcu__DOT__adcsr = IO(0xe8); r->ncv1_sub__DOT__mcu__DOT__adc_run = (IO(0xe8) >> 5) & 1;
    const int chbase[5] = {0x64, 0x6e, 0x78, 0x82, 0x92};
    for (int c = 0; c < 5; c++) {
        int b = chbase[c];
        r->ncv1_sub__DOT__mcu__DOT__tcr[c] = IO(b); r->ncv1_sub__DOT__mcu__DOT__tier[c] = IO(b + 2) & 7;
        r->ncv1_sub__DOT__mcu__DOT__tflag[c] = IO(b + 3) & 7;
        r->ncv1_sub__DOT__mcu__DOT__tcnt[c] = (IO(b + 4) << 8) | IO(b + 5);
        r->ncv1_sub__DOT__mcu__DOT__gra[c] = (IO(b + 6) << 8) | IO(b + 7);
        r->ncv1_sub__DOT__mcu__DOT__grb[c] = (IO(b + 8) << 8) | IO(b + 9);
    }
    // ITU prescaler phase (h8_timer.txt: "<ch> <total cycles at the dump> <phase> <divider>"):
    // MAME counts on (cycles + phase) >> divider, so the RTL's free-running 3-bit
    // prescaler starts at (cycles + phase) mod 8
    {
        std::ifstream f(dir + "/h8_timer.txt"); unsigned long ch, cyc, ph, dv;
        if (f >> ch >> cyc >> ph >> dv) r->ncv1_sub__DOT__mcu__DOT__presc = (cyc + ph) & 7;
    }
    // port DDR/DR from the device state dump (h8_ports.txt: "<port> <ddr> <dr>")
    {
        std::ifstream f(dir + "/h8_ports.txt"); std::string pn, ddr, drs;
        while (f >> pn >> ddr >> drs) {
            uint8_t d = strtoul(ddr.c_str(), nullptr, 16), v = strtoul(drs.c_str(), nullptr, 16);
            switch (pn[0]) {
            case '4': r->ncv1_sub__DOT__mcu__DOT__ddr4 = d; r->ncv1_sub__DOT__mcu__DOT__dr4 = v; break;
            case '6': r->ncv1_sub__DOT__mcu__DOT__ddr6 = d; r->ncv1_sub__DOT__mcu__DOT__dr6 = v; break;
            case '8': r->ncv1_sub__DOT__mcu__DOT__ddr8 = d; r->ncv1_sub__DOT__mcu__DOT__dr8 = v; break;
            case '9': r->ncv1_sub__DOT__mcu__DOT__ddr9 = d; r->ncv1_sub__DOT__mcu__DOT__dr9 = v; break;
            case 'a': r->ncv1_sub__DOT__mcu__DOT__ddra = d; r->ncv1_sub__DOT__mcu__DOT__dra = v; break;
            case 'b': r->ncv1_sub__DOT__mcu__DOT__ddrb = d; r->ncv1_sub__DOT__mcu__DOT__drb = v; break;
            default: break;
            }
        }
    }
    top->eval();
    // if MAME took IRQ5 right at the start, present the pin now (CPU frozen) so the synchroniser sees it
    if (trace[0].irq && trace[0].irqnum == 5) { top->irq5_n = 0; for (int i = 0; i < 8; i++) tick(false); }
    // let the synchronised IRQ5 pin reach the controller
    for (int i = 0; i < 2; i++) tick(false);
    top->eval();

    size_t ti = 0, ai = 0; long ninstr = 0, nacc = 0, nint = 0, clocks = 0;
    long drift_extra = 0, drift_missing = 0, nirq = 0;
    std::deque<uint32_t> recent; uint32_t last_pc = 0;
    bool fail = false, req_seen = false; int pending_ack = 0;
    bool irq5_armed = false;
    last_pc = start_pc;

    auto next_is_irq = [&](int num) { return ti < trace.size() && trace[ti].irq && (num < 0 || trace[ti].irqnum == num); };
    // the vector of the interrupt the trace takes next: the handler is its next entry
    auto next_vector = [&]() -> int {
        if (!(ti < trace.size() && trace[ti].irq) || ti + 1 >= trace.size()) return -1;
        uint32_t handler = trace[ti + 1].pc;
        for (int v = 0; v < 64; v++) {
            uint32_t a = ((uint32_t)rom[4 * v] << 24) | ((uint32_t)rom[4 * v + 1] << 16) | ((uint32_t)rom[4 * v + 2] << 8) | rom[4 * v + 3];
            if ((a & 0xffffff) == handler) return v;
        }
        return -1;
    };
    // On-chip (ITU) interrupts are replayed at MAME's instruction, as sim/tb_h8.cpp replays
    // every interrupt. The ITU counts exactly as MAME's does, state for state, but where a
    // TCNT reload lands inside its own instruction cannot be recovered from a register
    // dump, and an overflow that falls a state or two either side of an instruction
    // boundary moves the interrupt by a whole instruction, after which the two machines
    // stack different state. So the pending bit is held back until MAME's instruction if
    // the RTL raises it first, and raised there if the RTL is a few states behind (its own
    // late copy is then dropped). Everything else stays exact, and the skew is reported
    // and bounded: more than IRQ_SKEW_MAX states fails.
    const long IRQ_SKEW_MAX = 16;
    enum { V_IDLE, V_HELD, V_TAKING, V_RAISED, V_DROP };
    int vst[64] = {0}; long vage[64] = {0}; bool vseen[64] = {false};
    long n_exact = 0, n_held = 0, n_forced = 0, worst_held = 0, worst_forced = 0;
    auto arm = [&]() {
        if (next_is_irq(5)) { top->irq5_n = 0; irq5_armed = true; }
    };
    if (trace[0].irq && trace[0].irqnum == 5) irq5_armed = true; else arm();

    // internal-access checking: watch the CPU bus for accesses to fffd10+ and compare with the log
    bool int_seen = false; bool dbgp = false; int dbgn = 0;

    unsigned cen_acc = 0;             // the H8 enable as rtl/clk_enables.sv makes it: 16.384 of 96 MHz
    while (!fail) {
        cen_acc += 64; bool cen = false;
        if (cen_acc >= 375) { cen_acc -= 375; cen = true; }
        // external bus model
        top->rom_ack = 0; top->sh_ack = 0;
        bool ext_req = top->rom_req || top->sh_req;
        uint32_t ba = top->dbg_bus_addr & 0xffffff;
        bool ext_other = (top->dbg_bus_rd || top->dbg_bus_wr) && !is_internal(ba) && !top->rom_req && !top->sh_req;   // C352 / inputs / other
        if (ext_req) {
            if (!req_seen) { req_seen = true; pending_ack = 1; }
            else if (pending_ack > 0 && --pending_ack == 0) {
                if (top->rom_req) {
                    uint32_t ae = (top->rom_addr << 1) & 0x7fffe;
                    top->rom_q = ((uint32_t)rom[ae] << 8) | rom[ae + 1];
                    top->rom_ack = 1;
                } else {
                    // shared RAM: replay
                    nacc++;
                    if (ai >= accesses.size()) { printf("FAIL: log exhausted\n"); fail = true; break; }
                    const Access &x = accesses[ai++];
                    uint32_t a = 0x200000 | (top->sh_addr << 1) | (top->dbg_bus_word ? 0 : (ba & 1));
                    char dir = top->sh_we ? 'W' : 'R';
                    bool ok = (x.dir == dir) && (x.addr == a);
                    if (ok && dir == 'W') {
                        uint32_t d = top->dbg_bus_word ? (top->sh_wdata & 0xffff) : (top->sh_wdata & 0xff);
                        uint32_t ld = top->dbg_bus_word ? (x.data & 0xffff) : (x.data & 0xff);
                        if (d != ld) ok = false;
                    }
                    if (!ok) { printf("FAIL at instr %ld pc %06X: RTL shared %c %06X data %04X, log %c %06X data %04X\n", ninstr, last_pc, dir, a, top->sh_wdata, x.dir, x.addr, x.data); fail = true; break; }
                    if (dir == 'R') top->sh_q = top->dbg_bus_word ? (x.data & 0xffff) : ((a & 1) ? (x.data & 0xff) : ((x.data & 0xff) << 8));
                    top->sh_ack = 1;
                }
            }
        } else req_seen = false;
        // C352 and inputs: the sub decoder acks these itself; replay their data through c352_q / ports
        if (ext_other && !int_seen) {
            // one log entry per access: consume when the RTL's ack for it appears (dbg_bus_ack)
        }

        if (getenv("NCV1_VERBOSE") && ba >= 0xc00000 && ba < 0xc00100 && dbgn < 6) { dbgn++; printf("see instr %ld: addr %06X rd %d wr %d ack %d word %d\n", ninstr, ba, top->dbg_bus_rd, top->dbg_bus_wr, top->dbg_bus_ack, top->dbg_bus_word); }
        if (getenv("NCV1_VERBOSE") && ba >= 0xc00000 && ba < 0xc00100 && (top->dbg_bus_rd || top->dbg_bus_wr) && !dbgp) { dbgp = true; printf("bus instr %ld: %s %06X word %d rdata %04X ack %d (log[%zu] %c %06X %04X)\n", ninstr, top->dbg_bus_rd ? "R" : "W", ba, top->dbg_bus_word, top->dbg_bus_rdata, top->dbg_bus_ack, ai, ai < accesses.size() ? accesses[ai].dir : '-', ai < accesses.size() ? accesses[ai].addr : 0, ai < accesses.size() ? accesses[ai].data : 0); }
        if (!(top->dbg_bus_rd || top->dbg_bus_wr)) dbgp = false;
        // supply replayed data for C352 / input reads before the access is acknowledged: peek the log
        if ((top->dbg_bus_rd) && !is_internal(ba) && ((ba >= 0xa00000 && ba < 0xa08000) || (ba >= 0xc00000 && ba < 0xc00100)) && ai < accesses.size()) {
            const Access &x = accesses[ai];
            uint32_t want = top->dbg_bus_word ? (ba & ~1u) : ba;
            if (x.dir == 'R' && x.addr == want) {
                uint32_t v = top->dbg_bus_word ? (x.data & 0xffff) : ((ba & 1) ? (x.data & 0xff) : ((x.data & 0xff) << 8));
                top->c352_q = v; if (ba >= 0xc00000) { if ((ba & 0xff) < 2) top->dsw = v; else top->p1p2 = v; }
                if (getenv("NCV1_VERBOSE") && ba >= 0xc00000 && ninstr > 200380) printf("peek instr %ld: rd %06X word %d <- log[%zu] %c %06X %04X -> v %04X\n", ninstr, ba, top->dbg_bus_word, ai, x.dir, x.addr, x.data, v);
            } else if (getenv("NCV1_VERBOSE") && ba >= 0xc00000 && ninstr > 200380) printf("peek instr %ld: rd %06X but log[%zu] is %c %06X %04X\n", ninstr, ba, ai, x.dir, x.addr, x.data);
        }

        // the ADC flag phase is not in the dump: follow MAME's value for each ADCSR read
        if (top->dbg_bus_rd && ba == 0xffffe8 && ai < accesses.size() && accesses[ai].dir == 'R' && accesses[ai].addr == 0xffffe8)
            r->ncv1_sub__DOT__mcu__DOT__adcsr = (r->ncv1_sub__DOT__mcu__DOT__adcsr & 0x7f) | (accesses[ai].data & 0x80);

        if (cen) {
            uint64_t pend = r->ncv1_sub__DOT__mcu__DOT__pend;
            int want = next_vector();                            // >= 24: an ITU vector is due at this instruction
            // while the CPU masks interrupts (CCR I) a pending one waits in both machines: not skew
            bool masked = (r->ncv1_sub__DOT__mcu__DOT__cpu__DOT__core__DOT__ccr >> 7) & 1;
            for (int v = 24; v < 44; v++) {
                uint64_t bit = 1ULL << v;
                int c = (v - 24) / 4, k = (v - 24) % 4;
                bool flag = k < 3 && ((r->ncv1_sub__DOT__mcu__DOT__tflag[c] >> k) & 1);   // the ITU's own event
                switch (vst[v]) {
                case V_IDLE:
                    if (v == want) {
                        if (pend & bit) { n_exact++; vst[v] = V_TAKING; }
                        else { pend |= bit; n_forced++; vage[v] = 0; vseen[v] = flag; vst[v] = V_RAISED; }
                    } else if (pend & bit) { pend &= ~bit; vage[v] = 0; vst[v] = V_HELD; }        // RTL first: hold it back
                    break;
                case V_HELD:
                    if (v == want) { pend |= bit; n_held++; if (vage[v] > worst_held) worst_held = vage[v]; vst[v] = V_TAKING; }
                    else if (!masked && ++vage[v] > IRQ_SKEW_MAX) { printf("FAIL: vector %d pending %ld states before MAME takes it (instr %ld)\n", v, vage[v], ninstr); fail = true; }
                    break;
                case V_TAKING:                                       // until the core has taken it
                    if (v != want) vst[v] = V_IDLE;
                    break;
                case V_RAISED:                                       // raised for MAME; the ITU's own event is still to come
                    if (!vseen[v]) {
                        if (flag) { vseen[v] = true; if (vage[v] > worst_forced) worst_forced = vage[v]; }
                        else if (++vage[v] > IRQ_SKEW_MAX) { printf("FAIL: vector %d taken by MAME, the RTL's own event %ld states later still missing (instr %ld)\n", v, vage[v], ninstr); fail = true; }
                    }
                    if (v != want) {                                 // taken
                        if (vseen[v]) vst[v] = V_IDLE;
                        else vst[v] = V_DROP;
                    }
                    break;
                case V_DROP:                                         // taken before the ITU's own event: drop that copy
                    if (pend & bit) { pend &= ~bit; if (vage[v] > worst_forced) worst_forced = vage[v]; vst[v] = V_IDLE; }
                    else if (++vage[v] > IRQ_SKEW_MAX) { printf("FAIL: vector %d taken by MAME, the RTL's own event never came (instr %ld)\n", v, ninstr); fail = true; }
                    break;
                }
            }
            r->ncv1_sub__DOT__mcu__DOT__pend = pend;
            if (fail) break;
        }
        tick(cen);
        clocks++;
        if (top->rom_ack || top->sh_ack) req_seen = false;

        // internal and other accesses complete with dbg_bus_ack: compare with the log there
        if (top->dbg_bus_ack && !top->rom_req && !top->sh_req) {
            uint32_t a = ba; bool word = top->dbg_bus_word;
            if (is_internal(a) || (a >= 0xa00000 && a < 0xa08000) || (a >= 0xc00000 && a < 0xc00100)) {
                nacc++; if (is_internal(a)) nint++;
                if (ai >= accesses.size()) { printf("FAIL: log exhausted at %06X\n", a); fail = true; break; }
                const Access &x = accesses[ai++];
                char dir = top->dbg_bus_wr ? 'W' : 'R';
                uint32_t cmp_addr = word ? (a & ~1u) : a;
                bool ok = (x.dir == dir) && (x.addr == cmp_addr);
                uint32_t d = dir == 'W' ? top->dbg_bus_wdata : top->dbg_bus_rdata;
                if (!word) d = (a & 1) ? (d & 0xff) : (dir == 'W' ? (d & 0xff) : (d >> 8) & 0xff);
                uint32_t ld = word ? (x.data & 0xffff) : (x.data & 0xff);
                // the ADC status flag (ADCSR bit 7) depends on a conversion phase the dump cannot restore
                if (a == 0xffffe8) { d &= 0x7f; ld &= 0x7f; }
                if (ok && is_internal(a) && d != ld) ok = false;              // RTL-served: data must match
                if (ok && dir == 'W' && d != ld) ok = false;
                if (!ok) { printf("FAIL at instr %ld pc %06X: RTL %c %06X %s data %04X, log %c %06X data %04X\n", ninstr, last_pc, dir, a, word ? "word" : "byte", d, x.dir, x.addr, x.data); fail = true; break; }
            }
        }
        if (top->dbg_irq) {
            nirq++;
            if (getenv("NCV1_VERBOSE")) printf("irq: RTL instr %ld npc %06X (trace idx %zu, trace next %s%06X, tcnt0 %04X, isr %02X, clocks %ld)\n",
                ninstr, top->dbg_npc, ti, trace[ti].irq ? "irq@" : "", trace[ti].pc, r->ncv1_sub__DOT__mcu__DOT__tcnt[0], r->ncv1_sub__DOT__mcu__DOT__isr, clocks);
            // find the matching trace entry, tolerating spin-loop drift
            if (!next_is_irq(-1)) {
                // RTL is early: skip trace entries that repeat the last executed PC (spin loop)
                long skipped = 0;
                while (ti < trace.size() && !trace[ti].irq && trace[ti].pc == last_pc) { ti++; skipped++; }
                drift_extra += skipped;
                if (!next_is_irq(-1)) { printf("FAIL: unexpected interrupt at instr %ld (npc %06X), trace next %06X\n", ninstr, top->dbg_npc, ti < trace.size() ? trace[ti].pc : 0); fail = true; break; }
            }
            if ((top->dbg_npc & 0xffffff) != trace[ti].pc) { printf("FAIL: interrupt npc %06X, MAME %06X (instr %ld)\n", top->dbg_npc, trace[ti].pc, ninstr); fail = true; break; }
            if (irq5_armed) { top->irq5_n = 1; irq5_armed = false; }
            ti++;
            arm();
        }
        if (top->dbg_istart) {
            if (ti >= trace.size()) break;
            if (trace[ti].irq) {
                // RTL is late: allow spin-loop iterations before the interrupt
                if ((top->dbg_pc & 0xffffff) == last_pc && drift_missing < 200000) { drift_missing++; ninstr++; clocks++; continue; }
                printf("FAIL: MAME took IRQ %d before %06X, RTL executed %06X instead (instr %ld)\n", trace[ti].irqnum, trace[ti].pc, top->dbg_pc, ninstr); fail = true; break;
            }
            if ((top->dbg_pc & 0xffffff) != trace[ti].pc) {
                // a timing-dependent poll loop (the ADC flag, say): if the RTL is still in the loop MAME
                // already left, let it spin; if MAME spins longer, skip its extra iterations
                uint32_t rpc = top->dbg_pc & 0xffffff;
                bool in_loop = false; for (uint32_t p : recent) if (p == rpc) in_loop = true;
                if (in_loop && drift_missing < 2000000) { drift_missing++; ninstr++; continue; }
                size_t k = ti; bool resync = false;
                while (k < trace.size() && k < ti + 200000 && !trace[k].irq) {
                    bool tin = false; for (uint32_t p : recent) if (p == trace[k].pc) tin = true;
                    if (!tin) break;
                    k++;
                    if (k < trace.size() && !trace[k].irq && trace[k].pc == rpc) { resync = true; break; }
                }
                if (resync) { drift_extra += (long)(k - ti); ti = k; }
            }
            if ((top->dbg_pc & 0xffffff) != trace[ti].pc) {
                printf("FAIL at instr %ld: RTL pc %06X, trace pc %06X\n  recent:", ninstr, top->dbg_pc, trace[ti].pc);
                for (uint32_t p : recent) printf(" %06X", p);
                printf("\n  trace:"); for (size_t k = (ti > 5 ? ti - 5 : 0); k < ti + 3 && k < trace.size(); k++) printf(" %s%06X", trace[k].irq ? "irq@" : "", trace[k].pc);
                printf("\n"); fail = true; break;
            }
            last_pc = top->dbg_pc; recent.push_back(last_pc); if (recent.size() > 12) recent.pop_front();
            ti++; ninstr++;
            arm();
            if (max_instr > 0 && ninstr >= max_instr) break;
        }
        if (clocks > 2000000000L) { printf("FAIL: timeout\n"); fail = true; }
    }
    printf("ITU interrupts: %ld on MAME's state, %ld held back (worst %ld states), %ld raised early (worst %ld states)\n",
           n_exact, n_held, worst_held, n_forced, worst_forced);
    printf("%ld instructions, %ld accesses checked (%ld on-chip), %ld interrupts, drift: RTL early by %ld loop iterations, late by %ld\n",
           ninstr, nacc, nint, nirq, drift_extra, drift_missing);
    printf(fail ? "FAIL\n" : "PASS\n");
    delete top;
    return fail ? 1 : 0;
}
