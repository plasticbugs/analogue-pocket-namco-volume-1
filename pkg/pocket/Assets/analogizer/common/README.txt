Analogizer - the shared configuration file
==========================================

This folder is where the Analogizer adapter's settings live, and it is shared
by every Analogizer-capable core on the card, not just this one:

    Assets/analogizer/common/analogizer.bin

The file is not included, and this core works without it: with no file the
adapter stays off and the cartridge pins stay in high impedance.

Make it with either of these, both of which write it straight into this
folder:

    Pupdate 5.6.0 or newer
      https://github.com/mattpannella/pupdate/releases
    Analogizer Configurator 0.7 or newer
      https://github.com/RndMnkIII/AnalogizerConfigurator/releases

Everything except the on/off switch is in that one file: the video output mode
(RGBS, RGsB, YPbPr, Y/C NTSC, Y/C PAL, SVGA scandoubler), the SNAC controller
type and how its pads map onto players, and whether the Pocket's own screen is
blanked. Set ANALOGIZER ENABLE OPTIONS: ON to turn it on.

Two things worth knowing before you plug anything in:

  * This core powers the cartridge slot for everyone, adapter or not, because
    that is where the adapter takes its power from. Do not leave a game
    cartridge in the slot while running it.

  * The Namco ND-1 drives a vertically mounted monitor, and the analog output
    is the board's own 288x224 raster at 15.46 kHz and 59.92 Hz, exactly as
    the board scans it. Nothing rotates it, so a CRT has to be turned on its
    side as the cabinet's was.

The adapter, its cases, the SNAC harnesses and the wiki that documents all of
it are RndMnkIII's:

    https://github.com/RndMnkIII/Analogizer

Analog video and SNAC problems belong there. Problems with this core's raster,
its colours, which buttons a SNAC pad lands on, or the Pocket's own picture
and sound belong in this core's issue tracker. None of the Analogizer support
in this core has been tested on hardware: nobody working on it owns an
adapter.
