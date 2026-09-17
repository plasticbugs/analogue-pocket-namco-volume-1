# Core design — Namco ND-1 on the Analogue Pocket

How the machine in `docs/hardware.md` maps onto the Pocket. Conventions are
inherited from `docs/rtl-conventions.md` (copied from the Gaiapolis core):
one 96 MHz clock, clock enables for machine rates, level-request/one-cycle-ack
memory ports, block RAMs with registered reads, Verilator bench per block.

## 1. Clocks

`clk` = 96 MHz (the proven SDRAM rate). Machine rates come from
`rtl/clk_enables.sv`:

| enable | rate | how | consumer |
|---|---|---|---|
| `cen_68k` | 12.288 MHz | fractional 16/125 accumulator | fx68k phi1/phi2 alternate on successive pulses (24.576 M pulses/s) |
| `cen_h8` | 16.384 MHz | fractional 64/375 accumulator | H8/300H state clock |
| `cen_pix` | 6.4 MHz | /15 | YGV608 dot clock (see §4) |
| `cen_c352` | 85.333 kHz | /1125 exactly | C352 sample tick (24.576 MHz / 288) |

Fractional enables jitter by one 96 MHz clock; the CPUs do not care (they
are emulated machines, not the video path). The pixel enable is an exact
integer divider because the Pocket samples RGB on a clock phase-locked to it.

## 2. Memory

The 7.5 MB image (`ncv1.mra` or `ncv2.mra`, hardware.md section 6) lives in SDRAM through `target/pocket/ncv1_mem.sv`
(modelled on gaia_mem.sv), one 16-bit word per address, big-endian words:

| region | image offset | size | SDRAM word addr | client |
|---|---|---|---|---|
| 68000 program | 0x000000 | 1 MB | 0x000000 | `rom_cache` (68k), 2-word lines |
| H8 program | 0x100000 | 512 KB | 0x080000 | `rom_cache` (H8), 2-word lines |
| YGV608 pattern ROM, chip 0 | 0x180000 | 2 MB | 0x0C0000 | burst client: tile/sprite rows |
| C352 samples | 0x380000 | 2 MB | 0x1C0000 | single byte reads |
| YGV608 pattern ROM, chip 1 | 0x580000 | 2 MB | 0x2C0000 | the same burst client |

The VDP's 8 MB pattern space is two 4 MB halves, each a 2 MB chip mirrored
twice: pattern address bit 22 (unit address bit 20) picks the chip. Vol.1 has
one chip, which MAME mirrors across all 8 MB, so its image carries it twice.

Everything else is block RAM: shared RAM 64 KB (true dual port, 68k/H8),
YGV608 tables (4 KB + 256 + 512 + 768 B) and two 512-pixel line buffers, H8
on-chip RAM 512 B, EEPROM 2 KB (loaded/saved through data slot 2), two 4 KB
instruction caches. ≈ 90 KB of the 385 KB available.

Bandwidth: a video line is 414 dots x 15 = 6210 clocks. Plane fetch is 37
tiles x 2 words (8x8) or 19 x 4 (16x16) per plane; sprites up to 64 x 4
words (16x16) — about 400 random/burst words worst case, well inside the
line at ~10 clocks each. CPU fetches go through caches so the SDRAM sees
only misses. The C352 needs 32 byte reads per 1125 clocks.

## 3. Blocks (`rtl/`)

| file | what |
|---|---|
| `ncv1_core.sv` | top: everything below plus shared RAM and EEPROM |
| `ncv1_main.sv` | fx68k, address decode (§2 of hardware.md), cuskey, IPL from YGV608 |
| `h8300h.sv` | H8/300H CPU (advanced mode), 16-bit bus, MAME-faithful state counts |
| `h83002.sv` | on-chip RAM, ITU timer channels, ports, interrupt controller around `h8300h` |
| `ncv1_sub.sv` | H8 address decode: ROM, shared RAM, C352, input ports |
| `ygv608.sv` | VDP: ports/registers, tables, CRTC, tilemap + sprite line renderers, palette, IRQs |
| `c352.sv` | 32-voice PCM, sample fetch port to SDRAM |
| `rom_cache.sv` | direct-mapped read-only cache over a req/ack port (from xenophobe rom_icache) |
| `at28c16.sv` | EEPROM with load/save ports |
| `clk_enables.sv` | §1 |

### 3.1 68000 side

fx68k (cycle-accurate). DTACK is held off while the ROM cache misses or the
shared RAM port is busy; all other devices answer in one cycle. Only the
upper byte of the YGV608/EEPROM words is wired (`umask16 ff00`).

