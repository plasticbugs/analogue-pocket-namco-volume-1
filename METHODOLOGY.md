# Building an arcade-accurate openFPGA core

Method, tooling and hard-won lessons from the Xenophobe (Midway MCR-68000)
core, written to bootstrap Time Pilot. Everything here was learned by doing it
once; the sections marked **cost me time** are the ones worth reading twice.

---

## 1. The central idea

Three artefacts, in this order. Each one makes the next cheaper.

**MAME is the oracle.** Not a reference to read — a program to interrogate. Its
Lua interface can tap memory writes, force inputs, dump RAM, record audio and
snapshot frames. Nearly every question about "what does the real hardware do
here" is answerable in a few minutes with a Lua script, and the answer is
authoritative. Guessing instead is what cost me the most time on Xenophobe.

**A reference renderer is the executable spec.** Before writing video RTL, write
a Python program that reads a dumped machine state (VRAM, sprite RAM, palette)
and produces the exact frame MAME produces. Iterate until it is pixel-identical
on a spread of frames. Now you own a precise, readable statement of the video
hardware's semantics — priority rules, transparency, coordinate maths — and you
can consult it while writing RTL instead of re-deriving from MAME's C++.

**Frozen-state benches are the regression gate.** Load a dumped state directly
into the RTL's memories, render one frame in Verilator, diff against the
reference renderer. Roughly 30 seconds per run. Every video change gets checked
against a set of states before it goes near hardware. On Xenophobe this held at
zero differing pixels across seven states, including the heaviest sprite load
found in real play, and caught several "optimisations" that were wrong.

The pattern generalises: **make the correct answer cheap to compute, then check
against it constantly.**

---

## 2. Toolchain

| Tool | Role | Notes |
|---|---|---|
| MAME (`brew install mame`) | Oracle | Use `-video none -sound none -nothrottle -skip_gameinfo`, and always `-cfg_directory`/`-nvram_directory` pointing somewhere disposable |
| MAME Lua (`-autoboot_script`) | Instrumentation | `install_write_tap`, `register_frame_done`, `ioport` fields, `machine.video:snapshot()`, `-wavwrite` |
| Verilator | RTL simulation | Fast enough for whole-frame and whole-second simulations |
| Quartus 18.1 in Docker | Synthesis | `raetro/quartus:pocket`, `--platform linux/amd64` on Apple silicon |
| Ghidra (optional, via MCP) | Disassembly | Only as far as needed to answer specific questions |
| Python 3 | Everything else | Reference renderer, image diffing, ROM building, audio analysis. No numpy needed |

Two Quartus habits worth keeping:

- `quartus_map` alone (~2 min) catches syntax and inference errors without a
  full fit. Run it before every push. I once pushed a "fix" that referenced a
  nonexistent bit and burned a CI cycle discovering it.
- The full compile runs in CI on every push. Builds take ~20 minutes, so treat
  a build as expensive and verify everything verifiable beforehand.

---

## 3. Workflow

**Phase 1 — map the hardware.** Read MAME's driver for memory maps, IRQ sources,
clock rates and input bit assignments. Write it into `docs/hardware.md` as you
go; you will consult it constantly. Record exact clock frequencies — they matter
more than you expect (see §5.3).

**Phase 2 — build the ROM path first.** Write the tool that turns the user's
MAME romset into whatever image the core loads, and verify each ROM's CRC while
doing it. Get this right early: every later test depends on having correct data
in the right place.

**Phase 3 — reference renderer.** Dump states from MAME with Lua, render them in
Python, diff against MAME's snapshots until pixel-identical. Expect to discover
non-obvious semantics here — Xenophobe's sprite priority turned out to be
first-wins per priority class, with pen 8 claiming a pixel invisibly, which no
amount of staring at RTL would have revealed.

**Phase 4 — RTL against the frozen bench.** Build the video core and check every
change against the reference renderer. Only then integrate into the platform.

**Phase 5 — full system.** Both CPUs, real memory paths, audio capture. Slower
(~20 min for a few hundred frames), so use it for integration questions, not
iteration.

