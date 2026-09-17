#!/bin/sh
# ncv1_mem bench: sim/tb_mem.cpp over target/pocket/ncv1_mem.sv + sdram_ctrl + sim/sdram_model.sv.
#   sim/run_mem.sh [reads per port]
set -e
cd "$(dirname "$0")/.."
verilator --cc --exe --build -j 4 -O2 -Wno-fatal --top-module tb_mem_top -Mdir sim/obj_mem \
    sim/tb_mem_top.sv target/pocket/ncv1_mem.sv target/pocket/sdram_ctrl.sv sim/sdram_model.sv sim/tb_mem.cpp -o tb_mem > sim/obj_mem.log 2>&1 \
    || { tail -30 sim/obj_mem.log; exit 1; }
sim/obj_mem/tb_mem "${ROM:-artifacts/ncv1.rom}" ${1:-}
