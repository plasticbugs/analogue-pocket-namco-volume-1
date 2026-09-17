#!/bin/sh
# Publish a release built from a specific, hardware-verified CI build.
#
# Usage: cut-release.sh <tag> <run-id>
#        cut-release.sh v1.0.0 32214080417
#
# Takes the bitstream from that run rather than recompiling, so the release
# ships the exact gateware that was tested on hardware. Everything outside the
# bitstream (JSON definitions, platform image, ROM recipe, README) comes from
# the working tree, which is how a definition-only change can be released
# without a rebuild.
#
# Creating the tag triggers the Compile Core workflow; it sees the release
# already exists and skips publishing, leaving this artifact in place.
set -e
TAG="$1"
RUN="$2"
[ -n "$TAG" ] && [ -n "$RUN" ] || { echo "usage: cut-release.sh <tag> <run-id>"; exit 1; }
cd "$(dirname "$0")/.."

command -v gh >/dev/null || { echo "gh CLI required"; exit 1; }
if gh release view "$TAG" >/dev/null 2>&1; then
    echo "release $TAG already exists; delete it first or pick another tag"; exit 1
fi
if [ -n "$(git status --porcelain pkg target rtl platform projects)" ]; then
    echo "working tree has uncommitted core changes; commit them so the tag matches"; exit 1
fi

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

echo "fetching bitstream from run $RUN ..."
gh run download "$RUN" -D "$STAGE" || { echo "download failed"; exit 1; }
# The run ships one bitstream per core, each under its own Cores/<id>/ folder.
CORES=$(find "$STAGE" -name 'bitstream.rbf_r' -exec dirname {} \; | xargs -n1 basename | sort -u)
[ -n "$CORES" ] || { echo "no bitstream in run $RUN"; exit 1; }
for c in $CORES; do
    RBF=$(find "$STAGE" -path "*/$c/bitstream.rbf_r" | head -1)
    SIZE=$(wc -c < "$RBF")
    [ "$SIZE" -gt 500000 ] || { echo "$c bitstream only $SIZE bytes, looks truncated"; exit 1; }
done

# Assemble the package: definitions from the tree, bitstream from the run.
OUT="$STAGE/release/pocket"
rm -rf "$OUT"; mkdir -p "$OUT"
# A ROM may sit in pkg/pocket/Assets locally (gitignored); never ship it.
tar -cf - --exclude '.DS_Store' --exclude '*.rom' --exclude '*.zip' \
    -C pkg/pocket . | tar -xf - -C "$OUT"
for c in $CORES; do
    RBF=$(find "$STAGE" -path "*/$c/bitstream.rbf_r" | head -1)
    [ -d "$OUT/Cores/$c" ] || { echo "run has a bitstream for $c but the tree has no such core"; exit 1; }
    cp "$RBF" "$OUT/Cores/$c/bitstream.rbf_r"
done
# A core folder with no bitstream would be one the Pocket cannot load.
for d in "$OUT"/Cores/*/; do
    [ -f "$d/bitstream.rbf_r" ] || { echo "no bitstream for $(basename "$d") in run $RUN"; exit 1; }
done
for extra in ncv1.mra ncv2.mra README.md tools/mra_build.py; do
    [ -f "$extra" ] && cp "$extra" "$OUT/$(basename "$extra")"
done

# Sanity-check the package before it goes out.
for c in $CORES; do
    for f in core.json input.json interact.json data.json; do
        [ -e "$OUT/Cores/$c/$f" ] || { echo "package missing Cores/$c/$f"; exit 1; }
    done
    plat=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['core']['metadata']['platform_ids'][0])" \
           "$OUT/Cores/$c/core.json")
    for f in "Platforms/$plat.json" "Platforms/_images/$plat.bin" "Assets/$plat/common/README.txt" \
             "Assets/$plat/$c/Namco Classic Collection Vol.1.json" "Assets/$plat/$c/Namco Classic Collection Vol.2.json"; do
        [ -e "$OUT/$f" ] || { echo "package missing $f"; exit 1; }
    done
done
for j in "$OUT"/Cores/*/*.json "$OUT"/Platforms/*.json "$OUT"/Assets/*/*/*.json; do
    python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$j" || { echo "bad json: $j"; exit 1; }
done
if find "$OUT" -name '*.rom' | grep -q .; then
    echo "refusing to publish: a ROM is in the package"; exit 1
fi

VER=$(python3 -c "import json;print(json.load(open('pkg/pocket/Cores/plasticbugs.namcocollection/core.json'))['core']['metadata']['version'])")
ZIP="$PWD/namcocollection-pocket-sdcard.zip"
rm -f "$ZIP"
(cd "$OUT" && zip -qr "$ZIP" .)
echo "package $VER, zip $(wc -c < "$ZIP") bytes"
for c in $CORES; do
    echo "  $c  md5 $(md5 -q "$OUT/Cores/$c/bitstream.rbf_r")"
done

gh release create "$TAG" \
    --title "Namco Classic Collection for Analogue Pocket $TAG" \
    --notes "Unzip onto the Pocket SD card root, overwriting previous files. Build ncv1.rom and ncv2.rom with the included mra_build.py and put them in Assets/namcocollection/common/." \
    "$ZIP"
rm -f "$ZIP"
echo "published $TAG"