**Phase 6 — hardware.** Reserve for faults that cannot be reproduced in
simulation. Add an on-screen diagnostic overlay before you need it.

---

## 4. Verification recipes

**Dump a machine state from MAME:**

```lua
local sp = manager.machine.devices[":maincpu"].spaces["program"]
local f = io.open("state.txt", "w")
f:write("VRAM\n")
for i = 0, 2047 do f:write(string.format("%04x\n", sp:read_u16(VRAM_BASE + i*2))) end
f:close()
manager.machine.video:snapshot()
```

**Drive the game to a specific situation** with `ioport` fields and a frame
counter — coin at frame N, start at N+20, and so on. This is how you reach
gameplay states worth capturing.

**Watch a value the CPU writes** with `install_write_tap` on the relevant range.
Note that a tap may not see accesses that go through an installed write handler;
if a tap comes back empty, instrument your own RTL instead.

**Compare audio against MAME** by sending the same sound command in both and
recording with `-wavwrite`. Compare peak, RMS and per-band energy. This is how I
proved our output was 6 dB low: same command, same window, ratio 2.06.

**Diagnostic overlay on hardware:** a few rows of coloured squares on the bottom
scanlines, each a status bit, hidden behind a menu option. Cheap in logic, and
the only way to see inside a fault that only appears on real hardware.

---

## 5. Key learnings

### 5.1 Measure before you diagnose — and check the instrument

**Cost me time, repeatedly.** I announced confident causes three times on the
audio problem alone: bus contention, then downstream clipping, then a truncation
bug. Measurement killed all three. What eventually found it was one user
observation I could not explain away.

Worse, I once "fixed" a bug that existed only in my measurement harness:
Verilator exposes ports unsigned, so reading a signed 16-bit sample without a
cast made clean audio look railed and full of harmonics. **When a measurement
shows something shocking, suspect the harness first.**

Practical rules that emerged:

- A theory that explains only some of the observations is wrong, not incomplete.
- If a change is meant to fix something, predict the measurement it should move,
  and check that specific number.
- State plainly when you cannot reproduce something. Shipping a speculative fix
  costs the user a build cycle and teaches you nothing.

### 5.2 Budget bandwidth explicitly

Write down the cycle budget per scanline and what consumes it. On Xenophobe:
1270 clocks per line; a full sprite-table scan cost 512 of them; each sprite cost
~75 more (38 fetch, 32 blend, ~5 attribute reads). That arithmetic said ~10
sprites per line, and sampling real gameplay in MAME found lines needing 17. The
mismatch *was* the flicker — the engine ran out of time, skipped starting the
next line, and rendered sprites on alternating lines.

Two fixes, both measurable: snapshot sprite RAM during vblank and record the
highest used entry so the scan stops there; and overlap each sprite's fetch with
the previous sprite's blend so cost becomes `max(38, 32)` rather than the sum.
Worst line went from 1270 clocks and overrunning to 807 with room spare.

**For Time Pilot this whole category likely disappears** — see §6.

### 5.3 Sound boards have no slack

The Sounds Good board has no timer. Its only interrupt is a command handshake,
so the sound CPU's *execution rate is the sample rate*: bandwidth it loses
becomes pitch and tempo error, directly. Ours ran ~20% slow because its ROM
fetches crossed SDRAM with wait states that real hardware does not have.

Two general lessons:

- **Find out what paces the audio.** If it is a timer, CPU speed only affects
  whether it keeps up. If it is the CPU itself, every stall is audible.
- Game logic is usually frame-locked to the video interrupt, so it tolerates
  stalls invisibly. Audio does not. A core can feel perfect and still have
  audibly wrong sound.

Fix was a small direct-mapped cache over the sound ROM — trivially safe because
the ROM is read-only, so entries can never go stale. Restored 99.6–99.9% of
hardware rate.

### 5.4 Clock domain crossings — the bug that hid from everything

