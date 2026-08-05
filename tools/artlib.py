# ============================================================================
#  artlib.py — FURIOUS FOWLS art pipeline core.
#
#  Everything the game draws is authored as a SPRITESHEET PNG under
#  assets/sheets/. This module is the codec and the palette contract:
#
#    * a dependency-free PNG reader/writer (no PIL — the build stays
#      installable with nothing but python3), deliberately forgiving about
#      what a pixel editor saves: RGB / RGBA / greyscale / indexed,
#      1/2/4/8-bit palettes, any scanline filter.
#    * ART_PALETTE — the sixteen Mode 0 pens, as the RGB values a pixel
#      editor shows. Pen 0 is TRANSPARENT (magenta in the editor); the
#      other fifteen are the CPC hardware colours the game loads.
#    * sheet slicing / assembly, so a sheet is just a grid of cells.
#
#  Read colours are nearest-matched, so mild colour drift from an editor
#  is tolerated; anything genuinely off-palette is a build error naming
#  the offending pixel, because a wrong pen is invisible until it is on
#  screen in the wrong colour.
# ============================================================================
import struct
import zlib

# ---------------------------------------------------------------------------
#  The palette. Index == Mode 0 pen number. The editor RGB values are the
#  ones written into exported sheets and matched on import; the comment is
#  the CPC hardware colour src/hardware.inc loads into that pen.
#  Pen 0 is never drawn by a sprite — it is the transparency key.
# ---------------------------------------------------------------------------
ART_PALETTE = [
    (255,   0, 255),   # 0  TRANSPARENT (sky shows through)      HW_SKY_BLUE
    (  0,   0,   0),   # 1  outline black                        HW_BLACK
    (255, 255, 255),   # 2  white                                HW_BRIGHT_WHITE
    (255,   0,   0),   # 3  red                                  HW_BRIGHT_RED
    (255, 128,   0),   # 4  orange / wood                        HW_ORANGE
    (255, 255,   0),   # 5  yellow / beak                        HW_BRIGHT_YELLOW
    (  0, 255,   0),   # 6  bright green / pig                   HW_BRIGHT_GREEN
    (  0, 128,   0),   # 7  dark green / foliage                 HW_GREEN
    (  0, 255, 255),   # 8  cyan / ice                           HW_BRIGHT_CYAN
    (  0,   0, 255),   # 9  blue                                 HW_BLUE
    (128, 128, 128),   # 10 grey / stone                         HW_WHITE
    (128,   0,   0),   # 11 brown / trunk / dark wood            HW_RED
    (255, 128, 192),   # 12 pink                                 HW_PINK
    (255, 255, 128),   # 13 sand / pale yellow                   HW_PASTEL_YELLOW
    (128, 128, 255),   # 14 pale blue / highlight                HW_PASTEL_BLUE
    (128,   0, 128),   # 15 purple                               HW_MAGENTA
]

PEN_NAMES = [
    'transparent', 'black', 'white', 'red', 'orange', 'yellow',
    'green', 'dgreen', 'cyan', 'blue', 'grey', 'brown',
    'pink', 'sand', 'paleblue', 'purple',
]

TRANSPARENT = 0


# ---------------------------------------------------------------------------
#  PNG writing
# ---------------------------------------------------------------------------
def _chunk(tag, data):
    body = tag + data
    return struct.pack('>I', len(data)) + body + struct.pack('>I',
                                                             zlib.crc32(body))


def write_png(path, pixels):
    """pixels: list of rows, each a list of pen indices (0..15)."""
    h = len(pixels)
    w = len(pixels[0])
    raw = bytearray()
    for row in pixels:
        raw.append(0)                       # filter type 0 (None)
        for pen in row:
            raw += bytes(ART_PALETTE[pen])
    png = (b'\x89PNG\r\n\x1a\n'
           + _chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0))
           + _chunk(b'IDAT', zlib.compress(bytes(raw), 9))
           + _chunk(b'IEND', b''))
    with open(path, 'wb') as f:
        f.write(png)


