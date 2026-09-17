# Vendored modules

Third-party HDL cores copied into the tree -- no submodules, so the build is
self-contained and reproducible. Each keeps its own LICENSE alongside.

| module | upstream | via | licence |
|---|---|---|---|
| cpu-fx68k | fx68k by Jorge Cwik | the Xenophobe core | GPL-3.0 (modules/cpu-fx68k/LICENSE) |

Written here rather than vendored: the H8/300H CPU and H8/3002 peripherals, the
Yamaha YGV608 and the Namco C352 (no open implementations exist), from MAME's
device models (see README.md, Credits).

To update one: re-copy from upstream at the new commit and record it here.
