#!/bin/sh
# Whole-machine bench (sim/tb_system.cpp): boots the ROM image in ncv1_core and
# dumps frames/audio to sim/obj_system/out.
#   sim/run_system.sh <frames> [tb_system args...]
set -e
cd "$(dirname "$0")/.."
ROM=${ROM:-artifacts/ncv1.rom}
OUT=${OUT:-sim/obj_system/out}
mkdir -p "$OUT"
SRC="rtl/*.sv modules/cpu-fx68k/fx68k.sv modules/cpu-fx68k/fx68kAlu.sv modules/cpu-fx68k/uaddrPla.sv"
mkdir -p sim/obj_system
if [ ! -x sim/obj_system/tb_system ] || [ -n "$(find rtl sim/tb_system.cpp -newer sim/obj_system/tb_system 2>/dev/null)" ]; then
    verilator --cc --exe --build -j 4 -O2 -Wno-fatal -Wno-MULTIDRIVEN -Wno-BLKANDNBLK -Wno-TIMESCALEMOD --no-assert-case \
        +1364-2005ext+v -Irtl -Imodules/cpu-fx68k --top-module ncv1_core -Mdir sim/obj_system \
        -GHEXDIR='"../../rtl/data"' $SRC sim/tb_system.cpp -o tb_system > sim/obj_system.log 2>&1 \
        || { tail -30 sim/obj_system.log; exit 1; }
fi
# fx68k reads its microcode with $readmemb relative to the working directory
ln -sf ../../modules/cpu-fx68k/microrom.mem sim/obj_system/microrom.mem
ln -sf ../../modules/cpu-fx68k/nanorom.mem sim/obj_system/nanorom.mem
FRAMES=$1; shift
ROM=$(cd "$(dirname "$ROM")" && pwd)/$(basename "$ROM")
OUT=$(mkdir -p "$OUT" && cd "$OUT" && pwd)
cd sim/obj_system && ./tb_system "$ROM" "$FRAMES" "$OUT" "$@"
