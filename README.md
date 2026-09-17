# Namco Classic Collection Vol.1 for the Analogue Pocket

An openFPGA core for Namco's ND-1 arcade board running *Namco Classic
Collection Vol.1* (1995): Galaga, Xevious and Mappy, each in Original and
Arrangement form. The whole board is in gateware: 68000 main CPU, H8/3002 sub
CPU, Yamaha YGV608 video, Namco C352 sound.

**Status: pre-release.** Every block is verified against MAME in simulation
(below); the first hardware build is in progress.

## What is in the box

| Board part | Implementation | Verified by |
|---|---|---|
| 68000 @ 12.288 MHz | fx68k (cycle-accurate) | system bench |
| H8/3002 @ 16.384 MHz | `rtl/h8300h.sv` + `rtl/h83002.sv`, written from MAME's `h8.lst` | trace replay: 800k instructions of gameplay in lockstep with MAME, every non-ROM access and interrupt matched (`sim/run_sub.sh`) |
| Yamaha YGV608 VDP | `rtl/ygv608.sv`, `rtl/ygv608_render.sv` | pixel-exact on 79 frozen MAME states across every video mode the games use, including the title's rotation/zoom (`tools/regress_video.sh`) |
| Namco C352 PCM | `rtl/c352.sv` | 40 s of MAME's register writes replayed, output within 0.3% of MAME's WAV (`sim/run_c352.sh`) |
| AT28C16 EEPROM | `rtl/at28c16.sv`, saved to `ncv1.sav` | — |
| 5.5 MB ROM | Pocket SDRAM (`target/pocket/ncv1_mem.sv`) with instruction caches | image load and read-back through every port with the SDRAM chip model (`sim/run_mem.sh`) |

`docs/hardware.md` describes the board, `docs/core-design.md` the mapping onto
the Pocket, `docs/ygv608.md` the VDP semantics the RTL was written from, and
`METHODOLOGY.md` the method (MAME is the oracle; a Python reference renderer is
the executable spec; frozen-state benches are the regression gate).

## Building the ROM image

ROMs are not included. From your own MAME `ncv1` romset (zip or directory):

```
python3 tools/mra_build.py ncv1.mra ncv1.zip
```

produces `ncv1.rom` (5.5 MB); copy it to `Assets/ncv1/common/` on the SD card.
Both known dumps of `nc1cg0.10c` are accepted (MAME ≤ 0.270 listed CRC
355e7f29, later versions d4383199).

## Controls

D-pad or stick moves; A = button 1, B = button 2, X/Y = button 3, Select =
coin, Start = start. A second pad plays player 2. Test/service switches are in
the core's interact menu.

## Building the core

```
./build-local.sh map        # analysis & synthesis only, ~2 minutes (run before every push)
./build-local.sh compile    # full compile in Docker + package into release/pocket/
```

CI (`.github/workflows/compile.yml`) lints, compiles and packages on every
push; a tag cuts a release with the tested bitstream.

## Verification

```
sim/lint.sh                    # Verilator -Wall over every block
tools/regress_render.sh        # reference renderer vs MAME snapshots (79 states)
tools/regress_video.sh         # VDP RTL vs the reference renderer
sim/run_h8.sh                  # H8/300H CPU trace replay (artifacts/h8)
sim/run_sub.sh                 # H8/3002 + peripherals + decode trace replay
sim/run_c352.sh                # C352 vs MAME audio
sim/run_mem.sh                 # SDRAM partition: load the image, read it back through every port
sim/run_system.sh 400          # boot the whole machine, frames and audio to sim/obj_system/out
```

The MAME captures under `artifacts/` are produced by the Lua scripts in
`tools/` (`tools/mame_run.sh` runs MAME headless with disposable directories).

## Credits

The Namco ND-1-specific RTL, reference renderer and verification harness
(`rtl/`, `tools/`, `sim/`) are original; the rest of the core is built on
MAME's device models, one vendored CPU core, and the Pocket's platform layer.

### The hardware description

