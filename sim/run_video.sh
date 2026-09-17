#!/bin/sh
# YGV608 frozen-state bench: render one frame of a corpus state in the RTL and
# require a pixel-exact match with the reference renderer.
#   sim/run_video.sh <state.txt> [--keep]
set -e
cd "$(dirname "$0")/.."
STATE=$1
[ -n "$STATE" ] || { echo "usage: $0 artifacts/states/<state>.txt"; exit 2; }
ROM=${ROM:-artifacts/ncv1.rom}
OUT=${OUT:-sim/obj_video/out}
mkdir -p "$OUT"
if [ ! -x sim/obj_video/tb_video ] || [ rtl/ygv608.sv -nt sim/obj_video/tb_video ] || [ rtl/ygv608_render.sv -nt sim/obj_video/tb_video ] || [ sim/tb_video.cpp -nt sim/obj_video/tb_video ]; then
    verilator --cc --exe --build -j 4 -O2 -Wno-fatal --top-module tb_video_top -Mdir sim/obj_video \
        rtl/ygv608.sv rtl/ygv608_render.sv sim/tb_video_top.sv sim/tb_video.cpp -o tb_video > sim/obj_video.log 2>&1 \
        || { tail -30 sim/obj_video.log; exit 1; }
fi
name=$(basename "$STATE" .txt)
sim/obj_video/tb_video "$STATE" "$ROM" "$OUT/$name.ppm" | tee "$OUT/$name.log"
python3 tools/render_model.py "$STATE" --rom "$ROM" --out "$OUT/$name.ref.png" --quiet
python3 tools/diff_frames.py "$OUT/$name.ppm" "$OUT/$name.ref.png" "$OUT/$name.diff.png" | tee -a "$OUT/$name.log"
grep -q "^diff 0/" "$OUT/$name.log" && grep -q "BENCH-OK" "$OUT/$name.log" && echo "PASS $name" || { echo "FAIL $name"; exit 1; }
