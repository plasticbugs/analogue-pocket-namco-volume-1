# Analogizer

[Analogizer](https://github.com/RndMnkIII/Analogizer) is RndMnkIII's
cartridge-slot adapter for the Analogue Pocket. It takes analog video out of
the cart port and native game controllers in, and this core supports both.
RndMnkIII's wiki is the authority on the adapter itself.

**None of it has been tested.** No maintainer of this core owns an adapter, a
CRT or a SNAC harness, so what follows describes what the gateware does, not
what anyone has seen it do. The integration is the same one the adapter's own
cores use, at this core's clock and raster. Treat it as untested until somebody
reports otherwise.

## Turning it on

Everything except the on/off switch comes from `analogizer.bin`, not from the
Pocket's menu. Generate it with
[Pupdate 5.6.0 or newer](https://github.com/mattpannella/pupdate/releases) or
[AnalogizerConfigurator 0.7 or newer](https://github.com/RndMnkIII/AnalogizerConfigurator/releases),
then copy it to `/Assets/analogizer/common` on the SD card, creating that folder
if it does not exist. That one file is shared by every Analogizer core on the
card. Set **ANALOGIZER ENABLE OPTIONS: ON** in it; with it off, every Analogizer
path in the core is disabled and the cart pins stay in high impedance.

The core loads it through data slot 10 at `0xF7000000` (`data.json`), which is
why `core.json` lists `analogizer` as a second platform id: the slot's
`parameters` field points its Assets folder at that platform rather than at
`namcocollection`.

**Cart power is on for everyone.** The adapter draws its power from the
cartridge slot, so `cartridge_adapter: 0` in `core.json` enables that slot for
every user of this core, adapter or no adapter. The setting in `analogizer.bin`
does not gate it. Do not leave a cartridge in the slot while running this core.

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
three and the dot clock times five, so the raster crosses into it as a timed
path off the same PLL rather than as an asynchronous one. The **Screen Shape**
menu entry and the Pocket's scaler modes do not affect the analog output.

The core's own 96 MHz would have driven the DAC (the ADV7123 is good to
140 MHz), but not the logic behind it: the hq2x blender inside the scandoubler
misses setup by 1.3 ns there, and 2,900 ALUTs of adapter sitting on the
machine's own clock costs the rest of the design its placement.

These video modes come from `analogizer.bin`; the SOG switch position applies
to R2 and R3 adapters:

| Mode | SOG switch |
|---|---|
| RGBS | off |
| RGsB | on |
| YPbPr | on |
| Y/C NTSC | off |
| Y/C PAL | off |
| SVGA scandoubler (with scanlines) | off |

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

**Blank the Pocket Screen** in `analogizer.bin` darkens the handheld's own
panel while the analog output keeps the picture.

## SNAC controllers

A SNAC pad stands in for a Pocket pad. The adapter reports its buttons in the
Pocket's own PAD bitmap, so the core's mapping is unchanged: A = button 1,
B = button 2, X = button 3, Select = coin, Start = 1 player start, R = 2 player
start. A pad with fewer buttons than the Pocket's cannot reach the ones it
lacks — an NES pad has no X or R, so on an NES pad button 3 and the 2 player
start are out of reach, while SNES, PC Engine 6-button, DB15 and PSX pads have
everything.

**SNAC controller assignment** in `analogizer.bin` decides who plays:

| Assignment | Player 1 | Player 2 |
|---|---|---|
| 0 | SNAC pad 1 | the Pocket's own controls |
| 1 | the Pocket's own controls | SNAC pad 1 |
| 2 | SNAC pad 1 | SNAC pad 2 |
| 3 | SNAC pad 2 | SNAC pad 1 |

**Pass-and-Play** in the core's menu still works and still follows whoever is
player 1, so it is redundant once two SNAC pads are plugged in.

Supported pads, with the A/B switch position each one needs, are RndMnkIII's
list, verified on his hardware and not here:

* **DB15 Neo Geo**, **NES**, **SNES**, **PC Engine**, **PC Engine multitap** —
  switch A.
* **PS/2 Keyboard & Mouse + NES / SNES / DB15 / no pad** — switch A. This core
  reads no keyboard or mouse; only the game-controller half of those modes does
  anything here.
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

Nobody has tried any of this, so here is where to look first.

**A noisy or unstable analog picture.** The DAC clock is 32 MHz, at the low
end of what Analogizer cores use, so the clock itself is an unlikely suspect;
look at the adapter, the cable and the SOG switch first. The frequency is set
in one place, `output_clock_frequency4` in
`target/pocket/core_pll/core_pll/core_pll_0002.v`. The 960 MHz VCO will also
divide to 48 or 64 MHz, but only 32 divides the 96 MHz system clock evenly,
and anything else makes the crossing in `core_top.sv` a real asynchronous one
rather than the timed path it is now.

**Colours wrong in Y/C but fine in RGBS.** The subcarrier constants are
computed from `CLK_VIDEO = 32.0` in `core_top.sv`; at 32 MHz they come out as
122992229676 (NTSC) and 152337980273 (PAL) in Q0.40, with the colourburst
window at 33..113 (NTSC) and 33..105 (PAL) encoder clocks from the start of
hsync.

**No picture at all in any mode.** `analogizer.bin` is a shared file: check it
is at `/Assets/analogizer/common/analogizer.bin` and that ANALOGIZER ENABLE
OPTIONS is ON. With no file at all, `analogizer_config` powers up as zero, the
adapter is disabled and the cart pins stay in high impedance — which looks
exactly the same as a file the core failed to read.

**A SNAC pad that does not respond.** The controller polling dividers are
scaled from `MASTER_CLK_FREQ`; at 32 MHz they land within 0.001% of their
nominal rates, so the clock is not the suspect. Check the A/B switch first.

## Where to report problems

Analog video and SNAC behaviour belong to the
[Analogizer project](https://github.com/RndMnkIII/Analogizer). Three things are
this core's and are worth reporting here:

* the raster and its timing (288x224, 15.46 kHz, 59.92 Hz) and the colours in it
* which buttons a SNAC pad lands on, and the player assignments above
* Blank the Pocket Screen, and anything that changed about the Pocket's own
  picture, sound or saves after this was added

## What it costs the rest of the core

The adapter is 2,900 ALUTs, about 1,900 ALMs, which takes the core from 73% of
the device to 82%. Nothing else about the machine changes: the 68000, the H8,
the VDP and the C352 are untouched, and the Pocket's own picture, sound and
saves go out exactly as before.

It does squeeze the fitter, and this core's 96 MHz clock never had much room.
The numbers, cold corner (the worst one here), 96 MHz setup slack:

| | ALMs | slack |
|---|---|---|
| without the adapter | 73% | +0.236 ns |
| with it, `AUTO FIT` | 83% | +0.009 ns |
| with it, `STANDARD FIT` | 82% | +0.618 ns |

Which is why the fitter effort changed along with it — see below.

## In the gateware

* `target/pocket/analogizer/` — RndMnkIII's adapter sources, release 1.4
  (20/08/2026), carried across unmodified. It contains work from the MiST
  project (scandoubler), MiSTer (YPbPr, hq2x) and Mike Simone (Y/C).
* `target/pocket/core_top.sv` — the settings block above `gamepad`, the SNAC
  mux into `pad1_key`/`pad2_key`, the Pocket-screen blanking in the video
  hand-over, and the raster crossing plus the `openFPGA_Pocket_Analogizer`
  instance at the foot of the file. `USE_ANALOGIZER = 0` in the parameter list
  takes the whole thing out of the build and restores the stock "cart slot
  unused" pin state.
* `target/pocket/core_pll/core_pll/core_pll_0002.v` — `outclk_4`, which was a
  spare 96 MHz output nothing used, retuned to the adapter's 32 MHz.
* `projects/ncv1_pocket.qsf` — `analogizer.qip`, and `FITTER_EFFORT` moved
  from `AUTO FIT` to `STANDARD FIT`. The adapter takes the design from 73% of
  the device to 82%, and `AUTO FIT` stops placing the moment it believes the
  constraints are met: it left the 96 MHz clock closing by 0.009 ns on the cold
  corner, where the same design without the adapter closed by 0.236 ns. At high
  effort the placer finds 0.618 ns with the adapter in — more margin than the
  core had before it — for no extra fit time.
* `pkg/pocket/Cores/plasticbugs.namcocollection/data.json`, `core.json` — the
  configuration slot, the second platform id and cart power.
