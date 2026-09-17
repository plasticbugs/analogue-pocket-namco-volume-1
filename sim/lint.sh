#!/bin/sh
# Lint every RTL file the core synthesises. Run before every push: it catches
# syntax and inference errors in seconds, where a broken push costs a whole
# CI cycle. The vendored fx68k is waived by path in sim/waivers.vlt; nothing
# under rtl/ is waived wholesale.
set -e
cd "$(dirname "$0")/.."
verilator --version >/dev/null 2>&1 || { echo "verilator not found"; exit 2; }

PROBE=$(mktemp -d)
trap 'rm -rf "$PROBE"' EXIT
echo 'module lintprobe; endmodule' > "$PROBE/lintprobe.v"
WANT="DECLFILENAME UNOPTFLAT PINCONNECTEMPTY PINMISSING GENUNNAMED TIMESCALEMOD BLKANDNBLK MULTIDRIVEN"
FLAGS="-Wall -Irtl +1364-2005ext+v sim/waivers.vlt"
for w in $WANT; do
    if verilator --lint-only "-Wno-$w" "$PROBE/lintprobe.v" >/dev/null 2>&1; then
        FLAGS="$FLAGS -Wno-$w"
    fi
done

RTL="$(ls rtl/*.sv 2>/dev/null)"
VENDOR="modules/cpu-fx68k/fx68k.sv modules/cpu-fx68k/fx68kAlu.sv modules/cpu-fx68k/uaddrPla.sv"

for top in h8300h h83002 ncv1_sub ncv1_main ygv608 c352 rom_cache shared_ram at28c16 clk_enables; do
    grep -q "^module $top\b" rtl/*.sv 2>/dev/null || continue
    echo "--- $top ---"
    verilator --lint-only $FLAGS --top-module $top $RTL $VENDOR
done
echo "--- whole machine ---"
verilator --lint-only $FLAGS --top-module ncv1_core $RTL $VENDOR
echo "--- pocket memories ---"
verilator --lint-only $FLAGS sim/waivers_platform.vlt --top-module ncv1_mem \
    target/pocket/ncv1_mem.sv target/pocket/sdram_ctrl.sv
echo "lint clean"
