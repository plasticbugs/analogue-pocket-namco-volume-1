# Namco Classic Collection for the Analogue Pocket

An openFPGA core for Namco's ND-1 arcade board and the two collections that
ran on it, each game in Original and Arrangement form:

* *Namco Classic Collection Vol.1* (1995): Galaga, Xevious, Mappy
* *Namco Classic Collection Vol.2* (1996): Pac-Man, Rally-X, Dig Dug

The whole board is in gateware: 68000 main CPU, H8/3002 sub CPU, Yamaha YGV608
video, Namco C352 sound. The two collections are the same hardware with
different ROMs (Vol.2 fills a second character-ROM socket), so one bitstream
runs both and the Pocket lists them by name.

**Status: pre-release.** Every block is verified against MAME in simulation
(below) with both collections; nothing has run on a Pocket yet.

## What is in the box

| Board part | Implementation | Verified by |
|---|---|---|
| 68000 @ 12.288 MHz | fx68k (cycle-accurate) | system bench |
| H8/3002 @ 16.384 MHz | `rtl/h8300h.sv` + `rtl/h83002.sv`, written from MAME's `h8.lst` | trace replay of both sub programs: 1.9 million instructions of boot and gameplay in lockstep with MAME, every non-ROM access matched, timer interrupts within 8 CPU states of MAME's (`sim/run_sub.sh`) |
| Yamaha YGV608 VDP | `rtl/ygv608.sv`, `rtl/ygv608_render.sv` | pixel-exact on 157 frozen MAME states from both collections, across every video mode the games use, including rotation/zoom (`tools/regress_video.sh`) |
| Namco C352 PCM | `rtl/c352.sv` | 40 s of MAME's register writes replayed, output within 0.3% of MAME's WAV (`sim/run_c352.sh`) |
| AT28C16 EEPROM | `rtl/at28c16.sv`, saved per collection (`ncv1.sav`, `ncv2.sav`) | — |
| 7.5 MB ROM | Pocket SDRAM (`target/pocket/ncv1_mem.sv`) with instruction caches | image load and read-back through every port with the SDRAM chip model (`sim/run_mem.sh`) |

`docs/hardware.md` describes the board, `docs/core-design.md` the mapping onto
the Pocket, `docs/ygv608.md` the VDP semantics the RTL was written from, and
`METHODOLOGY.md` the method (MAME is the oracle; a Python reference renderer is
the executable spec; frozen-state benches are the regression gate).

## Building the ROM images

ROMs are not included. From your own MAME `ncv1` and `ncv2` romsets (zip or
directory), whichever you have:

```
python3 tools/mra_build.py ncv1.mra ncv1.zip     # -> ncv1.rom
python3 tools/mra_build.py ncv2.mra ncv2.zip     # -> ncv2.rom
```

Each image is 7,864,320 bytes; copy them to `Assets/namcocollection/common/` on
the SD card. The Pocket lists "Namco Classic Collection Vol.1" and "Vol.2"
under the core (the instance files in
`Assets/namcocollection/plasticbugs.namcocollection/`); a collection whose image
is missing will not load, the other still does. Settings and records are saved
per collection (`ncv1.sav`, `ncv2.sav`).

The builder checks every ROM's CRC32. Both known dumps of Vol.1's `nc1cg0.10c`
are accepted (MAME ≤ 0.270 listed CRC 355e7f29, later versions d4383199), and
Vol.2's second character ROM is found by CRC whether it is named `ncs1cg1.10f`
(MAME) or `ncs1cg1.10e`. An `ncv1.rom` built for version 0.1.0 (5,767,168
bytes) must be rebuilt.

## The screen

The ND-1 drives a vertically mounted monitor. The core emits the VDP's native
288x224 raster and the Pocket's scaler turns it 90 degrees clockwise
(`rotation: 90` in `video.json`, the same orientation as MAME's ROT90 and as
the Gaiapolis and Time Pilot cores). **Screen Shape** in the Interact menu
switches live between the cabinet's 3:4 and square pixels. The aspect values in
`video.json` describe the raster before rotation, so the 3:4 entry is written
4:3.

## Controls

D-pad or stick moves; A = button 1, B = button 2, X = button 3, Select =
coin, Start = 1 player start, Y = 2 player start. A second pad plays player 2,
and its Start is also the 2 player start. The buttons can be remapped in the
Pocket's controls menu; the directions are fixed. Test/service switches are in
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
tools/regress_render.sh        # reference renderer vs MAME snapshots (157 states, both collections)
tools/regress_video.sh         # VDP RTL vs the reference renderer
sim/run_h8.sh                  # H8/300H CPU trace replay (H8DIR=artifacts/h8, h8_game, h8_ncv2, h8_ncv2_game)
sim/run_sub.sh                 # H8/3002 + peripherals + decode trace replay (same captures)
sim/run_c352.sh                # C352 vs MAME audio
sim/run_mem.sh                 # SDRAM partition: load the image, read it back through every port
sim/run_system.sh 400          # boot the whole machine, frames and audio to sim/obj_system/out
                               # (ROM=artifacts/ncv2.rom for Vol.2; Vol.2 benches take ROM= the same way)
```

The MAME captures under `artifacts/` are produced by the Lua scripts in
`tools/`: `tools/make_corpus.sh` dumps the frozen video states of both
collections, `tools/capture_h8.sh` the four sub-CPU traces, and
`tools/mame_run.sh` runs MAME headless with disposable directories
(`GAME=ncv2` for Vol.2).

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

Namco Classic Collection Vol.1 and Vol.2 are © 1995, 1996 Namco. No ROM data
of any kind is included in this repository — see "Building the ROM images"
above.
