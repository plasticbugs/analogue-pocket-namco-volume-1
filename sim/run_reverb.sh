#!/bin/sh
# Cabinet reverb bench (sim/tb_reverb.cpp over rtl/nc_reverb.sv): dry path, first
# echo at 29.7 ms, the same tail on both sides, no overflow at full scale.
set -e
cd "$(dirname "$0")/.."
verilator --cc --exe --build -j 4 -O2 -Wno-fatal --top-module nc_reverb -Mdir sim/obj_reverb \
    rtl/nc_reverb.sv sim/tb_reverb.cpp -o tb_reverb > sim/obj_reverb.log 2>&1 || { tail -30 sim/obj_reverb.log; exit 1; }
sim/obj_reverb/tb_reverb