* MAME's `namco/namcond1.cpp` by **Mark McDougall** and **R. Belmont** — the
  ND-1 board driver this core's memory map and machine description
  (`docs/hardware.md`) are derived from. Its "Guru-Readme" section is the
  source for the board's PCB layout and part list.
* MAME's `namco/ygv608.cpp` by **Mark McDougall** and **Angelo Salese** — the
  Yamaha YGV608 device model `rtl/ygv608.sv` and `rtl/ygv608_render.sv`, and
  the reference renderer `tools/render_model.py`, were written from it;
  documented in `docs/ygv608.md`.
* MAME's `sound/c352.cpp` by **R. Belmont** and **superctr** — the Namco C352
  PCM model `rtl/c352.sv` (per-voice stepping, volume ramp, mu-law table) was
  written from it.
* MAME's H8 CPU core — `cpu/h8/h8.cpp`, `h8.lst`, `h83002.cpp` and `h8h.cpp`,
  plus the on-chip peripheral models `h8_intc.cpp`, `h8_timer16.cpp`,
  `h8_adc.cpp`, `h8_dma.cpp`, `h8_dtc.cpp`, `h8_port.cpp`, `h8_sci.cpp` and
  `h8_watchdog.cpp` — all by **Olivier Galibert**. `rtl/h8300h.sv` (the
  H8/300H core) and `rtl/h83002.sv` (the on-chip peripherals the ND-1 sub
  program actually touches) were written as an executable spec against them.
* MAME's `machine/at28c16.cpp` by **smf** — the AT28C16 EEPROM model
  `rtl/at28c16.sv`, including its erased-at-power-on (0xFF) state, was written
  from it.
* MAME's `tilemap.cpp` by **Aaron Giles** — the generic tilemap compositing
  (`tilemap_t::draw`, `draw_roz_core`) that `tools/render_model.py` reproduces
  for the YGV608's plain and ROZ tilemap drawing.

### Documentation

* Renesas' *H8/300H Series Software Manual* (REJ09B0213, available from
  Renesas) — the instruction-set reference `rtl/h8300h.sv` was implemented
  against. It is not redistributed here.

### CPU

* fx68k, the cycle-accurate 68000 core, by **Jorge Cwik** (GPLv3) —
  `modules/cpu-fx68k`, used for both simulation (`sim/run_system.sh`,
  `sim/lint.sh`) and synthesis (`rtl/index.qip`), so what the benches verify
  is what ships.

### Platform layer

* The Pocket platform layer is the
  [OpenGateware](https://github.com/opengateware) framework, whose primary
  author is **Marcus Andrade** (MIT and GPL-3.0-or-later per file). Within it
  this core also uses work by **Alexey Melnikov** (audio filters, DC blocker,
  scanlines and shadow mask), **Till Harbaum** (the original scanline
  generator) and **Adam Gastineau** (data loader and unloader).
* `platform/pocket/bsp/pocket/apf_top.sv` and the APF bridge peripherals in
  `platform/pocket/peripherals/` are supplied by **Analogue Enterprises
  Limited** under its own Analogue Pocket Framework Software License
  Agreement and EULA, not under the GPL/MIT terms above.
* `target/pocket/sdram_ctrl.sv`'s pin-level timing (CL2, read data captured at
  READ+4) is carried over from the Punch-Out!! core's `sdram16.sv`, by way of
  the S.T.U.N. Runner and Gaiapolis cores, all proven on the Pocket at 96 MHz.
* PLL and memory wrappers under `target/pocket/core_pll/` and
  `platform/pocket/megafunctions/` are generated Altera/Intel megafunction
  instantiations.

### Tools

* **MAME** as the oracle throughout — driven headless via the Lua scripts in
  `tools/` (`tools/mame_run.sh`) to dump frozen states, tap device reads and
  capture reference frames.
* **Verilator** for simulation and lint, **Quartus Prime** for synthesis,
  **Python 3** for the reference renderer and ROM builder
  (`tools/mra_build.py`, `tools/render_model.py`) — no third-party Python
  modules.

### Game

Namco Classic Collection Vol.1 is © 1995 Namco. No ROM data of any kind is
included in this repository — see "Building the ROM image" above.
