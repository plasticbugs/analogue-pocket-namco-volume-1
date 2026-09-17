#!/usr/bin/env python3
"""Build the Pocket .rom image for the Namco Classic Collection core from a MAME romset.

A core is FPGA gateware: it cannot unzip a romset or run a script, so the ROM
image has to be assembled on a computer. This reads the .mra description and a
MAME `ncv1` or `ncv2` romset -- either the zip or a directory of loose files -- checks
every part's CRC32, assembles the image in the order the .mra gives, and
verifies the finished image against the md5 recorded in the .mra.

Supported MRA elements (the standard MiSTer subset):

  <part name="x" crc="y" [offset="0x1000" length="0x800"]/>
        a ROM, or a slice of one.
  <part repeat="N">FF</part>
        a run of literal bytes.
  <interleave output="16"> <part name=.. crc=.. map="01"/> ... </interleave>
        byte-interleave several ROMs into 16-bit words. Each digit of `map` is
        one byte of the output word, left to right; the digit is the 1-based
        byte of that part in the word ("01" = this ROM supplies byte 1, the
        second/odd byte; "10" = the first/even byte).

Nothing but Python 3 is required. The same .mra works with the standard MiSTer
mra tools.

Usage:
    mra_build.py <file.mra> <romset.zip|romset_dir> [out.rom]
"""
import sys, os, zipfile, hashlib, zlib
import xml.etree.ElementTree as ET


def load_parts(path):
    """Map lowercase member name -> bytes, from a zip or a directory."""
    out = {}
    if os.path.isdir(path):
        for entry in os.scandir(path):
            if entry.is_file():
                with open(entry.path, 'rb') as f:
                    out[entry.name.lower()] = f.read()
        if not out:
            sys.exit(f'error: {path} contains no files')
        return out
    if not os.path.exists(path):
        sys.exit(f'error: {path} not found')
    try:
        with zipfile.ZipFile(path) as zf:
            for info in zf.infolist():
                if not info.is_dir():
                    out[os.path.basename(info.filename).lower()] = zf.read(info)
    except zipfile.BadZipFile:
        sys.exit(f'error: {path} is neither a directory nor a readable zip')
    return out


def literal_bytes(node):
    text = (node.text or '').split()
    if not text:
        sys.exit('error: <part> with no name and no body')
    try:
        pattern = bytes(int(tok, 16) for tok in text)
    except ValueError:
        sys.exit(f'error: <part> body is not hex bytes: {node.text!r}')
    repeat = int(node.get('repeat', '1'), 0)
    return f'<fill {pattern.hex()} x{repeat}>', pattern * repeat


def get_part(parts, node):
    name = node.get('name')
    if name is None:
        return literal_bytes(node)
    data = parts.get(name.lower())
    crc = node.get('crc')
    if data is None and crc:
        # romsets in the wild name some chips differently (ncv2's second
        # character ROM is ncs1cg1.10f in MAME, ncs1cg1.10e in some dumps):
        # take the one member whose CRC is listed
        wanted = [int(c, 16) for c in crc.split('|')]
        hits = [k for k, v in parts.items() if zlib.crc32(v) & 0xffffffff in wanted]
        if len(hits) == 1:
            data = parts[hits[0]]
    if data is None:
        sys.exit(f'error: {name} is missing from the romset')
    if crc:
        # several acceptable dumps may be listed as "aaaaaaaa|bbbbbbbb"
        actual = zlib.crc32(data) & 0xffffffff
        if actual not in [int(c, 16) for c in crc.split('|')]:
            sys.exit(f'error: {name} has crc {actual:08x}, expected {crc}')
    offset = int(node.get('offset', '0'), 0)
    length = node.get('length')
    if length is not None:
        length = int(length, 0)
        if offset + length > len(data):
            sys.exit(f'error: {name} slice {offset:#x}+{length:#x} exceeds {len(data):#x}')
        return f'{name}[{offset:#x}:{offset + length:#x}]', data[offset:offset + length]
    if offset:
        return f'{name}[{offset:#x}:]', data[offset:]
    return name, data


def do_interleave(parts, node):
    width = int(node.get('output', '16'), 0)
    if width % 8:
        sys.exit(f'error: interleave output="{width}" is not a whole number of bytes')
    nbytes = width // 8
    sources = []
    for child in node:
        if child.tag != 'part':
            sys.exit(f'error: <{child.tag}> inside <interleave> is not supported')
        m = child.get('map')
        if m is None or len(m) != nbytes:
            sys.exit(f'error: {child.get("name")} inside <interleave> needs a {nbytes}-digit map')
        label, data = get_part(parts, child)
        sources.append((label, data, m))
    # each source supplies `k` bytes of every output word, where k = number of
    # non-zero digits in its map; its data is consumed k bytes at a time
    n_words = None
    for label, data, m in sources:
        k = sum(1 for d in m if d != '0')
        if k == 0:
            sys.exit(f'error: {label} map {m} supplies no bytes')
        if len(data) % k:
            sys.exit(f'error: {label} length {len(data)} is not a multiple of {k}')
        words = len(data) // k
        if n_words is None:
            n_words = words
        elif words != n_words:
            sys.exit(f'error: interleave parts have different word counts ({label})')
    out = bytearray(n_words * nbytes)
    for label, data, m in sources:
        k = sum(1 for d in m if d != '0')
        for pos, d in enumerate(m):
            if d == '0':
                continue
            src_index = int(d) - 1     # which of this part's k bytes per word
            out[pos::nbytes] = data[src_index::k]
    labels = ' + '.join(f'{l}(map {m})' for l, _, m in sources)
    return f'interleave{width}[{labels}]', bytes(out)


def build(mra_path, romset_path, verbose=False):
    tree = ET.parse(mra_path)
    rom = tree.getroot().find('rom')
    if rom is None:
        sys.exit('error: no <rom> element in the .mra')
    parts = load_parts(romset_path)
    image = bytearray()
    for node in rom:
        if node.tag == 'part':
            label, data = get_part(parts, node)
        elif node.tag == 'interleave':
            label, data = do_interleave(parts, node)
        else:
            continue
        if verbose:
            print(f'  {len(image):#08x}  {len(data):7d}  {label}')
        image += data
    expected = rom.get('md5')
    actual = hashlib.md5(image).hexdigest()
    if expected and expected.lower() != 'none' and expected.lower() != actual:
        sys.exit(f'error: built image md5 {actual} does not match the .mra ({expected})')
    return bytes(image), actual


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    mra_path, romset_path = sys.argv[1], sys.argv[2]
    tree = ET.parse(mra_path)
    setname = tree.getroot().findtext('setname') or 'out'
    out_path = sys.argv[3] if len(sys.argv) > 3 else f'{setname}.rom'
    image, md5 = build(mra_path, romset_path, verbose=True)
    with open(out_path, 'wb') as f:
        f.write(image)
    print(f'wrote {out_path}: {len(image)} bytes, md5 {md5}')


if __name__ == '__main__':
    main()
