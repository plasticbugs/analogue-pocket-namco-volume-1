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
| Yamaha YGV608 VDP | `rtl/ygv608.sv`, `rtl/ygv608_render.sv` | pixel-exact on 65 frozen MAME states across every video mode the games use (`tools/regress_video.sh`) |
| Namco C352 PCM | `rtl/c352.sv` | 40 s of MAME's register writes replayed, output within 0.3% of MAME's WAV (`sim/run_c352.sh`) |
| AT28C16 EEPROM | `rtl/at28c16.sv`, saved to `ncv1.sav` | — |
| 5.5 MB ROM | Pocket SDRAM (`target/pocket/ncv1_mem.sv`) with instruction caches | system bench |

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
tools/regress_render.sh        # reference renderer vs MAME snapshots (65 states)
tools/regress_video.sh         # VDP RTL vs the reference renderer
sim/run_h8.sh                  # H8/300H CPU trace replay (artifacts/h8)
sim/run_sub.sh                 # H8/3002 + peripherals + decode trace replay
sim/run_c352.sh                # C352 vs MAME audio
sim/run_system.sh 400          # boot the whole machine, frames and audio to sim/obj_system/out
```

The MAME captures under `artifacts/` are produced by the Lua scripts in
`tools/` (`tools/mame_run.sh` runs MAME headless with disposable directories).
