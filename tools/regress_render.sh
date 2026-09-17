#!/bin/sh
# Render every frozen state in artifacts/states/ with the reference renderer
# and require a pixel-exact match with MAME's snapshot of the same frame.
#   tools/regress_render.sh [state-glob]
cd "$(dirname "$0")/.."
ROM=${ROM:-artifacts/ncv1.rom}
fail=0; n=0
for st in artifacts/states/${1:-*}.txt; do
    png=${st%.txt}.png
    [ -f "$png" ] || { echo "SKIP $(basename "$st") (no PNG)"; continue; }
    n=$((n+1))
    if ! python3 tools/render_model.py "$st" --rom "$ROM" --compare "$png" --quiet; then
        fail=$((fail+1))
    fi
done
echo "$n states, $fail failed"
[ "$fail" -eq 0 ]
