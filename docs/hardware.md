# Namco Classic Collection Vol.1 (Namco, 1995) — hardware notes

Namco ND-1 board (MAME `namco/namcond1.cpp`, set `ncv1`). Games: Galaga,
Xevious, Mappy, each in Original and Arrangement form. Every claim carries its
source: `[MAME]` from the driver/device source in `ref/mame/`, `[XML]` from
`mame -listxml ncv1`, `[GURU]` from the PCB readme in the driver, `[PROBE]`
measured with a Lua script in `tools/`, `[VERIFIED]` matched against the RTL.

## 1. Clocks `[GURU][MAME]`

| Clock | Value | Derivation |
|---|---|---|
| Master | 49.152 MHz | crystal |
| 68000 | 12.288 MHz | 49.152 / 4 |
| H8/3002 | 16.384 MHz | 49.152 / 3 |
| C352 | 24.576 MHz | 49.152 / 2; sample rate = 24.576 MHz / 288 = 85.333 kHz |
| YGV608 | 25.326 MHz crystal | dot clock = crystal / 2 or / 4 (R#7 DCKM); see §4.1 |
| Measured video | HSync 15.47 kHz, VSync 59.96 Hz | `[GURU]` |

MAME clocks its screen at 49.152/8 = 6.144 MHz with 402 x 261 (58.56 Hz)
`[XML]`, which is a placeholder; the YGV608 CRTC registers the game programs
are in §4.1.

## 2. 68000 memory map `[MAME]`

| Range | Function | Notes |
|---|---|---|
| 000000–0FFFFF | program ROM | `nc2main0.14d` at 0, `nc2main1.13d` at 80000; 16-bit words as stored |
| 400000–40FFFF | shared RAM (64 KB) | H8 sees it at 200000 |
| 800000–80000F | YGV608 ports P#0–P#7 | upper byte only (`umask16 ff00`), one port per word |
| A00000–A00FFF | AT28C16 EEPROM (2 KB) | upper byte only |
| C3FF00–C3FFFF | "cuskey" (MACH211 KC001) | see below |

Cuskey `[MAME]`: reads at +2E and +30 return 0 (a jump vector inside ISR2;
zero means return). Write +0A: non-zero releases the H8 from reset and enables
its IRQ5 (per-vblank); zero disables. Write +0C: bits 1:0 select the YGV608
graphics bank (`set_gfxbank`, 64K 8x8 tiles per bank in 4bpp). The game
writes +00, +0A, +0C, +0E `[PROBE]`.

Interrupts: YGV608 vblank → 68000 IPL1, raster → IPL2. The game enables only
the vblank interrupt (R#14 = 01) `[PROBE]`.

## 3. H8/3002 sub CPU `[MAME]`

Hitachi H8/3002 (H8/300H core, no internal ROM, 512 bytes on-chip RAM at
FFFD10–FFFF0F, on-chip peripherals at FFFF20–FFFFFF), advanced mode (24-bit
addresses), 16.384 MHz.

| Range | Function |
|---|---|
| 000000–07FFFF | program ROM `nc1sub.1c` |
| 200000–20FFFF | shared RAM (64 KB) |
| A00000–A07FFF | C352 (word access; register index = address/2) |
| C00000–C00001 | DSW port (active low) |
| C00002–C00003 | P1/P2 port (active low) |
| C00010, C00030, C00040 | unmapped (watchdog/outputs?) |

The H8 gets IRQ5 pulsed once per vblank while enabled through the cuskey. It
handles inputs (reads the two ports, publishes to shared RAM), the C352 sound
driver and the EEPROM-less bookkeeping the 68000 asks for via shared RAM.

On-chip peripherals the sub program uses `[PROBE][VERIFIED]` (from the
trace-replay captures in `artifacts/h8*`, replayed by `sim/run_sub.sh`):

| Block | Registers | Use |
|---|---|---|
| Interrupt controller | SYSCR FFFFF2 = 09, ISCR FFFFF4 = 20 (IRQ5 edge), IER FFFFF5 = 20, ISR FFFFF6, ICR FFFFF8/9 = 0 | IRQ5 (vector 17) from the vblank, 60 Hz |
| ITU channel 0 | TSTR FFFF60 = 01, TCR0 FFFF64 = 83 (phi/8, no clear), TIER0 FFFF66 = FC (OVIE), TSR0 FFFF67, TCNT0 FFFF68 reloaded with BD55 each interrupt | overflow interrupt (vector 26) every 136,536 states = 120 Hz sound-driver tick |
| Ports | DDR/DR of P4, P6, P8, P9, PA, PB; P7 and PA pins read 1 | outputs the board does not use; PA bit 0 toggled |
| ADC | ADCSR FFFFE8 written 3B (scan, channels 0-3, CKS=1), ADF polled | the games have no analog inputs; the flag is polled once at boot |
| Watchdog, SCI, DMA | written at reset, never used | registers read back |

Timing model `[MAME]`: every 16-bit bus access is 2 states, internal operations
n+1 states (`internal(n)`), one word of prefetch per instruction. The RTL
matches MAME's per-instruction state counts closely enough that the timer
interrupts land within a handful of instructions of MAME's over 800k
instructions of gameplay.

## 4. YGV608 video `[MAME ygv608.cpp][PROBE]`

Yamaha YGV608 "PVDC2" pattern VDP with internal pattern name table (4 KB),
sprite attribute table (256 B = 64 sprites), scroll tables (2 x 256 B) and a
256-entry 18-bit palette; pattern data comes from the external 2 MB character
ROM `nc1cg0.10c` (mirrored to 8 MB) through the gfx bank in the cuskey.

### 4.1 Register programming seen in ncv1 `[PROBE]`

| Reg | Value | Meaning |
|---|---|---|
| R#2 | CF | CPAW, CPAR, SCAW, SCAR, SAAW, SAAR auto-increment on; B/A=0 |
| R#7 | 05 | DSPE=1, MD=2 (1 plane, 16 colours, 16-bit pattern names), ZRON=0, FLIP=0, DCKM=0 |
| R#8 | F0 | HDS=3, VDS=3 (512 x 512 display domain), PGS=0 (64x32 page) |
| R#9 | 00 | PTS=8x8 patterns, SLH=SLV=0 (whole-screen scroll) |
| R#10 | 40 | SPA=1, SPAS=0 → all sprites 16x16, no flip, SPRD=0 |
| R#11 | 00 | PRM=0 (sprites above plane A above plane B), no transparency enables |
| R#12 | 00 | colour from attribute bits (no colour-fetch modes) |
| R#13 | FF | border colour |
| R#14 | 01 | vblank IRQ enabled |
| R#15/16 | DC/DC | raster IRQ position (unused, mask off) |
| R#17–24 | 00 | base addresses |
| R#25–38 | 0 except R#29=02, R#36=02 | ROZ identity at boot; the title animation (frames ~330-700) sets ZRON and rotates/zooms the Namco logo (docs/ygv608.md §10) |
| R#39 | 62 | HSW=3 (48 dots), HBW=2 (32 dots) |
| R#40 | 64 | HDW=36 (576 units → 288 pixels), HTL[9:8]=01 |
| R#41 | 36 | HDS=0x36 → display start 108 |
| R#42 | 92 | HTL[7:0] → htotal 804 |
| R#43 | 60 | VSW=3, VBW=0 |
| R#44 | 1C | VDW=28 → 224 lines |
| R#45 | 9A | VTL[8]=1, VDS=26 |
| R#46 | 05 | VTL[7:0] → vtotal 261 |

These are the boot values. The games switch modes freely: the frozen-state
corpus (`artifacts/states/`, `tools/make_corpus.sh`) covers MD 0-3, 8x8 and
16x16 patterns, row and column scroll, both priority modes, both sprite aux
modes, and ROZ.

### 4.2 Timing

MAME's screen is 402 x 261 at 6.144 MHz (58.56 Hz) until the game programs the
CRTC in frame 41; from then on MAME runs 264 x 384 dot clocks per frame
(60.6 Hz). The real board measures 15.47 kHz / 59.96 Hz `[GURU]`, i.e. 258
lines per frame and ~409.3 dot clocks per line at 25.326/4 = 6.3315 MHz. The
core (docs/core-design.md §4) runs 414 x 258 at 6.4 MHz: 15.459 kHz, 59.92 Hz,
with the vblank interrupt at the start of line 250 (the first line after the
224 visible ones).

### 4.3 Pattern name table (mode MD=2, 64x32 page, 8x8) `[MAME]`

Two bytes per cell, cell index = row*64 + col, byte 0 = pattern name low 8
bits, byte 1: bits 3:0 = pattern name bits 11:8 (masked by NA8 = 0F when
FLIP=0), bits 7:4 = colour (16-colour palette bank). Pattern number is then
`+ scroll_table[0xC0 + page] << 10` and `+ base_addr[row >> 3] << 8`, then
`+ gfxbank * 0x10000`. Page selection uses the plane's scroll x/y (§4.4) and
the 64x32 page: page = ((sx + col*8) % 2048) / 256 + (((sy + row*8) % 2048) /
512) * 8, masked to 5 bits.

### 4.4 Scroll tables `[MAME]`

Per plane, 256 bytes: [0x00..0x01] scroll y (12 bits, low byte first, per
column when SLV != 0), [0x80..0x81] scroll x (12 bits), [0xC0 + page] the
page's pattern-name high bits.

### 4.5 Sprites `[MAME]`

64 entries x 4 bytes: sy[7:0], sx[7:0], attr (7:4 colour, 3:2 size/flip
selected by SPAS, 1 = sx bit 8, 0 = sy bit 8), pattern name (8 bits). The
16x16 pattern code is `(sprite_bank & FC) << 6 | sn`, plus `gfxbank * 0x4000`.
Drawn last-entry-first (entry 63 first, so entry 0 is on top), transparent
pen 0, position (sx, sy + 1) & 1FF with wraparound at 512, clipped to 512x512.

### 4.6 Pattern data format `[MAME]`

4bpp, 16 planes packed: the 8x8 4-bit layout `pts_4bits_layout` places the
8 rows of an 8x8 pattern at word offsets using x offsets `STEP8(n*256, 4)` and
y offsets `STEP8(n*256, 32)`. In bytes: an 8x8 tile occupies 32 bytes; pixel
(x, y) of tile t is nibble `(t*32 + y*4 + x/2)`, high nibble first. 16x16
tiles are four 8x8 tiles in the order (0,0) (1,0) (0,1) (1,1) at t, t+1,
t+4?, ... — see `tools/render_model.py` for the exact decode, verified
against MAME's `pts_4bits_layout_xoffset/yoffset` tables.

### 4.7 Palette `[MAME]`

256 entries of 3 bytes (R, G, B), 6 significant bits each (`pal6bit`), written
through P#3 with auto-increment; entry 0 of each 16-colour bank is transparent
for sprites, and for planes only when transparency is enabled (not in ncv1).

## 5. Sound `[MAME c352.cpp]`

Namco C352, 32 voices, 8-bit linear or 8-bit mu-law samples from the 2 MB
`nc1voice.7b` (24-bit address, 16 MB max), 4 outputs of which the board wires
front-left/front-right (the second DAC is not fitted). Sample clock 85.333
kHz. Per-voice registers (8 x 16-bit): vol_f, vol_r, freq, flags, wave_bank,
wave_start, wave_end, wave_loop; global 0x200 control, 0x202 key-on/off
execute. Volume ramps one step per counter overflow; linear interpolation
between samples unless FILTER flag set. Output = sum(voice) >> 3.

## 6. ROM sets `[MAME]`

Vol.1 (`ncv1`, 1995: Galaga, Xevious, Mappy) and Vol.2 (`ncv2`, 1996: Pac-Man,
Rally-X, Dig Dug) are the same board and the same MAME machine
(`namcond1_state::namcond1`, same maps, same inputs, ROT90). They differ in
the ROMs only, and Vol.2 populates the second character-ROM socket.

Vol.1:

| File | Size | CRC32 | Region |
|---|---|---|---|
| nc2main0.14d | 512 KB | 4ffc530b | 68000 0x00000 (16-bit words) |
| nc2main1.13d | 512 KB | 26499a4e | 68000 0x80000 |
| nc1sub.1c | 512 KB | 48ea0de2 | H8 0x00000 |
| nc1cg0.10c | 2 MB | d4383199 (MAME ≥ 0.271), 355e7f29 (MAME ≤ 0.270) | YGV608 pattern ROM, mirrored across the 8 MB space |
| nc1voice.7b | 2 MB | 91c85bd6 | C352 samples |

The user's set carries the older `nc1cg0.10c`; the builder accepts both CRCs.

Vol.2:

| File | Size | CRC32 | Region |
|---|---|---|---|
| ncs2main0.14e | 512 KB | fb8a4123 | 68000 0x00000 |
| ncs2main1.13e | 512 KB | 7a5ef23b | 68000 0x80000 |
| ncs1sub.1d | 512 KB | 365cadbf | H8 0x00000 (a different sub program from Vol.1's) |
| ncs1cg0.10e | 2 MB | fdd24dbe | YGV608 pattern 0x000000, mirrored at 0x200000 |
| ncs1cg1.10f | 2 MB | 007b19de | YGV608 pattern 0x400000, mirrored at 0x600000 |
| ncs1voic.7c | 2 MB | ed05fd88 | C352 samples |

Some romsets name the second character ROM `ncs1cg1.10e`; the builder finds
it by CRC.

Both build into the same 7,864,320-byte image (`ncv1.mra`, `ncv2.mra`):

| Offset | Size | Contents |
|---|---|---|
| 0x000000 | 1 MB | 68000 program |
| 0x100000 | 512 KB | H8/3002 program |
| 0x180000 | 2 MB | character ROM, chip 0 (pattern space 0x000000-0x3FFFFF) |
| 0x380000 | 2 MB | C352 samples |
| 0x580000 | 2 MB | character ROM, chip 1 (pattern space 0x400000-0x7FFFFF); Vol.1 repeats chip 0 |

The first 5.5 MB are the layout the Vol.1-only core (0.1.0) used; chip 1 was
appended so nothing else moved. MAME flags Vol.2 `UNEMULATED_PROTECTION`
(the cuskey at C3FF00 returns 0 where the real part returns a jump vector);
the games run in MAME regardless, and this core reproduces MAME's behaviour.
What Vol.2 exercises that Vol.1 does not: gfx bank and character chip 1, a
full-screen 16x16 8bpp ROZ plane at identity (Rally-X attract), and in the
sub program `jsr @aa:24` in its main polling loop (about 1,000 a frame,
against 11 in Vol.1), which is how a 2-state error in that instruction's cost
surfaced (core-design.md section 3.2).

## 7. Open questions

- Exact YGV608 line/frame timing: no datasheet found; the core uses the
  board's measured rate (§4.2).
- EEPROM contents for first boot: MAME boots with a blank one and the game
  initialises it; the Pocket's empty save slot does the same.