**The most valuable lesson here.** Audio conditioning ran on the 40 MHz core
clock; the Pocket's audio filter runs on a PLL derived from `clk_74b`. The
16-bit sample bus crossed between them unsynchronised. The audio side could latch
a mix of old and new bits, and a torn 16-bit sample is not a small error — one
flipped high bit throws the value across the range. Heard as clicks and static.

It defeated every measurement because **both sides were individually correct**.
Our rendering matched MAME within a few percent across 8 seconds of music; the
mixer measured at unity gain with no saturation. The fault existed only in the
handoff, which no simulation of either side can show.

Most cores never hit this: their audio changes only at the sound chip's sample
rate, so the bus is still between updates. Ours carried a filtered value moving
every 40 MHz cycle — never stable.

```systemverilog
// sample at ~48 kHz, hold, hand over with a toggle flag
always_ff @(posedge clk_sys) begin
    snd_div <= snd_div + 1'd1;
    if (snd_div == DIV_48K) begin
        snd_div <= '0; snd_hold <= snd_pcm; snd_tog <= ~snd_tog;
    end
end
always_ff @(posedge clk_74b) begin
    snd_tog_s <= {snd_tog_s[1:0], snd_tog};
    if (snd_tog_s[2] != snd_tog_s[1]) snd_xfer <= snd_hold;  // stable by now
end
```

**Audit every multi-bit signal that crosses a clock domain, at the start.** For
Time Pilot the AY-3-8910 outputs will cross exactly this boundary.

### 5.5 openFPGA platform traps

**`input.json` does not mean what it looks like.** List *position* selects the
physical button, in the order **B, A, X** (Game Boy convention, not A first).
The `key` field does **not** choose the button — it names the `cont1_key` bit the
core reads when that button is pressed. So an entry declaring `pad_btn_x` in
position 2 is correct and deliberate: A sits in position 2 and asserts the bit
the gateware routes to that function. Reordering entries changes which pad does
what; changing a key changes which game input it drives.

**The Pocket persists a per-`id` remap** in
`/Settings/<core>/Input/_core/input_persist.json`, binding entry ids to physical
buttons. Reuse an id whose meaning changed and the saved file silently overrides
your defaults — buttons appear rotated. **Give entries fresh ids whenever the
layout changes.** This cost several rounds of confusing hardware testing.

**Valid keycodes** are `pad_btn_a/b/x/y`, `pad_trig_l/r`, `pad_btn_start`,
`pad_btn_select`. `pad_select` is not one; an invalid key silently does nothing.

**`info.txt`** drives the core's detail page: max 32 lines, plain characters,
`*` for bullets.

**Byte-enable inference:** partial-select writes like `mem[a][7:0] <= x` fail to
infer byte enables in Quartus and explode into registers. Use 2D-packed
(`logic [1:0][7:0]`) and word-buffered writes.

### 5.6 Release engineering

- **Release the bitstream you tested**, not a fresh compile of the same source.
  Quartus is not reproducible, and a rebuild is an unverified artefact.
  `tools/cut-release.sh <tag> <run-id>` pulls the bitstream from a named CI run
  and takes everything else from the working tree — which also means a
  definition-only change ships without a rebuild.
- **Never ship ROMs.** A gitignored test ROM in the package directory nearly went
  into a published zip; the release script's final check caught it. Exclude at
  the copy step *and* keep the check as a backstop.
- **Releases are immutable.** Tools track assets by tag; replacing a file leaves
  people holding a stale copy silently. Cut a new tag.
- Verify the published zip by downloading it: version, bitstream checksum, no
  ROM, expected files present.

### 5.7 ROM distribution

A core is FPGA gateware — it cannot unzip a romset or run a script. The ROM must
be assembled on a computer. Ship an **MRA file** (the arcade standard, so
existing tools work) plus a dependency-free Python builder that reads the MAME
zip directly, checks each CRC, and verifies the finished image against a known
checksum.