### 3.2 H8/3002 side

The CPU is written against MAME's `h8.lst` semantics (the executable spec):
each 16-bit bus access costs 2 states, `internal(n)` costs n+1, instruction
fetch is one word ahead (prefetch). Only the H8/300H instruction subset is
implemented (the `h`, `-`, `r8l/r8u/r16l/abs*/ccr` rows of `h8.lst`; not the
H8S `s20/s26` rows). Peripherals: the ITU (16-bit timers) and interrupt
controller as the sub program uses them (§3 of hardware.md), ports as
constants, no DMA/SCI/ADC unless the trace shows use.

Verification is trace replay (`tools/trace_h8.lua`, `sim/run_h8.sh`): MAME
dumps registers, internal RAM and shared RAM at frame T0, then logs every
instruction with its registers and every non-ROM read/write in order. The
bench loads the dumps, runs the RTL, feeds each non-ROM read from the log
(checking the address), checks every write, and compares registers at every
instruction boundary. IRQ5 is injected at the instruction where MAME took it.

Timing (96 MHz): the sequencer's decode, ALU and register write-back are far
more than one system clock deep, but the CPU only advances on `cen_h8`, whose
pulses are 5 or 6 clocks apart. `h8300h_core` holds every register the
sequencer writes and writes them only on the enable; it samples the bus data,
the bus-done flag and the interrupt vector on the enable and uses them from
the next state, and it signals new bus requests, divider starts and debug
pulses by toggling a register. The `h8300h` wrapper around it does the
per-clock work: issuing requests, capturing acknowledges, the 32-clock
restoring divider and the one-clock pulses. That split is what makes
`projects/ncv1_pocket.sdc`'s 5-cycle multicycle on `h8300h_core` valid.
With memories that acknowledge within 5 clocks (the ROM caches' hits, on-chip
and shared RAM, the C352) every access still costs exactly 2 states.

State-exactness against MAME. Vol.2's sub program calls through
`jsr @aa:24` about a thousand times a frame, and its timer interrupts drifted
six instructions a period until three differences from `h8.lst` were found by
summing the RTL's states between MAME's timer interrupts (the ITU's period,
136,536 states, is an absolute reference):

* `jsr` and `bsr` charged 2 states for a prefetch at the target that, in this
  core, is the next instruction's own opcode read. Removed: `jsr @aa:24` and
  `bsr d:16` are 10 states, `bsr d:8` and `jsr @ern` 8, `jsr @@aa:8` 12.
* Interrupt entry was 2 states short: MAME has already prefetched (and
  discards) the opcode it is about to interrupt. Entry is now 14 states.
* MAME takes an interrupt in the state its source raises it, and a store lands
  about 3 states later in MAME than here (it prefetches before it writes).
  This core's controller registers its vector and the core samples it, two
  states. The two nearly cancel with a TCNT write staged one state
  (`h83002.sv`). A combinational vector reproduced MAME's instruction in 68 of
  69 interrupts, but the fitter's register retiming pulled that loop apart and
  it missed timing by a nanosecond, so the vector stays registered.

With those, the RTL's states between consecutive timer interrupts equal
MAME's to within the width of the last instruction, in all four captures.
What is left is where inside its own instruction a TCNT reload lands, a state
or two that a register dump cannot recover. An overflow a state either side of
an instruction boundary moves the interrupt by one instruction, after which
the two machines stack different state, so `sim/tb_sub.cpp` replays ITU
interrupts at MAME's instruction (holding the pending bit back, or raising it
and dropping the RTL's own copy) and fails if the RTL's own event is more than
16 states from MAME's. Measured worst case: 8 states, 0.49 microseconds; the
handler reloads the timer every period, so the skew does not accumulate.

### 3.3 YGV608

Everything MAME's `ygv608.cpp` implements except the ROM DMA and mosaic,
which ncv1 does not use (an `unsupported` output flags them). ROZ is used by
the title animation and implemented per pixel with whole-tile bursts
(docs/ygv608.md §10). Modes seen so
far: MD=2 8x8 64x32 (title/attract) and MD=1 (2 planes, 16-bit names) 32x32
with 16x16 patterns and 16-dot column scroll (games); PRM 0 and 1; plane A
transparency; both sprite aux modes.

