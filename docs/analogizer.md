# Analogizer

[Analogizer](https://github.com/RndMnkIII/Analogizer) is RndMnkIII's
cartridge-slot adapter for the Analogue Pocket. It takes analog video out of
the cart port and native game controllers in, and this core supports both.
RndMnkIII's wiki is the authority on the adapter itself.

**Not yet tried with this core.** What follows describes what the gateware
does and what the simulation bench checks (*What was measured*, below), not
what anyone has seen this core do on an adapter. The same wrapper and adapter
module run in the Moo Mesa core, where the menu, the adapter and the picture
on a CRT have been seen working (2026-10-08). Treat this core's analog output
as untested until somebody reports otherwise.

## Turning it on

**Settings are in the core's own menu**, under the game's other options,
like RndMnkIII's own "Pocket Menu" Analogizer cores. The Pocket remembers
them for this core. No `analogizer.bin` is needed: this core does not read
it (the first test build, v0.3.0-alpha.1, did; see *History* below).

| entry | options |
|---|---|
| Analogizer | Off (the default), On, On, Pocket off (the picture goes to the CRT only) |
| Analogizer Video | RGBS, RGsB, YPbPr, Y/C NTSC, Y/C PAL, Scandoubler, Scandoubler 25% / 50% / 75%, Scandoubler HQ2x |
| SNAC Adapter | None, DB15, NES, SNES, PCE 2-button, PCE 6-button, PCE Multitap, DB15 Fast, SNES A,B<->X,Y, PSX Digital, PSX Digital Fast, PSX Analog, PSX Analog Fast |
| SNAC Assignment | the six below |
| Analogizer H Position | -16 to +16 dots; + moves the picture right |
| Analogizer V Position | -24 to +2 lines; + moves the picture down |

With **Analogizer** off the core behaves exactly as it did without Analogizer
support and the cart pins stay as on a core that does not use the slot. The
adapter itself is set up as its wiki's
[How to use it](https://github.com/RndMnkIII/Analogizer/wiki/How-to-use-it%3F)
says: SNAC switch in position A (B for PlayStation pads), 5 V into its USB-C
port, the SCART cable's audio jack in the Pocket's headphone socket.

**Cart power is on for everyone.** The adapter draws its power from the
cartridge slot, so `cartridge_adapter: 0` in `core.json` enables that slot for
every user of this core, adapter or no adapter. The menu does not gate it. Do
not leave a cartridge in the slot while running this core.

**Position.** The two sliders move the picture on the CRT, in the board's own
dots and lines, for a set whose picture sits off centre. They move the syncs,
not the picture, so nothing is cropped and every mode follows; the size is
still the set's to adjust. 0 is the board's own timing. The ranges are lopsided
because the board's blanking is: vsync starts only 2 lines after the last
picture line (so the picture can move down by only 2), and is followed by 29
lines of blanking before the first (so it can move up by 24). Horizontally,
hsync starts 18 dots after the picture ends and has 76 dots of blanking after
it; +16 keeps it off the picture, and -16 keeps the Y/C colour burst off it.

## Video

The ND-1 drives a vertically mounted monitor: 414 dots by 258 lines at a
6.4 MHz dot clock, so 288x224 visible at 15.46 kHz and 59.92 Hz. The analog
output is that raster exactly as the board scans it, which is what the
cabinet's monitor saw. Nothing rotates it — the Pocket's scaler is the only
place this core's picture is ever turned — so a CRT has to be turned instead,
as it was in the cabinet.

The adapter has a clock of its own, 32 MHz, taken from the PLL's spare fifth
output. It is both the video DAC's clock and the Y/C encoder's, and it holds
each pixel for five of its cycles. It is exactly the system clock divided by
three and the dot clock times five. `pocket_analogizer.sv` takes each pixel two
system clocks after the dot enable, when the bring-up overlay's output has
settled, and hands it over with a toggle; both clocks come off the same PLL,
so the crossing is a timed path. The **Screen Shape** menu entry and the
Pocket's scaler modes do not affect the analog output.

The core's own 96 MHz would have driven the DAC (the ADV7123 is good to
140 MHz), but not the logic behind it: the hq2x blender inside the scandoubler
misses setup by 1.3 ns there, and 2,900 ALUTs of adapter sitting on the
machine's own clock costs the rest of the design its placement.

The video mode is the menu's **Analogizer Video**; the SOG switch position
applies to R2 and R3 adapters:

| Mode | SOG switch |
|---|---|
| RGBS | off |
| RGsB | on |
| YPbPr | on |
| Y/C NTSC | off |
| Y/C PAL | off |
| Scandoubler 0/25/50/75%, HQ2x (31 kHz, for a VGA monitor) | off |

The board is 60 Hz NTSC hardware and has no PAL mode. Choosing **Y/C PAL** is a
statement about the television, not the machine: it switches the colour
encoding to PAL and leaves the 59.92 Hz raster alone.

Analogizer generates the encoded Y/C signal from RGB and drives it out of the
VGA port's R and G pins, redirecting CSync to the VGA HSync pin. Turning that
into S-Video or composite is the job of an external Y/C adapter on the VGA
port, which takes its 5V from VGA pin 9. Only Mike Simone's active designs have
official support:

* [MiSTerAddons Active Y/C Adapter](https://misteraddons.com/collections/parts/products/yc-active-encoder-board/)
* [MikeS11 Active VGA to Composite / S-Video](https://ultimatemister.com/product/mikes11-active-composite-svideo/)
* [Active VGA to Composite/S-Video adapter](https://antoniovillena.com/product/mikes1-vga-composite-adapter/)

Passive adapters may work to varying degrees depending on the screen. Thanks to
[Mike Simone](https://github.com/MikeS11/MiSTerFPGA_YC_Encoder) for the Y/C
encoder this builds on.

**Analogizer: On, Pocket off** darkens the handheld's own panel while the
analog output keeps the picture.

## SNAC controllers

A SNAC pad stands in for a Pocket pad. The adapter reports its buttons in the
Pocket's own PAD bitmap, so the core's mapping is unchanged: A = button 1,
B = button 2, X = button 3, Select = coin, Start = 1 player start, R = 2 player
start. A pad with fewer buttons than the Pocket's cannot reach the ones it
lacks — an NES pad has no X or R, so on an NES pad button 3 and the 2 player
start are out of reach, while SNES, PC Engine 6-button, DB15 and PSX pads have
everything.

**SNAC Assignment** in the menu decides who plays. The board has two
players, so the last two of the adapter's six assignments add nothing:

| Assignment | Player 1 | Player 2 |
|---|---|---|
| SNAC P1 -> P1 | SNAC pad 1 | the Pocket's own controls |
| SNAC P1 -> P2 | the Pocket's own controls | SNAC pad 1 |
| SNAC P1,P2 -> P1,P2 | SNAC pad 1 | SNAC pad 2 |
| SNAC P1,P2 -> P2,P1 | SNAC pad 2 | SNAC pad 1 |
| SNAC P1,P2 -> P3,P4 | the Pocket's own controls | a second Pocket pad (SNAC goes to players 3 and 4, which the board does not have) |
| SNAC P1-P4 -> P1-P4 | SNAC pad 1 | SNAC pad 2 |

**Pass-and-Play** in the core's menu still works and still follows whoever is
player 1, so it is redundant once two SNAC pads are plugged in.

Supported pads, with the A/B switch position each one needs, are RndMnkIII's
list, verified on his hardware and not here:

* **DB15 Neo Geo**, **NES**, **SNES**, **PC Engine**, **PC Engine multitap** —
  switch A.
* **PSX DualShock / DualShock 2**, digital or analog d-pad — switch B. In the
  analog modes the left stick drives the four direction bits.

Every adapter version (v1, v2, v3) has a side slide switch labelled `A B` that
has to match the controller plugged in. Handle it with something thin and flat,
like a 2.0 mm precision screwdriver: rest the tip on the lever and press gently
until it slides over.

```
     ---
   B|O  |A  A/B switch on position B
     ---
     ---
   B|  O|A  A/B switch on position A
     ---
```

## If it does not work

Nobody has tried this core on an adapter yet, so here is where to look first.
`docs/bringup.md` in the Moo Mesa core has the order to try things in:
Analogizer Off first (the core must be exactly as before), then RGBS, then
each mode, then SNAC, then that the menu remembers its settings.

**A noisy or unstable analog picture.** The DAC clock is 32 MHz, at the low
end of what Analogizer cores use, so the clock itself is an unlikely suspect;
look at the adapter, the cable and the SOG switch first. The frequency is set
in one place, `output_clock_frequency4` in
`target/pocket/core_pll/core_pll/core_pll_0002.v`. The 960 MHz VCO will also
divide to 48 or 64 MHz, but only 32 divides the 96 MHz system clock evenly,
and anything else makes the crossing in `core_top.sv` a real asynchronous one
rather than the timed path it is now.

**Colours wrong in Y/C but fine in RGBS.** The subcarrier step and the
colourburst window are computed in integers from `CLK_HZ` (32,000,000, set
where `core_top.sv` instances `pocket_analogizer`), in `pocket_analogizer.sv`.

**No picture at all in any mode.** Check the menu says **Analogizer: On**.
With it off the adapter is disabled and the cart pins stay as on a core that
does not use the slot.

**The picture rolls or tears at one end of a position slider.** The range is
set from the board's blanking (above); say which slider, which end and which
mode.

**A SNAC pad that does not respond.** The controller polling dividers are
scaled from `MASTER_CLK_FREQ`; at 32 MHz they land within 0.001% of their
nominal rates, so the clock is not the suspect. Check the A/B switch first.

## Where to report problems

Analog video and SNAC behaviour belong to the
[Analogizer project](https://github.com/RndMnkIII/Analogizer). Three things are
this core's and are worth reporting here:

* the raster and its timing (288x224, 15.46 kHz, 59.92 Hz) and the colours in it
* the position sliders
* which buttons a SNAC pad lands on, and the player assignments above
* "On, Pocket off", the menu's memory of its settings, and anything that
  changed about the Pocket's own picture, sound or saves after this was added

## What it costs the rest of the core

The adapter is about 2,100 ALMs, which takes the core from 73% of the device
to 84%. Nothing else about the machine changes: the 68000, the H8, the VDP
and the C352 are untouched, and the Pocket's own picture, sound and saves go
out exactly as before.

It does squeeze the fitter, and this core's 96 MHz clock never had much room.
The numbers, cold corner (the worst one here), 96 MHz setup slack:

| | ALMs | slack |
|---|---|---|
| without the adapter | 73% | +0.236 ns |
| with it (file settings), `AUTO FIT` | 83% | +0.009 ns |
| with it (file settings), `STANDARD FIT` | 82% (15,241) | +0.618 ns |
| with it (menu settings, this build), `STANDARD FIT` | 84% (15,555) | +0.464 ns |

Which is why the fitter effort changed along with it — see below. The menu
build costs 314 ALMs more than the file build (the wrapper's read-back,
position and pixel hand-over registers) and the same 161 RAM blocks and 13
DSP blocks. Its worst setup slack at any corner is +0.402 ns (slow 85C, the
96 MHz clock); its worst hold is +0.007 ns at fast 0C, the SDRAM's
`dram_dq` -> `dq_in` capture, exactly what the file build had; every
constraint in `projects/ncv1_pocket.sdc` applied (the only ignored ones are
the platform's `sys_constr.sdc` output delays on `dram_clk`, which the
project SDC sets again once it has defined that clock).

## For the developer

### The settings word

One 32-bit word at `0xF7000000`, the layout RndMnkIII's adapter module (1.4)
decodes. Each of the four list entries in `interact.json` (ids 70–73) has a
mask that keeps every bit but its own field, so they share the word:

| bits | field | values |
|---|---|---|
| 4:0 | SNAC type | 0 none, 1 DB15, 2 NES, 3 SNES, 4 PCE 2-button, 5 PCE 6-button, 6 PCE multitap, 9 DB15 fast, 0xB SNES A/B↔X/Y, 0x10/0x11 PSX digital, 0x12/0x13 PSX analog. 16 and up select the adapter's B wiring. |
| 5 | enable | 0: the port stays idle and nothing else applies |
| 9:6 | SNAC assignment | 0–5 as in the table above |
| 13:10 | video | 0 RGBS, 1 RGsB, 2 YPbPr, 3 Y/C NTSC, 4 Y/C PAL, 5–9 scandoubler 0/25/50/75%/HQ2x |
| 14 | blank the Pocket screen | |

The word is written as a number (the module is told
`bridge_endian_little = 1`, so it does not byte-swap it as it would a file),
and `pocket_analogizer` reads it back from its own register, combinationally.
The firmware reads every entry back each frame and merges a masked entry
from that read (Analogue's interact.json docs); the bridge samples read data
four clocks after it presents the address and pulses `bridge_rd` only
afterwards, so the module's own read-back, updated on that pulse, would hand
back the previous read's value and the entries would wipe each other.

**Picture position.** `0xF7000004` (horizontal, dots, + right) and
`0xF7000008` (vertical, lines, + down), ids 74–75, signed sliders with no mask.
`pocket_analogizer` re-makes hsync and vsync from the source's own edges,
earlier or later by the amount set, as wide as the source's; RGB and blanking
pass untouched. A re-made sync waits until it has been off as long as it was
on, because the module's `sync_fix` re-decides sync polarity every period
and a jump between settings would otherwise turn csync inside out for a frame.

### What was measured

`sim/run_analogizer.sh`: the wrapper and the vendored module at this core's
raster (414 x 258 dots, 288 x 224 visible, 15 clocks of 96 MHz a dot) and the
32 MHz Analogizer clock, read at the cartridge pins as the DAC reads them.
- With the menu at its defaults, every pin sits as on a core without the
  adapter, and the controller words pass through.
- Every option of the four list entries (32), set as the firmware sets a
  masked entry (read the word back as the bridge samples it, merge, write):
  the word, the adapter's copy and the enable each followed.
- RGBS: all 64,512 visible dots of a frame reach the DAC pins, in raster
  order, as their top six bits per channel, 0 differing; csync one 32-dot
  pulse a line.
- Scandoubler: 516 lines a frame (twice 258) at 1,035 clocks, half the
  board's line.
- YPbPr and Y/C NTSC/PAL: no unknown on any pin for a frame.
- Position at both ends of the shipped sliders (+16,+2 and -16,-24): read
  back as written, the settings word untouched; csync moves by exactly 80
  clocks (16 dots) and 2 or 24 lines, the picture is still every dot with 0
  differing, csync is never low while a dot is drawn, the scandoubler is
  unchanged; back at 0, csync is where it started. A jump between settings
  written just after a pulse (V +2 to -2, H +16 to -16) leaves csync out of
  the picture for three frames. One step further (+18 dots, +3 lines) fails
  the bench: a sync inside the picture.
- All six SNAC assignments, the analog stick, and type "none" map as
  tabled; the blank bit; enable off again returns the port to idle.

`sim/lint.sh` lints the wrapper (the vendored files' warnings dropped by
path). `tools/check_json.py pkg/pocket --active 288x224` is clean: every
entry inside its mask, the sliders within the wrapper's 8 bits, no data slot
at `0xF7000000`, the slot powered, 11 menu entries and 3 data slots.

**Not proven:** anything on hardware with this core; that the firmware
writes a signed slider as a two's complement word; the SNAC serial protocols,
which are the adapter module's and are forced at its outputs in the bench;
the Y/C and YPbPr encodings beyond running without unknowns.

## In the gateware

* `target/pocket/analogizer/` — RndMnkIII's `openFPGA_Pocket_Analogizer` 1.4
  and the 14 files it instantiates, verbatim, from MiraxPocket commit
  `9dfdd2b9bec79fe5ea10e154a0613a0c9d4fe37f` (the copy every core from
  plasticbugs' template carries); `analogizer.qip` lists only what is used.
  It contains work from the MiST project (scandoubler), MiSTer (YPbPr, hq2x)
  and Mike Simone (Y/C).
* `target/pocket/pocket_analogizer.sv` — the template's wrapper, unchanged:
  the menu's settings and their read-back, the picture position, the pixel
  hand-over, the Y/C constants, and SNAC pads into `key1..key4`.
* `target/pocket/core_top.sv` — `key1..key4` into `gamepad` in place of
  `cont1..4_key`, the bridge read at `0xF7xxxxxx`, the Pocket-screen blank in
  the video hand-over, and the `pocket_analogizer` instance at the foot of the
  file. `USE_ANALOGIZER = 0` in the parameter list takes the whole thing out
  of the build and restores the stock "cart slot unused" pin state.
* `target/pocket/core_pll/core_pll/core_pll_0002.v` — `outclk_4`, which was a
  spare 96 MHz output nothing used, retuned to the adapter's 32 MHz.
* `projects/ncv1_pocket.qsf` — `analogizer.qip`, and `FITTER_EFFORT` moved
  from `AUTO FIT` to `STANDARD FIT`. The adapter takes the design from 73% of
  the device to 82%, and `AUTO FIT` stops placing the moment it believes the
  constraints are met: it left the 96 MHz clock closing by 0.009 ns on the cold
  corner, where the same design without the adapter closed by 0.236 ns. At high
  effort the placer finds 0.618 ns with the adapter in — more margin than the
  core had before it — for no extra fit time.
* `pkg/pocket/Cores/plasticbugs.namcocollection/interact.json` — the six
  entries; `core.json` — cart power.
* `sim/run_analogizer.sh`, `sim/tb_analogizer.sv` — the bench, with the
  raster at the top of the bench; `tools/check_json.py` — the JSON checks.

## History

The first test build (`v0.3.0-alpha.1`, commit `c1f1820`) read its settings
from `analogizer.bin`, a file Pupdate and AnalogizerConfigurator write to
`/Assets/analogizer/common/`, through a data slot at `0xF7000000` and a second
platform id `analogizer`; it instanced the adapter module directly. The
adapter's own *How to use it* page never mentions the file, players' other
Analogizer cores take their settings from the menu, and a player without the
file had an adapter that stayed dark, so this build uses the menu and the
template's wrapper instead. A leftover `analogizer.bin` on the card is
ignored.