MRA's `map` attribute: each digit is one byte of the output word, left to right;
the value is the 1-based byte of the input part. Verify against a known-good
reference — in MAME's `f1dreama` the even-offset ROM carries `map="10"`, which
establishes that the left digit is the first byte of the word.

---

## 6. Time Pilot: what changes

From `mame -listxml timeplt`:

| | Xenophobe | Time Pilot |
|---|---|---|
| Main CPU | 68000 @ 7.72 MHz | **Z80 @ 3.072 MHz** |
| Sound CPU | 68000 @ 8 MHz | **Z80 @ 1.789772 MHz** |
| Sound | software DAC (10-bit) | **2× AY-3-8910A @ 1.789772 MHz** + RC filters |
| Display | 512×480 | **256×224, rotated 90°**, 60 Hz |
| ROM total | 832 KB | **53 KB** |

**The big simplification: 53 KB fits entirely in block RAM.** The Cyclone V
5CEBA4 has ~393 KB. That removes SDRAM completely — and with it the arbiter, the
fetch latency, the sprite bandwidth budget, and the sound-CPU starvation that
between them accounted for most of the Xenophobe effort. Load everything into
BRAM at startup and every access is single-cycle and deterministic. **Do this.**

What to expect instead:

- **Z80 core**: T80 is the standard choice, widely used and well proven.
- **AY-3-8910**: use a proven implementation (jt49 or similar) rather than
  writing one. Real chips, so tempo comes from the chip's own clock, not CPU
  speed — §5.3 does not apply, but §5.4 very much does: the AY outputs still
  cross into the Pocket's audio domain.
- **PROMs**: `timeplt.b4`/`b5` (32 bytes) are colour PROMs, `e9`/`e12` (256
  bytes) lookup PROMs. Palette and tile/sprite colour resolution go through
  these — model them in the reference renderer first.
- **Rotation**: the Pocket handles rotated displays, but confirm the orientation
  and scaling early. It affects how you compare against MAME snapshots.
- **RC filters**: MAME models them explicitly. Read the coefficients from the
  driver rather than approximating — Xenophobe's three one-pole sections stood in
  for a five-pole design and left the output measurably darker in the passband
  and leakier above it.

Suggested order: ROM builder → reference renderer (with PROM colour resolution)
→ tilemap → sprites → frozen-state gate → Z80 + memory map → AY sound → platform
integration → hardware.

---

## 7. Worth copying from the Xenophobe repo

| Path | What it does |
|---|---|
| `tools/render_model.py` | Reference renderer + diff against MAME snapshot |
| `tools/diff_frames.py` | Pixel diff with per-cell hotspots and a visual diff image |
| `tools/regress_video.sh` | Runs every frozen state through the RTL and checks for zero differences |
| `tools/mra_build.py` | MRA interpreter; builds the ROM from a MAME zip, CRC-checked |
| `tools/cut-release.sh` | Publishes a release from a named CI run's bitstream |
| `tools/fetch_build.sh` | Stages and verifies a CI build before replacing an SD package |
| `sim/run_video.sh` | Frozen-state video bench (~30 s) |
| `sim/tb_audio.sv` | Measures the Pocket audio filter chain's gain |
| `.github/workflows/compile.yml` | Quartus in Docker, artifact upload, tag-triggered release |
| `target/pocket/core_top.sv` | APF integration, diagnostic overlay, audio CDC |

The platform directory (`platform/pocket/`) and the APF framework transfer
wholesale; only `core_top.sv` and the `rtl/` contents are game-specific.

---

## 8. If I were starting again

1. Read MAME's driver properly and write `docs/hardware.md` first.
2. Build the ROM path and CRC-check it.
3. Get the reference renderer pixel-perfect before writing video RTL.
4. Put everything in BRAM if it fits. It removes entire categories of bugs.
5. Audit clock-domain crossings before integration, not after.
6. Find out what paces the audio, and verify its rate against MAME early.
7. Add the diagnostic overlay before you think you need it.
8. Verify anything verifiable before spending a 20-minute build.
9. When a user reports something you cannot reproduce, believe the report and
   distrust the theory.
