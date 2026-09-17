#!/bin/sh
# Sub-CPU system bench: ncv1_sub (H8/3002 + on-chip peripherals + decode) replaying the
# MAME capture in $H8DIR (default artifacts/h8) -- see sim/tb_sub.cpp.
set -e
cd "$(dirname "$0")/.."
ROM=${ROM:-artifacts/ncv1.rom}
DIR=${H8DIR:-artifacts/h8}
verilator --cc --exe --build -j 4 -O2 -Wno-fatal -Wno-MULTIDRIVEN --public-flat-rw \
    --top-module ncv1_sub -Mdir sim/obj_sub rtl/h8300h.sv rtl/h83002.sv rtl/ncv1_sub.sv sim/tb_sub.cpp -o tb_sub > sim/obj_sub.log 2>&1 || { tail -30 sim/obj_sub.log; exit 1; }
sim/obj_sub/tb_sub "$ROM" "$DIR" ${1:-}