Rendering is per scanline into a line buffer during the previous line:
plane B (if 2-plane, opaque or transparent per CTPB), then plane A and the
sprites in PRM order, pen 0 transparent for sprites and for planes with CTPx
set. Sprites are drawn entry 63 first so entry 0 wins. The output stage
reads the line buffer at `cen_pix` through the palette (6-bit RGB → 8-bit by
`pal6bit`, i.e. `x<<2 | x>>4`).

The reference renderer `tools/render_model.py` is the spec; its input is
the state file `tools/dump_state.lua` writes, and `tools/regress_render.sh`
checks it against the MAME PNG for every state in `artifacts/states/`.

### 3.4 C352

A straight implementation of `c352.cpp`: per sample tick, 32 voices are
stepped in sequence (35 clocks each), each needing at most one byte from
SDRAM; the accumulator sums into front L/R with the `>> 3` scaling. Mu-law
table is a ROM generated by `tools/gen_c352_tables.py`. Verified against
MAME by replaying the captured register writes (`artifacts/c352/*_log.txt`)
and comparing the WAV.

## 4. Video timing

The YGV608 dot clock on the board is 25.326 MHz / 4 = 6.3315 MHz and the
board measures 15.47 kHz / 59.96 Hz, i.e. 258 lines of ~409.3 dots. The
CRTC registers give a visible window of 288 x 224 starting 108/2 = 54 dots
and 26 lines in. The core uses 6.4 MHz (96/15) with 414 dots per line and
258 lines: 15.459 kHz, 59.92 Hz. Vblank IRQ at the end of the last visible
line (line 250), matching MAME's `time_until_pos(display_height)`.

The Pocket sees a 288 x 224 raster rotated 90° in `video.json` (two scaler
modes: 3:4 arcade and square pixel), as the gaia core does for 376 x 224.

## 5. Audio

C352 front L/R (16-bit signed) at 85.333 kHz, held per sample tick, then
handed to the platform `audio_mixer` which resamples in its own clock
domain (the toggle-flag CDC of METHODOLOGY §5.4 lives inside it).

## 6. Save data

The AT28C16 is the game's settings/high-score store. Data slot 2 (2 KB) loads
it at boot and is written back on request as gaia does (`core_top.sv` save
block). Slot 0 is the instance JSON that names the collection (the Pocket
consumes it; the core never sees it), slot 1 the ROM image, and each instance
names its own save (`ncv1.sav`, `ncv2.sav`), so the collections keep separate
settings. `core_top.sv` names a slot in four places (ROM download index, save
download index, the core-initiated write, the size table); they move together.

## 7. Inputs

P1/P2 8-way joystick + 3 buttons + start; coin, service, test in the DSW
port (all active low). Pocket mapping: d-pad, A = button 1, B = button 2,
X = button 3, Start, Select = coin; Test/Service via the interact menu.

## 8. Status (2026-09-17)

| Block | State |
|---|---|
| H8/300H CPU (`rtl/h8300h.sv`) | trace replay PASS on four captures, Vol.1 and Vol.2 boot and gameplay (134k, 802k, 93k, 931k instructions), state-exact against MAME |
| H8/3002 peripherals + decode (`rtl/h83002.sv`, `rtl/ncv1_sub.sv`) | the same four captures PASS with timers, INTC, ADC and ports modelled; every access exact, ITU interrupts within 8 states of MAME's (section 3.2) |
| YGV608 (`rtl/ygv608*.sv`) | pixel-exact on 161 states (79 Vol.1, 78 Vol.2, 4 synthetic FLIP); worst line 3503/6210 clocks |
| C352 (`rtl/c352.sv`) | 40 s replay within 0.3% RMS of MAME, all register reads exact (Vol.1's driver; the chip model has no per-game state) |
| Memories (`target/pocket/ncv1_mem.sv`) | both 7.5 MB images load and read back through every port with the SDRAM chip model, the two character chips at their own addresses |
| 68000 side, top (`rtl/ncv1_main.sv`, `rtl/ncv1_core.sv`, `target/pocket/*`) | whole-machine bench boots both collections |

Also verified: a scripted whole-machine run (`sim/run_system.sh`) boots Vol.1,
takes coins, navigates the menus and starts Galaga. The boot runs about 50
frames behind MAME's timeline (under a second).

Timing closed at 96 MHz for the Vol.1-only build (0.1.0, +0.24 ns worst
setup). The combined build releases the H8's reset on an enable and registers
the H8's shared-RAM decode, both for timing; CI reports the slack. No hardware run
yet: the instance-file packaging (three data slots) follows the Punch-Out!!
and Atari System 2 cores, which load this way on a Pocket, but this core's
slots have not been exercised on one.
