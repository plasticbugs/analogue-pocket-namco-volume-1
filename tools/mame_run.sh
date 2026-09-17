#!/bin/sh
# Run MAME headless on ncv1 or ncv2 with disposable cfg/nvram dirs and a Lua script.
#   [GAME=ncv1|ncv2] tools/mame_run.sh <script.lua> [extra mame args]
# ROMPATH defaults to the repo root (the ncv1/ and ncv2/ directories or zips inside it).
# A loose ncv2 directory whose second character ROM is named ncs1cg1.10e (MAME
# wants ncs1cg1.10f) is staged under $SCRATCH/roms with the MAME name.
set -e
cd "$(dirname "$0")/.."
SCRIPT=$1; shift
GAME=${GAME:-ncv1}
ROMPATH=${ROMPATH:-$PWD}
SCRATCH=${SCRATCH:-/tmp/$GAME-mame}
mkdir -p "$SCRATCH/cfg" "$SCRATCH/nvram" "$SCRATCH/snap"
if [ "$GAME" = ncv2 ] && [ -d "$ROMPATH/ncv2" ] && [ ! -e "$ROMPATH/ncv2/ncs1cg1.10f" ] && [ -e "$ROMPATH/ncv2/ncs1cg1.10e" ]; then
    mkdir -p "$SCRATCH/roms/ncv2"
    for f in "$ROMPATH"/ncv2/*; do ln -sf "$(cd "$(dirname "$f")" && pwd)/$(basename "$f")" "$SCRATCH/roms/ncv2/"; done
    ln -sf "$(cd "$ROMPATH/ncv2" && pwd)/ncs1cg1.10e" "$SCRATCH/roms/ncv2/ncs1cg1.10f"
    ROMPATH=$SCRATCH/roms
fi
exec mame "$GAME" -rompath "$ROMPATH" -video none -sound none -nothrottle -skip_gameinfo \
    -cfg_directory "$SCRATCH/cfg" -nvram_directory "$SCRATCH/nvram" -snapshot_directory "$SCRATCH/snap" \
    -autoboot_script "$SCRIPT" -seconds_to_run "${SECONDS_TO_RUN:-600}" "$@"
