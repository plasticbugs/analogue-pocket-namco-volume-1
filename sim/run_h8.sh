#!/bin/sh
# H8/300H trace-replay bench: sim/tb_h8.cpp over rtl/h8300h.sv against the
# MAME capture in artifacts/h8 (tools/trace_h8.lua).
#   sim/run_h8.sh [max_instructions]
set -e
cd "$(dirname "$0")/.."
ROM=${ROM:-artifacts/ncv1.rom}
DIR=${H8DIR:-artifacts/h8}
verilator --cc --exe --build -j 4 -O2 -Wno-fatal -Wno-MULTIDRIVEN --public-flat-rw \
    --top-module h8300h -Mdir sim/obj_h8 rtl/h8300h.sv sim/tb_h8.cpp -o tb_h8 > sim/obj_h8.log 2>&1 || { tail -30 sim/obj_h8.log; exit 1; }
sim/obj_h8/tb_h8 "$ROM" "$DIR" ${1:-}
