#!/bin/sh
# Build the frozen-state corpus: one MAME session per game mode, dumping the
# YGV608 state and a PNG snapshot at the listed frames into artifacts/states/.
# Menu flow: coin -> start -> GAME SELECT (up/down, button) -> MODE SELECT
# (up = original, down = arrangement, button) -> game title (start) -> play.
set -e
cd "$(dirname "$0")/.."
OUT=artifacts/states
mkdir -p "$OUT"
run() {  # tag, navigation presses, mode press
    TAG=$1; NAV=$2; MODE=$3
    SCR=${SCRATCH_BASE:-/tmp/ncv1-mame}/$TAG
    rm -rf "$SCR"
    FRAMES="600,1000,1400,2000,2600,3200,3800,4400,5000,5600"
    INPUTS="400:Coin 1:8,500:1 Player Start:8,$NAV,900:P1 Button 1:8,$MODE,1300:P1 Button 1:8,1700:1 Player Start:8,1900:1 Player Start:8"
    INPUTS="$INPUTS,2300:P1 Button 1:6,2500:P1 Left:60,2700:P1 Button 1:6,2900:P1 Right:60,3100:P1 Button 1:6,3300:P1 Up:40,3500:P1 Button 1:6,3700:P1 Down:40,3900:P1 Button 1:6,4100:P1 Left:80,4300:P1 Button 1:6,4700:P1 Button 1:6,4900:P1 Right:80,5100:P1 Button 1:6,5300:P1 Up:60,5500:P1 Button 1:6"
    echo "== $TAG"
    SCRATCH=$SCR NCV1_OUT=$OUT NCV1_TAG=$TAG NCV1_FRAMES=$FRAMES NCV1_STOP=5600 NCV1_INPUTS="$INPUTS" \
        tools/mame_run.sh tools/dump_state.lua 2>&1 | grep -E "dumped|Average|rror" || true
    i=0
    for f in $(echo $FRAMES | tr , ' '); do
        src=$(printf "%s/snap/ncv1/%04d.png" "$SCR" $i)
        [ -f "$src" ] && cp "$src" "$OUT/${TAG}_$(printf %05d $f).png"
        i=$((i+1))
    done
}
UP2="700:P1 Up:8,720:P1 Up:8"
run galaga_orig  "$UP2"                          "1100:P1 Up:8"
run galaga_arr   "$UP2"                          "1100:P1 Down:8"
run xevious_orig "$UP2,760:P1 Down:8"            "1100:P1 Up:8"
run xevious_arr  "$UP2,760:P1 Down:8"            "1100:P1 Down:8"
run mappy_orig   "$UP2,760:P1 Down:8,780:P1 Down:8" "1100:P1 Up:8"
run mappy_arr    "$UP2,760:P1 Down:8,780:P1 Down:8" "1100:P1 Down:8"
