#!/bin/sh
# Run every frozen state in artifacts/states/ (MAME captures) and
# artifacts/states_synthetic/ (edited captures for modes the games never use,
# e.g. FLIP=1) through the YGV608 RTL bench (Vol.2 states, named ncv2_*,
# against the Vol.2 image) and require zero differing pixels
# against the reference renderer.
#   tools/regress_video.sh [state-glob]
cd "$(dirname "$0")/.."
fail=0; n=0; worst=0
for st in artifacts/states/${1:-*}.txt artifacts/states_synthetic/${1:-*}.txt; do
    [ -f "$st" ] || continue
    case "$st" in artifacts/states/*) [ -f "${st%.txt}.png" ] || continue ;; esac
    n=$((n+1))
    case $(basename "$st") in ncv2_*) rom=artifacts/ncv2.rom ;; *) rom=artifacts/ncv1.rom ;; esac
    if out=$(ROM=$rom sim/run_video.sh "$st" 2>&1); then
        w=$(echo "$out" | sed -n 's/.*worst line \([0-9]*\) clocks.*/\1/p')
        [ -n "$w" ] && [ "$w" -gt "$worst" ] && worst=$w
        echo "PASS $(basename "$st" .txt) (worst line $w clocks)"
    else
        fail=$((fail+1))
        echo "FAIL $(basename "$st" .txt)"
        echo "$out" | grep -E "^diff|BENCH|FAIL" | head -5
    fi
done
echo "$n states, $fail failed, worst line $worst clocks (budget 6210)"
[ "$fail" -eq 0 ]
