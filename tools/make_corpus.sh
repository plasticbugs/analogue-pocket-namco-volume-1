#!/bin/sh
# Build the frozen-state corpus: one MAME session per game mode, dumping the
# YGV608 state and a PNG snapshot at the listed frames into artifacts/states/.
#   tools/make_corpus.sh [ncv1|ncv2|all]      (default all)
#
# Vol.1 menu: coin -> start -> GAME SELECT (up/down, button) -> MODE SELECT
# (up = original, down = arrangement, button) -> game title (start) -> play.
# Vol.2 menu: coin -> start -> GAME SELECT (left/right, button) -> MODE SELECT
# (left = original, right = arrangement, button) -> game title (start) ->
# instructions (arrangement) -> play. Vol.2 states are prefixed ncv2_. The mode
# press repeats: after a game-select move the mode screen arrives later.
set -e
cd "$(dirname "$0")/.."
OUT=artifacts/states
mkdir -p "$OUT"
WHICH=${1:-all}
run() {  # game, tag, frames, inputs
    G=$1; TAG=$2; FRAMES=$3; INPUTS=$4
    SCR=${SCRATCH_BASE:-/tmp/ncv1-mame}/$TAG
    rm -rf "$SCR"
    STOP=${FRAMES##*,}
    echo "== $TAG"
    GAME=$G SCRATCH=$SCR NCV1_OUT=$OUT NCV1_TAG=$TAG NCV1_FRAMES=$FRAMES NCV1_STOP=$STOP NCV1_INPUTS="$INPUTS" \
        tools/mame_run.sh tools/dump_state.lua 2>&1 | grep -E "dumped|Average|rror" || true
    i=0
    for f in $(echo $FRAMES | tr , ' '); do
        src=$(printf "%s/snap/%s/%04d.png" "$SCR" "$G" $i)
        [ -f "$src" ] && cp "$src" "$OUT/${TAG}_$(printf %05d $f).png"
        i=$((i+1))
    done
}

if [ "$WHICH" = ncv1 ] || [ "$WHICH" = all ]; then
    F1="600,1000,1400,2000,2600,3200,3800,4400,5000,5600"
    I1="400:Coin 1:8,500:1 Player Start:8"
    P1="2300:P1 Button 1:6,2500:P1 Left:60,2700:P1 Button 1:6,2900:P1 Right:60,3100:P1 Button 1:6,3300:P1 Up:40,3500:P1 Button 1:6,3700:P1 Down:40,3900:P1 Button 1:6,4100:P1 Left:80,4300:P1 Button 1:6,4700:P1 Button 1:6,4900:P1 Right:80,5100:P1 Button 1:6,5300:P1 Up:60,5500:P1 Button 1:6"
    v1() {  # tag, navigation presses, mode press
        run ncv1 "$1" "$F1" "$I1,$2,900:P1 Button 1:8,$3,1300:P1 Button 1:8,1700:1 Player Start:8,1900:1 Player Start:8,$P1"
    }
    UP2="700:P1 Up:8,720:P1 Up:8"
    v1 galaga_orig  "$UP2"                             "1100:P1 Up:8"
    v1 galaga_arr   "$UP2"                             "1100:P1 Down:8"
    v1 xevious_orig "$UP2,760:P1 Down:8"               "1100:P1 Up:8"
    v1 xevious_arr  "$UP2,760:P1 Down:8"               "1100:P1 Down:8"
    v1 mappy_orig   "$UP2,760:P1 Down:8,780:P1 Down:8" "1100:P1 Up:8"
    v1 mappy_arr    "$UP2,760:P1 Down:8,780:P1 Down:8" "1100:P1 Down:8"
fi

if [ "$WHICH" = ncv2 ] || [ "$WHICH" = all ]; then
    # boot: self test, attract (Dig Dug, Rally-X demos), title
    run ncv2 ncv2_boot "300,600,800,1000,1200,1500" ""
    F2="1800,2200,2600,3000,3400,3800,4200,4600,5000,5400,5800,6200"
    I2="1400:Coin 1:8,1500:1 Player Start:8"
    P2="3000:P1 Left:90,3100:P1 Button 1:20,3300:P1 Up:90,3450:P1 Button 1:20,3600:P1 Right:90,3750:P1 Button 1:20,3900:P1 Down:90,4100:P1 Left:120,4250:P1 Button 1:20,4400:P1 Up:120,4600:P1 Right:120,4700:P1 Button 1:20,4800:P1 Down:120,5000:P1 Left:150,5200:P1 Button 1:20,5300:P1 Up:150,5500:P1 Right:150,5700:P1 Down:150,5900:P1 Left:150,6000:P1 Button 1:20"
    v2() {  # tag, game-select presses (or none), mode press
        NAV=$2; [ -n "$NAV" ] && NAV="$NAV,"
        run ncv2 "$1" "$F2" "$I2,${NAV}1900:P1 Button 1:8,$3,2300:P1 Button 1:8,2600:1 Player Start:8,2750:1 Player Start:8,2900:1 Player Start:8,$P2"
    }
    R1="1700:P1 Right:8"
    R2="1700:P1 Right:8,1740:P1 Right:8"
    v2 ncv2_pacman_orig  ""    "2150:P1 Left:8,2200:P1 Left:8"
    v2 ncv2_pacman_arr   ""    "2150:P1 Right:8,2200:P1 Right:8"
    v2 ncv2_rallyx_orig  "$R1" "2150:P1 Left:8,2200:P1 Left:8"
    v2 ncv2_rallyx_arr   "$R1" "2150:P1 Right:8,2200:P1 Right:8"
    v2 ncv2_digdug_orig  "$R2" "2150:P1 Left:8,2200:P1 Left:8"
    v2 ncv2_digdug_arr   "$R2" "2150:P1 Right:8,2200:P1 Right:8"
fi
