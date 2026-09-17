#!/usr/bin/env python3
"""Assemble an Analogue Pocket SD-card package from the compiled bitstream.

The Pocket loads a bit-reversed RBF (each byte's bits swapped) named per
core.json ("bitstream.rbf_r"). Output goes to release/pocket/ ready to copy
onto the SD card root.

Never ships a ROM: the copy step excludes them and there is a final sweep that
fails the package if one slipped through anyway.
"""
import os, shutil, sys

ROOT = os.path.dirname(os.path.abspath(__file__))
RBF = os.path.join(ROOT, "projects", "output_files", "ncv1_pocket.rbf")
PKG = os.path.join(ROOT, "pkg", "pocket")
OUT = os.path.join(ROOT, "release", "pocket")
CORE_ID = "plasticbugs.namcocollection"
# The Pocket resolves a data slot to Assets/<platform_id>/common/<filename>.
PLATFORM_ID = "namcocollection"
INSTANCES = {"Namco Classic Collection Vol.1.json", "Namco Classic Collection Vol.2.json"}

if not os.path.exists(RBF):
    sys.exit(f"missing {RBF} - run the Quartus compile first "
             "(and make sure the project generates a compressed RBF)")

REV = bytes(int(f"{b:08b}"[::-1], 2) for b in range(256))
reversed_rbf = bytes(REV[b] for b in open(RBF, "rb").read())

if os.path.exists(OUT):
    shutil.rmtree(OUT)
# ROMs may sit in pkg/pocket/Assets locally (gitignored); never package them.
shutil.copytree(PKG, OUT, ignore=shutil.ignore_patterns('.DS_Store', '*.rom', '*.zip'))

core_dir = os.path.join(OUT, "Cores", CORE_ID)
with open(os.path.join(core_dir, "bitstream.rbf_r"), "wb") as f:
    f.write(reversed_rbf)

# Ship the ROM recipes and their builder alongside the core, so a downloaded
# release contains everything needed to produce ncv1.rom and ncv2.rom.
for extra in ("ncv1.mra", "ncv2.mra", "README.md", os.path.join("tools", "mra_build.py")):
    src = os.path.join(ROOT, extra)
    if os.path.exists(src):
        shutil.copy(src, os.path.join(OUT, os.path.basename(extra)))

# Backstop: the ROM folder must be in the package even though it ships with
# only its README (git drops empty directories).
slot = os.path.join(OUT, "Assets", PLATFORM_ID, "common")
if not os.path.isdir(slot) or not os.listdir(slot):
    sys.exit(f"refusing to package, {os.path.relpath(slot, ROOT)} is missing or empty")

# Backstop: the instance JSONs are how the Pocket lists the two collections;
# a missing one silently drops a collection from the menu.
inst = os.path.join(OUT, "Assets", PLATFORM_ID, CORE_ID)
have = set(os.listdir(inst)) if os.path.isdir(inst) else set()
if INSTANCES - have:
    sys.exit("refusing to package, instance JSON missing:\n  " + "\n  ".join(sorted(INSTANCES - have)))

# Backstop: a gitignored test ROM in the package tree must never reach a release.
strays = [os.path.join(dp, f) for dp, _, fs in os.walk(OUT) for f in fs
          if f.lower().endswith(('.rom', '.zip'))]
if strays:
    sys.exit("refusing to package, ROM files present:\n  " + "\n  ".join(strays))

print(f"packaged -> {OUT}")
print("copy Cores/, Platforms/ and Assets/ from that folder onto the SD card root")
print("build the ROMs with:  python3 mra_build.py ncv1.mra ncv1.zip  /  python3 mra_build.py ncv2.mra ncv2.zip")
