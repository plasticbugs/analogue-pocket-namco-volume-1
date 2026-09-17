#!/usr/bin/env python3
"""YGV608 reference renderer for the Namco ND-1 (ncv1) core.

Renders one 288x224 frame from a state file written by tools/dump_state.lua
exactly as MAME's ygv608_device::screen_update does (ref/mame/ygv608.cpp), so
it can be diffed against MAME's own snapshot and later used as the executable
spec for the RTL. Pure Python 3, no dependencies (tools/pngio.py for PNG).

    render_model.py <state.txt> [--rom artifacts/ncv1.rom] [--out frame.png]
                    [--layer a|b|s|all] [--compare mame.png] [--diff diff.png]
                    [--dump-fetches fetches.txt] [--quiet]

Rotation: MAME runs ncv1 with ROT90, so its snapshot is 224 wide x 288 tall.
The VDP raster is 288 wide x 224 tall; MAME's ROT90 is a clockwise rotation
of that raster, hence  png(x, y) = native(nx = y, ny = 223 - x).  (Verified
empirically: the boot title screen reads correctly only with this mapping.)

The semantics are documented in docs/ygv608.md.
"""
import sys, os, argparse
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pngio

W, H = 288, 224                    # visible raster (CRTC HDW=36*16/2, VDW=28*8)
ROM_OFFSET, ROM_SIZE = 0x180000, 0x200000   # pattern ROM inside ncv1.rom
REGION_SIZE = 0x800000             # MAME's ygv608 region: the 2 MB mirrored 4x

# MAME gfx sets (gfx_ygv608): index -> (tile size, bpp, bytes per tile)
GFX = {0: (8, 4, 32), 1: (16, 4, 128), 2: (32, 4, 512), 3: (64, 4, 2048),
       4: (8, 8, 64), 5: (16, 8, 256)}
GFX_8X8_4BIT, GFX_16X16_4BIT, GFX_8X8_8BIT, GFX_16X16_8BIT = 0, 1, 4, 5

MD_2PLANE_8BIT, MD_2PLANE_16BIT, MD_1PLANE_16COLOUR, MD_1PLANE_256COLOUR = 0, 1, 2, 3
MD_1PLANE = 2                      # (MD_1PLANE_16COLOUR & MD_1PLANE_256COLOUR)


def elements(gfxset):
    return REGION_SIZE // GFX[gfxset][2]


# ----------------------------------------------------------------- state file
class State:
    def __init__(self, path):
        self.path = path
        self.s = {}
        self.a = {}
        with open(path) as f:
            lines = f.read().split('\n')
        i = 0
        while i < len(lines):
            ln = lines[i].strip(); i += 1
            if not ln:
                continue
            name, rest = ln.split(' ', 1)
            if name.endswith('[]'):
                count, size = (int(x) for x in rest.split())
                vals = []
                while len(vals) < count:
                    vals += [int(v, 16) for v in lines[i].split()]; i += 1
                self.a[name[:-2]] = vals
            elif name == 'frame':
                self.frame = int(rest)
            else:
                self.s[name] = int(rest, 16)

    def __getattr__(self, n):
        key = 'm_' + n
        if key in self.s:
            return self.s[key]
        if key in self.a:
            return self.a[key]
        raise AttributeError(n)


def pal6bit(v):
    v &= 0x3f
    return (v << 2) | (v >> 4)


