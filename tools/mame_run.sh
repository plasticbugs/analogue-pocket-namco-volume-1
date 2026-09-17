#!/bin/sh
# Run MAME ncv1 headless with disposable cfg/nvram dirs and a Lua script.
#   tools/mame_run.sh <script.lua> [extra mame args]
# ROMPATH defaults to the repo root (the ncv1/ directory or ncv1.zip inside it).
set -e
cd "$(dirname "$0")/.."
SCRIPT=$1; shift
ROMPATH=${ROMPATH:-$PWD}
SCRATCH=${SCRATCH:-/tmp/ncv1-mame}
mkdir -p "$SCRATCH/cfg" "$SCRATCH/nvram" "$SCRATCH/snap"
exec mame ncv1 -rompath "$ROMPATH" -video none -sound none -nothrottle -skip_gameinfo \
    -cfg_directory "$SCRATCH/cfg" -nvram_directory "$SCRATCH/nvram" -snapshot_directory "$SCRATCH/snap" \
    -autoboot_script "$SCRIPT" -seconds_to_run "${SECONDS_TO_RUN:-600}" "$@"
