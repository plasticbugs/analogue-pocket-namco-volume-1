#!/bin/sh
# Capture the H8/3002 trace-replay sets from MAME (tools/trace_h8.lua):
#   artifacts/h8            Vol.1 boot, frames 66-68
#   artifacts/h8_game       Vol.1 Galaga play, frames 2200-2212
#   artifacts/h8_ncv2       Vol.2 boot, frames 120-122
#   artifacts/h8_ncv2_game  Vol.2 Pac-Man arrangement play, frames 3400-3420
#   tools/capture_h8.sh [set...]      (default: all four)
# MAME writes the access log to ./error.log, so the captures run one at a time.
set -e
cd "$(dirname "$0")/.."
cap() {  # dir game t0 frames inputs
    D=$1; G=$2
    echo "== $D"
    mkdir -p "artifacts/$D"; rm -f error.log
    GAME=$G SCRATCH=${SCRATCH_BASE:-/tmp/ncv1-mame}/cap_$D NCV1_OUT=artifacts/$D NCV1_T0=$3 NCV1_FRAMES=$4 NCV1_INPUTS="$5" \
        tools/mame_run.sh tools/trace_h8.lua -debug -debugger none -log > /dev/null 2>&1
    mv error.log "artifacts/$D/h8_access_log.txt"
    wc -l < "artifacts/$D/h8trace.log"
}
SETS=${*:-h8 h8_game h8_ncv2 h8_ncv2_game}
for s in $SETS; do
    case $s in
    h8)           cap h8 ncv1 66 2 "" ;;
    h8_game)      cap h8_game ncv1 2200 12 "400:Coin 1:8,500:1 Player Start:8,700:P1 Up:8,720:P1 Up:8,900:P1 Button 1:8,1100:P1 Up:8,1300:P1 Button 1:8,1700:1 Player Start:8,2100:P1 Button 1:6,2203:P1 Button 1:6,2206:P1 Left:40" ;;
    h8_ncv2)      cap h8_ncv2 ncv2 120 2 "" ;;
    h8_ncv2_game) cap h8_ncv2_game ncv2 3400 20 "1400:Coin 1:8,1500:1 Player Start:8,1900:P1 Button 1:8,2100:P1 Right:8,2300:P1 Button 1:8,2600:1 Player Start:8,2750:1 Player Start:8,2900:1 Player Start:8,3380:P1 Left:60" ;;
    *) echo "unknown set $s"; exit 2 ;;
    esac
done