# ---------------------------------------------------------------- pattern ROM
class PatternRom:
    """The 8 MB region MAME sees (2 MB ROM mirrored), with the gfx decode of
    pts_4bits_layout / pts_8x8_8bits_layout / pts_16x16_8bits_layout."""

    def __init__(self, rom_path, fetch_log=None):
        with open(rom_path, 'rb') as f:
            f.seek(ROM_OFFSET)
            self.rom = f.read(ROM_SIZE)
        if len(self.rom) != ROM_SIZE:
            sys.exit(f'{rom_path}: pattern ROM short ({len(self.rom)} bytes)')
        self.fetch_log = fetch_log     # set of byte addresses, or None
        self.cache = {}

    @staticmethod
    def morton(bx, by):
        """8x8 block index inside a larger 4bpp tile: x bits in even positions."""
        m = 0
        for b in range(3):
            m |= ((bx >> b) & 1) << (2 * b)
            m |= ((by >> b) & 1) << (2 * b + 1)
        return m

    def byte(self, addr):
        addr &= REGION_SIZE - 1
        if self.fetch_log is not None:
            self.fetch_log.add(addr)
        return self.rom[addr & (ROM_SIZE - 1)]

    def pixel(self, gfxset, code, x, y):
        """Raw pen (0..15 or 0..255) of pixel (x, y) of tile `code` in set."""
        size, bpp, nbytes = GFX[gfxset]
        base = code * nbytes
        if bpp == 4:
            blk = self.morton(x >> 3, y >> 3)
            a = base + blk * 32 + (y & 7) * 4 + ((x & 7) >> 1)
            b = self.byte(a)
            return (b >> 4) if (x & 1) == 0 else (b & 0xf)
        else:
            blk = ((y >> 3) << 1) | (x >> 3)        # 16x16 8bpp: TL TR BL BR
            a = base + blk * 64 + (y & 7) * 8 + (x & 7)
            return self.byte(a)

    def tile(self, gfxset, code):
        """Decoded tile as a list of rows of raw pens (cached)."""
        key = (gfxset, code)
        t = self.cache.get(key)
        if t is None:
            size = GFX[gfxset][0]
            t = [[self.pixel(gfxset, code, x, y) for x in range(size)] for y in range(size)]
            self.cache[key] = t
        return t