# ---------------------------------------------------------------------------
#  PNG reading
# ---------------------------------------------------------------------------
def _decode(path):
    d = open(path, 'rb').read()
    if d[:8] != b'\x89PNG\r\n\x1a\n':
        raise SystemExit('%s: not a PNG file' % path)
    idat, plte, trns = b'', None, None
    interlace = 0
    pos = 8
    while pos < len(d):
        ln = int.from_bytes(d[pos:pos + 4], 'big')
        typ, c = d[pos + 4:pos + 8], d[pos + 8:pos + 8 + ln]
        pos += 12 + ln
        if typ == b'IHDR':
            w, h, depth, ctype, _, _, interlace = struct.unpack('>IIBBBBB', c)
        elif typ == b'PLTE':
            plte = c
        elif typ == b'tRNS':
            trns = c
        elif typ == b'IDAT':
            idat += c
        elif typ == b'IEND':
            break
    if interlace:
        raise SystemExit('%s: interlaced PNG — re-save non-interlaced' % path)
    if ctype == 3:
        if depth not in (1, 2, 4, 8):
            raise SystemExit('%s: %d-bit palette PNG unsupported'
                             % (path, depth))
    elif depth != 8:
        raise SystemExit('%s: %d-bit PNG — re-save as 8-bit' % (path, depth))
    if ctype not in (0, 2, 3, 6):
        raise SystemExit('%s: unsupported colour type %d' % (path, ctype))

    nch = {0: 1, 2: 3, 3: 1, 6: 4}[ctype]
    bpp = max(1, (depth * nch) // 8)
    stride = (w * depth * nch + 7) // 8
    raw = zlib.decompress(idat)
    lines, prev, p = [], bytearray(stride), 0
    for _ in range(h):
        f = raw[p]
        line = bytearray(raw[p + 1:p + 1 + stride])
        p += 1 + stride
        for i in range(stride):
            a = line[i - bpp] if i >= bpp else 0
            b = prev[i]
            c = prev[i - bpp] if i >= bpp else 0
            if f == 1:
                line[i] = (line[i] + a) & 255
            elif f == 2:
                line[i] = (line[i] + b) & 255
            elif f == 3:
                line[i] = (line[i] + ((a + b) >> 1)) & 255
            elif f == 4:
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                line[i] = (line[i] + (a if pa <= pb and pa <= pc
                                      else b if pb <= pc else c)) & 255
        lines.append(line)
        prev = line

    px = []
    for line in lines:
        row = []
        for x in range(w):
            if ctype == 3:
                if depth == 8:
                    i = line[x]
                else:
                    bit = x * depth
                    i = ((line[bit // 8] >> (8 - depth - bit % 8))
                         & ((1 << depth) - 1))
                r, g, b = plte[i * 3:i * 3 + 3]
                a = trns[i] if trns and i < len(trns) else 255
            elif ctype == 0:
                r = g = b = line[x]
                a = 255
            elif ctype == 2:
                r, g, b = line[x * 3:x * 3 + 3]
                a = 255
            else:
                r, g, b, a = line[x * 4:x * 4 + 4]
            row.append((r, g, b, a))
        px.append(row)
    return w, h, px


def read_png(path):
    """-> (width, height, rows of pen indices). Alpha < 50% reads as pen 0."""
    w, h, px = _decode(path)
    out = []
    for y in range(h):
        row = []
        for x in range(w):
            r, g, b, a = px[y][x]
            if a < 128:
                row.append(TRANSPARENT)
                continue
            best = min(range(16),
                       key=lambda p: (r - ART_PALETTE[p][0]) ** 2
                       + (g - ART_PALETTE[p][1]) ** 2
                       + (b - ART_PALETTE[p][2]) ** 2)
            cr, cg, cb = ART_PALETTE[best]
            if (r - cr) ** 2 + (g - cg) ** 2 + (b - cb) ** 2 > 3 * 80 * 80:
                raise SystemExit(
                    '%s: pixel (%d,%d) is rgb(%d,%d,%d), which is not one of '
                    'the sixteen art pens.\n  Load assets/sheets/fowls.gpl in '
                    'your editor and use only those colours.' % (path, x, y,
                                                                 r, g, b))
            row.append(best)
        out.append(row)
    return w, h, out


# ---------------------------------------------------------------------------
#  Sheets: a PNG holding a grid of equally sized cells, laid out left to
#  right then top to bottom. Cells are separated by a 1px guide line drawn
#  in the transparent key so the grid is visible while editing; the reader
#  skips those guides. GUIDE == 1 keeps arithmetic trivial.
# ---------------------------------------------------------------------------
GUIDE = 1


def sheet_size(cell_w, cell_h, cols, rows):
    return (cols * (cell_w + GUIDE) + GUIDE, rows * (cell_h + GUIDE) + GUIDE)


def sheet_write(path, cells, cell_w, cell_h, cols):
    """cells: list of cell bitmaps (each cell_h rows of cell_w pens)."""
    rows = (len(cells) + cols - 1) // cols
    w, h = sheet_size(cell_w, cell_h, cols, rows)
    img = [[TRANSPARENT] * w for _ in range(h)]
    for i, cell in enumerate(cells):
        cx = GUIDE + (i % cols) * (cell_w + GUIDE)
        cy = GUIDE + (i // cols) * (cell_h + GUIDE)
        for y in range(cell_h):
            for x in range(cell_w):
                img[cy + y][cx + x] = cell[y][x]
    write_png(path, img)


def sheet_read(path, cell_w, cell_h, cols, count):
    """Inverse of sheet_write. Returns exactly `count` cell bitmaps."""
    rows = (count + cols - 1) // cols
    want_w, want_h = sheet_size(cell_w, cell_h, cols, rows)
    w, h, img = read_png(path)
    if (w, h) != (want_w, want_h):
        raise SystemExit(
            '%s: sheet is %dx%d but should be %dx%d '
            '(%d cells of %dx%d, %d per row, 1px guides).\n'
            '  Re-export with `make sprites-export` if you resized it by '
            'accident.' % (path, w, h, want_w, want_h, count,
                           cell_w, cell_h, cols))
    cells = []
    for i in range(count):
        cx = GUIDE + (i % cols) * (cell_w + GUIDE)
        cy = GUIDE + (i // cols) * (cell_h + GUIDE)
        cells.append([[img[cy + y][cx + x] for x in range(cell_w)]
                      for y in range(cell_h)])
    return cells


# ---------------------------------------------------------------------------
#  Packing for the CPC: two pixels per byte, high nibble = left pixel.
#  This is the on-target art format; the runtime blitter turns each byte
#  into a Mode 0 (mask, data) pair through a pair of 256-entry LUTs.
# ---------------------------------------------------------------------------
def pack_nibbles(cell):
    out = bytearray()
    for row in cell:
        if len(row) & 1:
            raise SystemExit('cell width must be even, got %d' % len(row))
        for x in range(0, len(row), 2):
            out.append((row[x] << 4) | row[x + 1])
    return bytes(out)


def emit_bytes(fp, data, indent='        ', per_line=16):
    for i in range(0, len(data), per_line):
        fp.write('%sdb      %s\n'
                 % (indent, ','.join('#%02X' % b for b in data[i:i + per_line])))


# ---------------------------------------------------------------------------
#  GIMP/Aseprite palette file, so the editor offers exactly these pens.
# ---------------------------------------------------------------------------
def write_gpl(path):
    with open(path, 'w') as f:
        f.write('GIMP Palette\nName: Furious Fowls\nColumns: 4\n#\n')
        for i, (r, g, b) in enumerate(ART_PALETTE):
            f.write('%3d %3d %3d\t%d %s\n' % (r, g, b, i, PEN_NAMES[i]))
