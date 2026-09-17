#!/bin/sh
# C352 replay bench: rtl/c352.sv driven by MAME's captured register writes,
# audio compared against MAME's WAV of the same run (tools/probe_c352.lua).
#   sim/run_c352.sh [frames]
set -e
cd "$(dirname "$0")/.."
ROM=${ROM:-artifacts/ncv1.rom}
LOG=${LOG:-artifacts/c352/galaga_boot_log.txt}
WAV=${WAV:-artifacts/c352/galaga_boot.wav}
OUT=${OUT:-artifacts/c352/rtl_out.wav}
FRAMES=${1:-2400}
[ -f rtl/data/c352_mulaw.hex ] || python3 tools/gen_c352_tables.py
verilator --cc --exe --build -j 4 -O3 -Wno-fatal --public-flat-rw -GHEXDIR='"rtl/data"' \
    --top-module c352 -Mdir sim/obj_c352 rtl/c352.sv sim/tb_c352.cpp -o tb_c352 > sim/obj_c352.log 2>&1 || { tail -30 sim/obj_c352.log; exit 1; }
sim/obj_c352/tb_c352 "$ROM" "$LOG" "$OUT" "$FRAMES" ${CPS:-512}
python3 tools/c352_compare.py "$OUT" "$WAV" --frames "$FRAMES"