# ------------------------------------------------------------------ renderer
class Renderer:
    def __init__(self, st, rom):
        self.st = st
        self.rom = rom
        s = st
        self.md = s.md
        self.bits16 = s.bits16
        self.page_x, self.page_y = s.page_x, s.page_y
        self.pny_shift = s.pny_shift
        self.na8_mask = s.na8_mask
        self.base_y_shift = s.base_y_shift
        self.tsize = 8 if s.pattern_size == 0 else 16      # PTS 8x8 / 16x16 (only sizes MAME's tilemaps use)
        self.pnt = s.pattern_name_table
        self.sdt = [s.scroll_data_table[0:256], s.scroll_data_table[256:512]]
        self.base_addr = [s.base_addr[0:8], s.base_addr[8:16]]
        self.tw = self.page_x * self.tsize        # tilemap width in pixels
        self.th = self.page_y * self.tsize
        self.palette = [(pal6bit(s.colour_palette[i * 3]), pal6bit(s.colour_palette[i * 3 + 1]),
                         pal6bit(s.colour_palette[i * 3 + 2])) for i in range(256)]
        self.tile_cache = [{}, {}]

    # -- MAME helpers ------------------------------------------------------
    def get_col_division(self, raw_col):
        if (self.st.v_div_size & 4) == 0:
            return 0
        return ((raw_col >> self.st.col_shift) * 2) & 0x7f

    def get_row_division(self, raw_row):
        if self.st.h_div_size == 0:
            return 0
        return (raw_row & (self.page_y // 2 - 1)) * 2

    def tile_info(self, plane, col, row):
        """-> (gfxset, code, colour, flipx, flipy) exactly as get_tile_info_{A,B}_{8,16}."""
        key = (col, row)
        c = self.tile_cache[plane].get(key)
        if c is not None:
            return c
        s = self.st
        md = self.md
        is16 = self.tsize == 16
        if plane == 0:
            gfxset = (GFX_16X16_8BIT if is16 else GFX_8X8_8BIT) if md == MD_1PLANE_256COLOUR \
                else (GFX_16X16_4BIT if is16 else GFX_8X8_4BIT)
            pn_base = 0
            cf = s.planeA_color_fetch
        else:
            gfxset = GFX_16X16_4BIT if is16 else GFX_8X8_4BIT
            pn_base = (self.page_y << self.pny_shift) << self.bits16
            cf = s.planeB_color_fetch
        blank = (gfxset, 0, 0, False, False)
        if plane == 1 and (md & MD_1PLANE):
            # B_8: returns blank; B_16: falls through (no else) but B is disabled in 1-plane modes
            self.tile_cache[plane][key] = blank
            return blank
        if col >= self.page_x or row >= self.page_y:
            self.tile_cache[plane][key] = blank
            return blank
        translated_column = self.get_col_division(col)
        base = row >> self.base_y_shift
        i = pn_base + (((row << self.pny_shift) + col) << self.bits16)
        j = self.pnt[i]
        attr = 0
        flipx = flipy = False
        if self.bits16:
            j += (self.pnt[i + 1] & self.na8_mask) << 8
            if plane == 1 or gfxset in (GFX_8X8_4BIT, GFX_16X16_4BIT):
                attr = self.pnt[i + 1] >> 4
            if s.flip:
                flipx = bool(self.pnt[i + 1] & 8)
                flipy = bool(self.pnt[i + 1] & 4)
        sdt = self.sdt[plane]
        if s.v_div_size:
            page = 0
        else:
            sy = sdt[translated_column] + ((sdt[translated_column + 1] & 0x0f) << 8)
            sx = sdt[0x80] + ((sdt[0x81] & 0x0f) << 8)
            if not is16:
                if md == MD_2PLANE_16BIT:
                    page = ((sx + col * 8) % 1024) // 256
                    page += (((sy + row * 8) % 2048) // 256) * 4
                elif s.page_size:
                    page = ((sx + col * 8) % 2048) // 512
                    page += (((sy + row * 8) % 2048) // 256) * 4
                else:
                    page = ((sx + col * 8) % 2048) // 256
                    page += (((sy + row * 8) % 2048) // 512) * 8
            else:
                if md == MD_2PLANE_16BIT:
                    page = ((sx + col * 16) % 2048) // 512
                    page += ((sy + row * 16) // 512) * 4
                elif s.page_size:
                    page = (sx + col * 16) // 512
                    page += ((sy + row * 16) // 1024) * 8
                else:
                    page = (sx + col * 16) // 1024
                    page += ((sy + row * 16) // 512) * 4
        page &= 0x1f
        j += sdt[0xc0 + page] << (10 if not is16 else 8)
        j += self.base_addr[plane][base] << 8
        if j >= elements(gfxset):
            j = 0
        if cf != 0:
            if plane == 1 or gfxset in (GFX_8X8_4BIT, GFX_16X16_4BIT):
                # note the asymmetry in MAME: 8x8 uses (cf-1)*2, 16x16 uses cf*2
                attr = (j >> ((cf - 1) * 2 if not is16 else cf * 2)) & 0x0f
        bank = s.namcond1_gfxbank
        if gfxset == GFX_8X8_4BIT:
            j += bank * 0x10000
        elif gfxset == GFX_8X8_8BIT:
            j += bank * 0x8000
        elif gfxset == GFX_16X16_4BIT:
            j += bank * 0x4000
        else:
            j += bank * 0x2000
        colour = (attr & 0x0f) if plane == 0 else attr
        r = (gfxset, j, colour, flipx, flipy)
        self.tile_cache[plane][key] = r
        return r

    def tilemap_pixel(self, plane, tx, ty):
        """Raw pen and palette base of tilemap pixel (tx, ty) (already wrapped)."""
        ts = self.tsize
        gfxset, code, colour, flipx, flipy = self.tile_info(plane, tx // ts, ty // ts)
        px, py = tx % ts, ty % ts
        if flipx:
            px = ts - 1 - px
        if flipy:
            py = ts - 1 - py
        pen = self.rom.tile(gfxset, code)[py][px]
        granularity = 16 if GFX[gfxset][1] == 4 else 256
        return pen, colour * granularity

    def draw_tilemap(self, plane):
        """MAME tilemap_t::draw of plane into a 288x224 array of palette
        indices, honouring the row/column scroll configuration of
        screen_update. Returns (indices, drawn-mask) where undrawn pixels
        (transparent pen, plane A only) are 0 / False."""
        s = self.st
        sdt = self.sdt[plane]
        row_scroll_mode = s.h_div_size != 0        # scroll_cols = 1, scroll_rows = page_y
        # per-column y scroll (set_scrolly): only column 0 exists in row-scroll mode
        ncols = 1 if row_scroll_mode else self.page_x
        colscroll = []
        for col in range(ncols):
            tc = self.get_col_division(col)
            colscroll.append((sdt[tc] + (sdt[tc + 1] << 8)) % self.th)
        nrows = self.page_y if row_scroll_mode else 1
        rowscroll = []
        for row in range(nrows):
            tr = self.get_row_division(row)
            rowscroll.append((sdt[tr + 0x80] + (sdt[tr + 0x81] << 8)) % self.tw)
        tw, th, ts = self.tw, self.th, self.tsize
        transparent_pen = s.border_color if plane == 0 else None
        out = [0] * (W * H)
        drawn = [False] * (W * H)
        for sy in range(H):
            for sx in range(W):
                if row_scroll_mode:
                    ty = (sy + colscroll[0]) % th
                    row = ty // ts
                    tx = (sx + rowscroll[row]) % tw
                else:
                    tx = (sx + rowscroll[0]) % tw
                    col = tx // ts
                    ty = (sy + colscroll[col]) % th
                pen, pbase = self.tilemap_pixel(plane, tx, ty)
                if transparent_pen is not None and pen == transparent_pen:
                    continue
                out[sy * W + sx] = pbase + pen
                drawn[sy * W + sx] = True
        return out, drawn

    def draw_sprites(self, bitmap):
        s = self.st
        if not s.dspe or s.sprite_disable:
            return
        sprite_limits = [512 - 8, 512 - 16, 512 - 32, 512 - 64]
        spritebank_size = [0x10000, 0x4000, 0x1000, 0x400]
        sprite_shift = [8, 6, 4, 2]
        sprite_mask = [0xff, 0xfc, 0xf0, 0xc0]
        spf_shift = [-1, 0, 1, 2]
        sat = s.a['m_sprite_attribute_table.b']
        for i in range(63, -1, -1):          # entry 63 first, entry 0 on top
            sy0, sx0, attr, sn = sat[i * 4], sat[i * 4 + 1], sat[i * 4 + 2], sat[i * 4 + 3]
            colour = (attr >> 4) & 0x0f
            sx = ((attr & 0x02) << 7) | sx0
            sy = ((((attr & 0x01) << 8) | sy0) + 1) & 0x1ff
            a = (attr & 0x0c) >> 2
            g_attr = s.sprite_aux_reg & 3
            spf = s.sprite_color_fetch
            if not s.sprite_aux_mode:            # SPAS=0: SPA gives the size, attr bits flip
                size = g_attr
                flipx = (a & 2) != 0
                flipy = (a & 1) != 0
            else:                                # SPAS=1: attr bits give the size, SPA flips
                size = a
                flipx = (g_attr & 2) != 0
                flipy = (g_attr & 1) != 0
            code = ((s.sprite_bank & sprite_mask[size]) << sprite_shift[size]) | sn
            if spf != 0:
                colour = (code >> ((spf + spf_shift[size]) * 2)) & 0x0f
            if code >= elements(size):
                code = 0
            code += s.namcond1_gfxbank * spritebank_size[size]
            positions = [(sx, sy)]
            if sx > sprite_limits[size] or sy > sprite_limits[size]:
                positions += [(sx - 512, sy), (sx, sy - 512), (sx - 512, sy - 512)]
            tile = self.rom.tile(size, code)
            n = GFX[size][0]
            for (px0, py0) in positions:
                for yy in range(n):
                    dy = py0 + yy
                    if dy < 0 or dy >= H:
                        continue
                    srow = tile[n - 1 - yy] if flipy else tile[yy]
                    for xx in range(n):
                        dx = px0 + xx
                        if dx < 0 or dx >= W:
                            continue
                        pen = srow[n - 1 - xx] if flipx else srow[xx]
                        if pen != 0:
                            bitmap[dy * W + dx] = colour * 16 + pen

    def render(self, layer='all'):
        """-> list of W*H palette indices (the screen bitmap) and the RGB bytes."""
        s = self.st
        bitmap = [s.border_color] * (W * H)
        if self.page_x == 0 or self.page_y == 0:
            return bitmap
        want_a = layer in ('all', 'a')
        want_b = layer in ('all', 'b')
        want_s = layer in ('all', 's')
        two_planes = not (self.md & MD_1PLANE)
        if two_planes and want_b and s.dspe:
            work, _ = self.draw_tilemap(1)          # B is opaque into the work bitmap
            if s.planeB_trans_enable:
                for k in range(W * H):
                    if work[k] != 0:
                        bitmap[k] = work[k]
            else:
                bitmap = work[:]
        elif not two_planes:
            pass                                    # work bitmap cleared; nothing copied
        if s.priority_mode in (1, 3) and want_s:    # PRM_ASBDEX / PRM_ASEBDX: sprites under A
            self.draw_sprites(bitmap)
        if want_a:
            if s.dspe:
                work, _ = self.draw_tilemap(0)      # undrawn (== border pen) stay 0
            else:
                work = [0] * (W * H)
            if s.planeA_trans_enable:
                for k in range(W * H):
                    if work[k] != 0:
                        bitmap[k] = work[k]
            else:
                bitmap = work
        if s.priority_mode in (0, 2) and want_s:    # PRM_SABDEX / PRM_SEABDX: sprites on top
            self.draw_sprites(bitmap)
        return bitmap

    def to_rgb(self, bitmap):
        out = bytearray(W * H * 3)
        pal = self.palette
        for k, p in enumerate(bitmap):
            r, g, b = pal[p & 0xff]
            out[k * 3] = r; out[k * 3 + 1] = g; out[k * 3 + 2] = b
        return out


def rotate_to_mame(rgb):
    """288x224 native -> 224x288 as MAME's ROT90 snapshot lays it out."""
    out = bytearray(H * W * 3)
    for ny in range(H):
        for nx in range(W):
            x, y = H - 1 - ny, nx
            out[(y * H + x) * 3:(y * H + x) * 3 + 3] = rgb[(ny * W + nx) * 3:(ny * W + nx) * 3 + 3]
    return out


def rotate_from_mame(rgb):
    """224x288 MAME snapshot -> 288x224 native."""
    out = bytearray(W * H * 3)
    for y in range(W):
        for x in range(H):
            nx, ny = y, H - 1 - x
            out[(ny * W + nx) * 3:(ny * W + nx) * 3 + 3] = rgb[(y * H + x) * 3:(y * H + x) * 3 + 3]
    return out


def compare(rgb, ref_path, diff_path=None, quiet=False):
    rw, rh, ref = pngio.read(ref_path)
    if (rw, rh) == (H, W):
        ref = rotate_from_mame(ref)
    elif (rw, rh) != (W, H):
        sys.exit(f'{ref_path}: unexpected size {rw}x{rh}')
    ndiff = 0
    cells = {}
    first = []
    diff = bytearray(W * H * 3)
    for k in range(W * H):
        a = rgb[k * 3:k * 3 + 3]; b = ref[k * 3:k * 3 + 3]
        if a != b:
            ndiff += 1
            y, x = divmod(k, W)
            cells[(y // 16, x // 16)] = cells.get((y // 16, x // 16), 0) + 1
            if len(first) < 20:
                first.append((x, y, tuple(b), tuple(a)))
            diff[k * 3:k * 3 + 3] = b'\xff\x00\x00'
        else:
            diff[k * 3] = a[0] // 3; diff[k * 3 + 1] = a[1] // 3; diff[k * 3 + 2] = a[2] // 3
    if not quiet:
        print(f'diff {ndiff}/{W * H} pixels')
        for (x, y, e, g) in first:
            print(f'  ({x:3d},{y:3d}) expected {e} got {g}')
        for k, n in sorted(cells.items(), key=lambda kv: -kv[1])[:14]:
            print(f'  cell row{k[0]:2d} col{k[1]:2d}: {n} px')
    if diff_path:
        pngio.write(diff_path, W, H, diff)
    return ndiff


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('state')
    ap.add_argument('--rom', default=os.path.join(os.path.dirname(__file__), '..', 'artifacts', 'ncv1.rom'))
    ap.add_argument('--out')
    ap.add_argument('--layer', default='all', choices=['a', 'b', 's', 'all'])
    ap.add_argument('--compare')
    ap.add_argument('--diff')
    ap.add_argument('--dump-fetches')
    ap.add_argument('--raw', help='write the palette-index bitmap (W*H bytes) here')
    ap.add_argument('--quiet', action='store_true')
    args = ap.parse_args()

    st = State(args.state)
    fetches = set() if args.dump_fetches else None
    rom = PatternRom(args.rom, fetches)
    r = Renderer(st, rom)
    bitmap = r.render(args.layer)
    rgb = r.to_rgb(bitmap)
    if args.out:
        pngio.write(args.out, W, H, rgb)
    if args.raw:
        with open(args.raw, 'wb') as f:
            f.write(bytes(p & 0xff for p in bitmap))
    if args.dump_fetches:
        with open(args.dump_fetches, 'w') as f:
            for a in sorted(fetches):
                f.write(f'{a:06x}\n')
        if not args.quiet:
            print(f'{len(fetches)} pattern ROM bytes fetched')
    if args.compare:
        n = compare(rgb, args.compare, args.diff, args.quiet)
        print(('PASS' if n == 0 else 'FAIL') + f' {os.path.basename(args.state)} ({n} differing pixels)')
        sys.exit(0 if n == 0 else 1)


if __name__ == '__main__':
    main()
