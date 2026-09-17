// Trace-replay bench for the H8/300H core (docs/core-design.md section 3.2).
//
// Loads the sub program from the ROM image, the MAME register dump, the
// instruction trace and the non-ROM access log captured by tools/trace_h8.lua,
// then runs the RTL: every instruction start must hit the trace's next PC,
// every non-ROM access must be the log's next access (same direction, address
// and, for writes, data; reads are answered from the log), and interrupts are
// injected where MAME took them.
//
//   tb_h8 <rom.rom> <artifacts/h8 dir> [max_instructions]
#include "Vh8300h.h"
#include "Vh8300h___024root.h"
#include "verilated.h"
#include <cstdio>
#include <cstdint>
#include <cstring>
#include <string>
#include <vector>
#include <deque>
#include <fstream>
#include <sstream>

struct Access { char dir; uint32_t addr; uint32_t data; };
struct TraceEnt { bool irq; uint32_t pc; };   // irq: pc = NPC of the "interrupted at" line

static std::vector<uint8_t> rom;
static std::vector<TraceEnt> trace;
static std::vector<Access> accesses;

static bool load_file(const char *p, std::vector<uint8_t> &v) {
    FILE *f = fopen(p, "rb"); if (!f) return false;
    fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
    v.resize(n); size_t r = fread(v.data(), 1, n, f); fclose(f); return r == (size_t)n;
}

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    if (argc < 3) { fprintf(stderr, "usage: tb_h8 rom dir [max]\n"); return 2; }
    std::string dir = argv[2];
    long max_instr = argc > 3 ? atol(argv[3]) : -1;

    std::vector<uint8_t> img;
    if (!load_file(argv[1], img) || img.size() < 0x180000) { fprintf(stderr, "bad rom image\n"); return 2; }
    rom.assign(img.begin() + 0x100000, img.begin() + 0x180000);

    // trace
    {
        std::ifstream f(dir + "/h8trace.log");
        std::string line;
        while (std::getline(f, line)) {
            if (line.empty()) continue;
            size_t p = line.find("(interrupted at ");
            if (p != std::string::npos) {
                uint32_t npc = strtoul(line.c_str() + p + 16, nullptr, 16);
                trace.push_back({true, npc});
            } else if (line.size() > 7 && line[6] == ':') {
                trace.push_back({false, (uint32_t)strtoul(line.c_str(), nullptr, 16)});
            }
        }
    }
    // access log
    {
        std::ifstream f(dir + "/h8_access_log.txt");
        std::string line;
        while (std::getline(f, line)) {
            if (line.compare(0, 3, "H8R") && line.compare(0, 3, "H8W")) continue;
            char tag[8]; unsigned long cyc, addr, data;
            if (sscanf(line.c_str(), "%7s %lu %lx %lx", tag, &cyc, &addr, &data) == 4)
                accesses.push_back({tag[2], (uint32_t)addr, (uint32_t)data});
        }
    }
    // registers
    uint32_t er[8] = {0}; uint32_t ccr = 0;
    {
        std::ifstream f(dir + "/h8_regs.txt");
        std::string name; std::string val;
        while (f >> name >> val) {
            uint32_t v = strtoul(val.c_str(), nullptr, 16);
            if (name == "CCR") ccr = v;
            else if (name.size() == 3 && name[0] == 'E' && name[1] == 'R') er[name[2] - '0'] = v;
        }
    }
    printf("rom %zu bytes, %zu trace entries, %zu accesses\n", rom.size(), trace.size(), accesses.size());
    if (trace.empty()) { printf("FAIL: empty trace\n"); return 1; }

    Vh8300h *top = new Vh8300h;
    auto tick = [&](bool cen) {
        top->cen = cen ? 1 : 0;
        top->clk = 0; top->eval();
        top->clk = 1; top->eval();
    };
    // reset
    top->reset = 1; top->bus_ack = 0; top->bus_rdata = 0; top->irq_vector = 0;
    for (int i = 0; i < 4; i++) tick(true);
    top->reset = 0;
    // load the machine state: registers, PC from the trace, and skip the reset vector fetch
    uint32_t start_pc = trace[0].pc;
    for (int i = 0; i < 8; i++) top->rootp->h8300h__DOT__core__DOT__er[i] = er[i];
    top->rootp->h8300h__DOT__core__DOT__ccr = ccr;
    top->rootp->h8300h__DOT__core__DOT__pc = start_pc;
    top->rootp->h8300h__DOT__core__DOT__state = 3;   // S_FETCH
    top->eval();

    size_t ti = 0, ai = 0;
    long ninstr = 0, nacc = 0;
    std::deque<uint32_t> recent;
    bool irq_armed = false; uint32_t irq_npc = 0; uint8_t irq_vec = 0;
    bool fail = false;
    int pending_ack = 0;      // clocks until the current bus request is acknowledged
    bool req_seen = false;
    long clocks = 0;

    auto arm_irq_if_next = [&]() {
        if (ti < trace.size() && trace[ti].irq) {
            // the handler address is the next non-irq entry; find its vector
            uint32_t handler = (ti + 1 < trace.size()) ? trace[ti + 1].pc : 0;
            int vec = -1;
            for (int v = 0; v < 64; v++) {
                uint32_t a = ((uint32_t)rom[4 * v] << 24) | ((uint32_t)rom[4 * v + 1] << 16) | ((uint32_t)rom[4 * v + 2] << 8) | rom[4 * v + 3];
                if ((a & 0xffffff) == handler) { vec = v; break; }
            }
            if (vec < 0) { printf("FAIL: no vector points at handler %06X\n", handler); fail = true; return; }
            irq_armed = true; irq_npc = trace[ti].pc; irq_vec = vec;
            top->irq_vector = vec;
        }
    };
    arm_irq_if_next();
    top->eval();
    unsigned cen_acc = 0;             // the H8 enable as rtl/clk_enables.sv makes it: 16.384 of 96 MHz
    // H8_CYCLES=<file>: per executed instruction (and interrupt entry), the H8
    // states it took, "<trace index> <pc> <states>", for cost comparisons with MAME
    FILE *cyc_f = getenv("H8_CYCLES") ? fopen(getenv("H8_CYCLES"), "w") : nullptr;
    long cens = 0, cyc_ti = -1; uint32_t cyc_pc = 0;

    while (!fail && !Verilated::gotFinish()) {
        cen_acc += 64; bool cen = false;
        if (cen_acc >= 375) { cen_acc -= 375; cen = true; }
        // bus model: answer a request one clock after seeing it
        top->bus_ack = 0;
        if ((top->bus_rd || top->bus_wr)) {
            if (!req_seen) { req_seen = true; pending_ack = 1; }
            else if (pending_ack > 0 && --pending_ack == 0) {
                uint32_t a = top->bus_addr & 0xffffff;
                bool word = top->bus_word;
                if (a < 0x80000 && top->bus_rd) {
                    uint32_t ae = a & ~1u;
                    top->bus_rdata = ((uint32_t)rom[ae] << 8) | rom[ae + 1];
                } else {
                    nacc++;
                    if (ai >= accesses.size()) { printf("FAIL: access log exhausted at %s %06X\n", top->bus_rd ? "R" : "W", a); fail = true; break; }
                    const Access &x = accesses[ai++];
                    char dir = top->bus_rd ? 'R' : 'W';
                    uint32_t cmp_addr = word ? (a & ~1u) : a;
                    bool ok = (x.dir == dir) && (x.addr == cmp_addr);
                    if (ok && dir == 'W') {
                        uint32_t d = word ? (top->bus_wdata & 0xffff) : (top->bus_wdata & 0xff);
                        uint32_t ld = word ? (x.data & 0xffff) : (x.data & 0xff);
                        if (d != ld) ok = false;
                    }
                    if (!ok) {
                        printf("FAIL at instr %ld (trace idx %zu, pc %06X): RTL %c %06X %s data %04X, log %c %06X data %04X\n",
                               ninstr, ti, recent.empty() ? 0 : recent.back(), dir, a, word ? "word" : "byte",
                               top->bus_wr ? top->bus_wdata : 0, x.dir, x.addr, x.data);
                        fail = true; break;
                    }
                    if (dir == 'R') {
                        if (word) top->bus_rdata = x.data & 0xffff;
                        else top->bus_rdata = (a & 1) ? (x.data & 0xff) : ((x.data & 0xff) << 8);
                    }
                }
                top->bus_ack = 1;
            }
        } else req_seen = false;

        tick(cen);
        clocks++;
        if (cen) cens++;
        if (top->bus_ack) req_seen = false;
        if (cyc_f && (top->dbg_istart || top->dbg_irq)) {
            if (cyc_ti >= 0) fprintf(cyc_f, "%ld %06X %ld\n", cyc_ti, cyc_pc, cens);
            cens = 0; cyc_ti = (long)ti; cyc_pc = top->dbg_istart ? (top->dbg_pc & 0xffffff) : 0xFFFFFF;
        }

        if (top->dbg_irq) {
            if (!irq_armed) { printf("FAIL: unexpected interrupt at instr %ld npc %06X\n", ninstr, top->dbg_npc); fail = true; break; }
            if ((top->dbg_npc & 0xffffff) != irq_npc) { printf("FAIL: interrupt npc %06X, MAME %06X (instr %ld)\n", top->dbg_npc, irq_npc, ninstr); fail = true; break; }
            irq_armed = false; top->irq_vector = 0; ti++;
        }
        if (top->dbg_istart) {
            if (ti >= trace.size()) break;
            if (trace[ti].irq) { printf("FAIL: MAME took an interrupt before %06X (npc %06X), RTL executed instr %ld\n", top->dbg_pc, trace[ti].pc, ninstr); fail = true; break; }
            if ((top->dbg_pc & 0xffffff) != trace[ti].pc) {
                printf("FAIL at instr %ld: RTL pc %06X, trace pc %06X\n", ninstr, top->dbg_pc, trace[ti].pc);
                printf("  recent RTL pcs:");
                for (uint32_t p : recent) printf(" %06X", p);
                printf("\n  trace around:");
                for (size_t k = (ti > 5 ? ti - 5 : 0); k < ti + 3 && k < trace.size(); k++) printf(" %s%06X", trace[k].irq ? "irq@" : "", trace[k].pc);
                printf("\n");
                fail = true; break;
            }
            recent.push_back(top->dbg_pc); if (recent.size() > 12) recent.pop_front();
            ti++; ninstr++;
            arm_irq_if_next();
            if (max_instr > 0 && ninstr >= max_instr) break;
        }
        if (clocks > 400000000L) { printf("FAIL: timeout\n"); fail = true; }
    }
    printf("%ld instructions, %ld logged accesses replayed, %ld clocks\n", ninstr, nacc, clocks);
    if (!fail && ai < accesses.size()) printf("note: %zu accesses left in the log\n", accesses.size() - ai);
    printf(fail ? "FAIL\n" : "PASS\n");
    delete top;
    return fail ? 1 : 0;
}
