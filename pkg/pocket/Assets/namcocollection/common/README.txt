Namco Classic Collection for Analogue Pocket - the ROM images
=============================================================

This folder holds one image per collection. Build the ones you have:

    Assets/namcocollection/common/ncv1.rom    Vol.1: Galaga, Xevious, Mappy
    Assets/namcocollection/common/ncv2.rom    Vol.2: Pac-Man, Rally-X, Dig Dug
    (7,864,320 bytes each)

The core does not include any game data. You build each image yourself from
your own copy of the MAME romset: "ncv1" (Namco Classic Collection Vol.1,
Namco 1995) and "ncv2" (Namco Classic Collection Vol.2, Namco 1996), as a zip
or a folder of loose files.

The Pocket lists the two collections by name. Those entries are the .json
files one folder up, in

    Assets/namcocollection/plasticbugs.namcocollection/

so that folder and this one both have to be on the card. A collection whose
image is missing simply will not load; the other still works.

How to build them
-----------------
1. Put ncv1.zip and/or ncv2.zip next to the files at the top of this release:
   ncv1.mra and ncv2.mra (the recipes) and mra_build.py (the builder).

2. Run, with any Python 3 -- nothing else to install:

       python3 mra_build.py ncv1.mra ncv1.zip
       python3 mra_build.py ncv2.mra ncv2.zip

   It checks every ROM's CRC32 against the .mra and writes ncv1.rom or
   ncv2.rom. A wrong or incomplete romset stops with an error naming the file
   it did not like. For Vol.1, both known dumps of nc1cg0.10c are accepted
   (CRC 355e7f29, listed by MAME up to 0.270, and d4383199, listed from
   0.271). For Vol.2, the second character ROM is found by its CRC whether it
   is named ncs1cg1.10f (MAME) or ncs1cg1.10e.

3. Copy the images into this folder on the SD card.

Images built for version 0.1.0 of this core (5,767,168 bytes, Vol.1 only)
must be rebuilt.

What an image contains (docs/hardware.md, section 6, in the repository)
-----------------------------------------------------------------------
    0x000000  1,048,576  68000 program       main0 + main1
    0x100000    524,288  H8/3002 program     sub
    0x180000  2,097,152  YGV608 patterns     cg0
    0x380000  2,097,152  C352 samples        voice
    0x580000  2,097,152  YGV608 patterns     cg1 (Vol.1 repeats cg0)

Settings and high scores are kept in each collection's EEPROM, which the
Pocket saves as ncv1.sav or ncv2.sav in
Saves/namcocollection/plasticbugs.namcocollection/.
