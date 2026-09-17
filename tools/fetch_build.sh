#!/bin/sh
# Fetch a compiled core from a CI run and update the SD-card package.
#
# Usage: fetch_build.sh <run-id> [dest]
#
# Downloads to a staging directory and verifies the bitstream before touching
# the destination, so a failed or partial download can never destroy a working
# package (which is exactly what happened once).
set -e
RUN="$1"
DEST="${2:-$HOME/Desktop/mcr68-pocket-sd}"
[ -n "$RUN" ] || { echo "usage: fetch_build.sh <run-id> [dest]"; exit 1; }
cd "$(dirname "$0")/.."

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

echo "downloading run $RUN ..."
gh run download "$RUN" -D "$STAGE" || { echo "download FAILED - $DEST left untouched"; exit 1; }

# The artifact holds the Cores/Platforms/Assets tree; find the bitstream.
RBF=$(find "$STAGE" -name 'bitstream.rbf_r' | head -1)
[ -n "$RBF" ] || { echo "no bitstream in artifact - $DEST left untouched"; exit 1; }
SIZE=$(wc -c < "$RBF")
[ "$SIZE" -gt 500000 ] || { echo "bitstream only $SIZE bytes, looks truncated - $DEST left untouched"; exit 1; }

ROOT=$(dirname "$(dirname "$(dirname "$RBF")")")   # .../Cores/<core>/bitstream.rbf_r
[ -d "$ROOT/Cores" ] || ROOT=$(dirname "$RBF")

echo "bitstream ok ($SIZE bytes, md5 $(md5 -q "$RBF"))"

# Preserve any ROM the user already placed in Assets.
if [ -d "$DEST/Assets" ]; then
    find "$DEST/Assets" -name '*.rom' -exec cp {} "$STAGE/" \; 2>/dev/null || true
fi

rm -rf "$DEST.old"
[ -d "$DEST" ] && mv "$DEST" "$DEST.old"
cp -R "$ROOT" "$DEST"

# Put each ROM back if the fresh package doesn't carry one. The .rom basename
# is the platform id, so it names its own Assets folder - which keeps this
# right now that there is more than one core.
for r in "$STAGE"/*.rom; do
    [ -f "$r" ] || continue
    name=$(basename "$r")
    tgt="$DEST/Assets/${name%.rom}/common/$name"
    mkdir -p "$(dirname "$tgt")"
    [ -f "$tgt" ] || cp "$r" "$tgt"
done

rm -rf "$DEST.old"
echo "package updated: $DEST"
find "$DEST" -name 'bitstream.rbf_r' | while read -r b; do
    echo "  $(basename "$(dirname "$b")")  md5 $(md5 -q "$b")"
done
