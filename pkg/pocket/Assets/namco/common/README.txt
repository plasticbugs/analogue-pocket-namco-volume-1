Namco Classic Collection Vol.1 for Analogue Pocket - the ROM image
==================================================================

This folder must hold ONE file:

    Assets/namco/common/ncv1.rom
    (5,767,168 bytes)

The core does not include any game data. You build ncv1.rom yourself from
your own copy of the MAME romset "ncv1" (Namco Classic Collection Vol.1,
Namco 1995; ncv1.zip, or a folder of its five files).

How to build it
---------------
1. Put ncv1.zip next to the two files at the top of this release:
   ncv1.mra (the recipe) and mra_build.py (the builder).

2. Run, with any Python 3 -- nothing else to install:

       python3 mra_build.py ncv1.mra ncv1.zip

   It checks every ROM's CRC32 against the .mra and writes ncv1.rom. A wrong
   or incomplete romset stops with an error naming the file it did not like.
   Both known dumps of nc1cg0.10c are accepted (CRC 355e7f29, listed by MAME
   up to 0.270, and d4383199, listed from 0.271).

3. Copy ncv1.rom into this folder on the SD card.

What the image contains (docs/hardware.md, section 6, in the repository)
------------------------------------------------------------------------
    0x000000  1,048,576  68000 program       nc2main0.14d + nc2main1.13d
    0x100000    524,288  H8/3002 program     nc1sub.1c
    0x180000  2,097,152  YGV608 patterns     nc1cg0.10c
    0x380000  2,097,152  C352 samples        nc1voice.7b

Settings and high scores are kept in the game's EEPROM, which the Pocket saves
as ncv1.sav in its Saves folder.
