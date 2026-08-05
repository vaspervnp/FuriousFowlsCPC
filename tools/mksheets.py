#!/usr/bin/env python3
# ============================================================================
#  mksheets.py — EXPORT the editable spritesheets.
#
#      python3 tools/mksheets.py            write any sheet that is missing
#      python3 tools/mksheets.py --force    overwrite, losing your edits
#      python3 tools/mksheets.py creatures  just that one
#
#  The art below is the game's starting point, drawn in code so the
#  repository never depends on a binary blob nobody can regenerate. Once a
#  sheet exists on disk it is YOURS: `make` reads it back (tools/gen_art.py)
#  and this script will not touch it again unless you ask with --force.
#  Edit the PNGs in any pixel editor — load assets/sheets/fowls.gpl so the
#  palette is right — and rebuild.
#
#  Scenery is drawn WHOLE (a tree on a 32x128 canvas, a cloud on 64x64) and
#  then sliced into the 32x64 sheet cells the game streams. Drawing the
#  halves separately never lines up.
# ============================================================================
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import artlib
from sheetdefs import (BIRDS, PIGS, CREATURE_FRAMES, CREATURE_W, CREATURE_H,
                       CREATURE_COLS, BLOCK_PIECES, BLOCK_SETS, BLOCK_W,
                       BLOCK_H, BLOCK_COLS, SCENERY_CELLS, SCENERY_W,
                       SCENERY_H, SCENERY_COLS, SHEETS)

T = artlib.TRANSPARENT
BLACK, WHITE = 1, 2
LEAF, LEAF2, TRUNK, BARK = 7, 6, 11, 4
STONE, STONE2, SHADE = 10, 2, 14


# ---------------------------------------------------------------------------
#  A tiny raster toolkit. Everything is a list of rows of pen indices.
# ---------------------------------------------------------------------------
def cell(w, h, pen=T):
    return [[pen] * w for _ in range(h)]


def put(c, x, y, pen):
    if 0 <= y < len(c) and 0 <= x < len(c[0]):
        c[y][x] = pen


def rect(c, x0, y0, x1, y1, pen):
    for y in range(int(y0), int(y1) + 1):
        for x in range(int(x0), int(x1) + 1):
            put(c, x, y, pen)


def ellipse(c, cx, cy, rx, ry, pen):
    for y in range(len(c)):
        dy = (y - cy) / float(ry)
        if abs(dy) > 1.0:
            continue
        half = rx * (1.0 - dy * dy) ** 0.5
        for x in range(int(round(cx - half)), int(round(cx + half)) + 1):
            put(c, x, y, pen)


def triangle(c, pts, pen):
    (x0, y0), (x1, y1), (x2, y2) = pts

    def side(ax, ay, bx, by, px, py):
        return (bx - ax) * (py - ay) - (by - ay) * (px - ax)

    xs, ys = [x0, x1, x2], [y0, y1, y2]
    for y in range(max(0, min(ys)), min(len(c) - 1, max(ys)) + 1):
        for x in range(max(0, min(xs)), min(len(c[0]) - 1, max(xs)) + 1):
            d0 = side(x0, y0, x1, y1, x, y)
            d1 = side(x1, y1, x2, y2, x, y)
            d2 = side(x2, y2, x0, y0, x, y)
            if (d0 >= 0 and d1 >= 0 and d2 >= 0) or \
               (d0 <= 0 and d1 <= 0 and d2 <= 0):
                put(c, x, y, pen)


def outline(c, pen=BLACK):
    """Wrap every solid region in a one-pixel border, drawn into the
    transparent pixels around it — so nothing already drawn is lost."""
    h, w = len(c), len(c[0])
    edge = []
    for y in range(h):
        for x in range(w):
            if c[y][x] != T:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < h and c[ny][nx] not in (T, pen):
                    edge.append((x, y))
                    break
    for x, y in edge:
        c[y][x] = pen


def underside(c, pen, depth=3, match=WHITE):
    """Shade the bottom few pixels of every column of `match`, which is
    what turns a flat white blob into something with a lit top."""
    h = len(c)
    for x in range(len(c[0])):
        low = None
        for y in range(h - 1, -1, -1):
            if c[y][x] == match:
                low = y
                break
        if low is None:
            continue
        for y in range(max(0, low - depth + 1), low + 1):
            if c[y][x] == match:
                c[y][x] = pen


# ---------------------------------------------------------------------------
#  Faces: eyes and beaks, shared by both species.
# ---------------------------------------------------------------------------
def eye_open(c, x, y, pupil_dx=0, wide=False):
    if wide:
        rect(c, x, y - 1, x + 3, y + 4, WHITE)
        rect(c, x + 1 + pupil_dx, y + 1, x + 2 + pupil_dx, y + 2, BLACK)
    else:
        rect(c, x, y, x + 2, y + 3, WHITE)
        rect(c, x + 1 + pupil_dx, y + 1, x + 1 + pupil_dx, y + 2, BLACK)


def eye_shut(c, x, y):
    rect(c, x, y + 1, x + 2, y + 1, BLACK)
    put(c, x - 1, y, BLACK)
    put(c, x + 3, y, BLACK)


def eye_happy(c, x, y, up=True):
    """A closed, upturned arc — the laugh."""
    if up:
        put(c, x, y + 1, BLACK)
        put(c, x + 1, y, BLACK)
        put(c, x + 2, y + 1, BLACK)
    else:
        put(c, x, y, BLACK)
        put(c, x + 1, y + 1, BLACK)
        put(c, x + 2, y, BLACK)


def eye_cross(c, x, y):
    for i in range(3):
        put(c, x + i, y + i, BLACK)
        put(c, x + 2 - i, y + i, BLACK)


# ---------------------------------------------------------------------------
#  BIRDS. Six states from one body plan; the geometry table does the work.
#            centre-y  rx  ry
# ---------------------------------------------------------------------------
BIRD_POSE = {
    'idle':  (19, 7, 11),
    'blink': (19, 7, 11),
    'ready': (20, 6, 11),      # hauled back on the sling: tall and tense
    'fly':   (19, 8, 10),      # stretched out along the trajectory
    'hurt':  (22, 8,  9),      # squashed by the impact
    'dead':  (27, 8,  4),      # a puddle on the ground
}


def draw_bird(body, belly, beak, brow, frame):
    c = cell(CREATURE_W, CREATURE_H)
    cy, rx, ry = BIRD_POSE[frame]

    if frame == 'fly':                       # wings swept back behind it
        triangle(c, [(0, cy - 8), (8, cy - 2), (0, cy + 2)], belly)
        triangle(c, [(0, cy - 3), (7, cy + 1), (0, cy + 7)], body)
    elif frame in ('idle', 'blink', 'ready'):
        rect(c, 0, cy - 2, 2, cy + 2, body)  # folded tail feathers

    # the tuft: proud when idle, blown back in flight, gone when dead
    top = cy - ry
    if frame in ('idle', 'blink'):
        for x in (6, 8, 10):
            rect(c, x, top - 4, x, top, body)
    elif frame == 'ready':
        for x, y in ((5, top - 4), (3, top - 3), (1, top - 2)):
            rect(c, x, y, x + 1, y + 1, body)
    elif frame == 'fly':
        for x, y in ((6, top - 3), (4, top - 2), (2, top - 1)):
            rect(c, x, y, x + 1, y + 1, body)
    elif frame == 'hurt':
        rect(c, 5, top - 1, 10, top, body)

    ellipse(c, 7.5, cy, rx, ry, body)
    ellipse(c, 7.5, cy + ry * 0.35, rx * 0.62, ry * 0.5, belly)

    ey = cy - ry + 3
    if frame in ('hurt', 'dead'):
        eye_cross(c, 3, ey)
        eye_cross(c, 10, ey)
    elif frame == 'blink':
        eye_shut(c, 3, ey)
        eye_shut(c, 10, ey)
    elif frame == 'fly':
        eye_shut(c, 3, ey)
        eye_shut(c, 10, ey)
        rect(c, 2, ey - 2, 5, ey - 2, brow)
        rect(c, 10, ey - 2, 13, ey - 2, brow)
    else:
        eye_open(c, 3, ey, 1, wide=(frame == 'ready'))
        eye_open(c, 10, ey, 0, wide=(frame == 'ready'))
        rect(c, 3, ey - 2, 5, ey - 2, brow)
        rect(c, 10, ey - 2, 12, ey - 2, brow)
        put(c, 6, ey - 1, brow)
        put(c, 9, ey - 1, brow)
        if frame == 'ready':                 # furious: brows driven down
            rect(c, 4, ey - 1, 6, ey - 1, brow)
            rect(c, 9, ey - 1, 11, ey - 1, brow)

    by = cy + 1
    if frame in ('ready', 'fly'):             # beak open, mid-screech
        triangle(c, [(5, by - 1), (11, by - 1), (7, by - 4)], beak)
        triangle(c, [(5, by + 1), (11, by + 1), (7, by + 5)], beak)
    elif frame == 'dead':
        rect(c, 6, by, 10, by + 1, beak)
    else:
        triangle(c, [(5, by), (10, by), (7, by + 4)], beak)
        rect(c, 5, by, 10, by + 1, beak)

    outline(c)
    return c


# ---------------------------------------------------------------------------
#  PIGS.     centre-y  rx  ry
# ---------------------------------------------------------------------------
PIG_POSE = {
    'idle':  (20, 7, 11),
    'blink': (20, 7, 11),
    'ready': (20, 7, 11),      # it has seen the bird
    'fly':   (20, 7, 11),      # laughing: you missed
    'hurt':  (23, 8,  8),
    'dead':  (28, 8,  3),      # popped
}


def draw_pig(body, belly, snout, gear, frame):
    c = cell(CREATURE_W, CREATURE_H)
    cy, rx, ry = PIG_POSE[frame]
    top = cy - ry

    if frame != 'dead':
        triangle(c, [(2, top + 2), (6, top + 2), (3, top - 4)], body)
        triangle(c, [(13, top + 2), (9, top + 2), (12, top - 4)], body)

    ellipse(c, 7.5, cy, rx, ry, body)
    ellipse(c, 7.5, cy + ry * 0.4, rx * 0.7, ry * 0.45, belly)

    ey = top + 4
    if frame in ('hurt', 'dead'):
        eye_cross(c, 3, ey)
        eye_cross(c, 10, ey)
    elif frame == 'blink':
        eye_shut(c, 3, ey)
        eye_shut(c, 10, ey)
    elif frame == 'fly':
        eye_happy(c, 3, ey + 1)
        eye_happy(c, 10, ey + 1)
    else:
        eye_open(c, 3, ey, 1, wide=(frame == 'ready'))
        eye_open(c, 10, ey, 0, wide=(frame == 'ready'))

    sy = cy + 2
    ellipse(c, 7.5, sy, 4, 3, snout)
    put(c, 6, sy, BLACK)
    put(c, 9, sy, BLACK)
    if frame == 'ready':                      # jaw dropped
        rect(c, 5, sy + 4, 10, sy + 5, BLACK)
    elif frame == 'fly':                      # a wide grin
        rect(c, 4, sy + 4, 11, sy + 4, BLACK)
        put(c, 3, sy + 3, BLACK)
        put(c, 12, sy + 3, BLACK)

    if gear and frame != 'dead':
        if gear == 5:                         # the king's crown
            rect(c, 3, top - 5, 12, top - 2, gear)
            for x in (3, 7, 12):
                rect(c, x, top - 8, x, top - 6, gear)
            rect(c, 3, top - 2, 12, top - 1, BARK)
        else:                                 # a battered helmet
            ellipse(c, 7.5, top + 1, 8, 5, gear)
            rect(c, 0, top + 1, 15, top + 2, gear)
            rect(c, 2, top - 2, 13, top - 2, WHITE)

    if frame == 'dead':                       # the pop: a scatter of bits
        for x, y in ((1, 24), (14, 25), (3, 21), (12, 22)):
            put(c, x, y, body)

    outline(c)
    return c


# ---------------------------------------------------------------------------
#  BLOCKS — ten shapes, painted in each material set's four pens.
# ---------------------------------------------------------------------------
def draw_block(piece, pens):
    face, light, dark, detail = pens
    w, h = BLOCK_W, BLOCK_H
    c = cell(w, h)

    def bevel(x0, y0, x1, y1):
        rect(c, x0, y0, x1, y0, light)
        rect(c, x0, y0, x0, y1, light)
        rect(c, x0, y1, x1, y1, dark)
        rect(c, x1, y0, x1, y1, dark)

    if piece == 'beam_h':
        rect(c, 0, 1, w - 1, h - 2, face)
        bevel(0, 1, w - 1, h - 2)
        for y in (5, 10):
            for x in range(2, w - 2, 3):
                put(c, x, y, detail)
    elif piece == 'beam_v':
        rect(c, 2, 0, w - 3, h - 1, face)
        bevel(2, 0, w - 3, h - 1)
        for x in (5, 10):
            for y in range(1, h - 1, 3):
                put(c, x, y, detail)
    elif piece == 'cube':
        rect(c, 0, 0, w - 1, h - 1, face)
        bevel(0, 0, w - 1, h - 1)
        rect(c, 3, 3, w - 4, 3, detail)
        rect(c, 3, h - 4, w - 4, h - 4, detail)
    elif piece == 'brick':
        rect(c, 0, 0, w - 1, h - 1, face)
        for y in (0, 5, 10, 15):
            rect(c, 0, y, w - 1, y, dark)
        for i, y in enumerate((2, 7, 12)):
            off = 0 if i % 2 else 8
            for x in range(off, w, 8):
                rect(c, x, y - 2, x, y + 2, dark)
        bevel(0, 0, w - 1, h - 1)
    elif piece in ('roof_l', 'roof_r'):
        if piece == 'roof_l':
            triangle(c, [(0, h - 1), (w - 1, 0), (w - 1, h - 1)], face)
            for i in range(0, h, 3):
                put(c, w - 1 - i, i, light)
        else:
            triangle(c, [(0, 0), (w - 1, h - 1), (0, h - 1)], face)
            for i in range(0, h, 3):
                put(c, i, i, light)
        rect(c, 0, h - 1, w - 1, h - 1, dark)
    elif piece == 'arch':
        rect(c, 0, 4, w - 1, h - 1, face)
        ellipse(c, 7.5, 4, 8, 4, face)
        ellipse(c, 7.5, h, 4, 7, T)           # the doorway underneath
        rect(c, 0, 4, 0, h - 1, light)
        rect(c, w - 1, 4, w - 1, h - 1, dark)
    elif piece == 'pillar':
        rect(c, 4, 0, 11, h - 1, face)
        rect(c, 1, 0, w - 2, 2, face)         # capital
        rect(c, 1, h - 3, w - 2, h - 1, face)  # base
        bevel(4, 0, 11, h - 1)
        rect(c, 1, 0, w - 2, 0, light)
        rect(c, 1, h - 1, w - 2, h - 1, dark)
    elif piece == 'slab':
        rect(c, 0, 5, w - 1, 10, face)
        bevel(0, 5, w - 1, 10)
        rect(c, 3, 7, w - 4, 7, detail)
    elif piece == 'crate':
        rect(c, 0, 0, w - 1, h - 1, face)
        rect(c, 2, 2, w - 3, h - 3, T)        # hollow
        for i in range(h):
            put(c, 1 + i * (w - 3) // (h - 1), i, dark)
            put(c, w - 2 - i * (w - 3) // (h - 1), i, dark)
        bevel(0, 0, w - 1, h - 1)
    return c


# ---------------------------------------------------------------------------
#  SCENERY — each object drawn whole, then sliced into 32x64 sheet cells.
# ---------------------------------------------------------------------------
def slice_object(canvas):
    """Split a canvas into SCENERY_W x SCENERY_H cells, left-to-right
    within each band of rows, top band first."""
    h, w = len(canvas), len(canvas[0])
    cells = []
    for by in range(0, h, SCENERY_H):
        for bx in range(0, w, SCENERY_W):
            cells.append([[canvas[by + y][bx + x] for x in range(SCENERY_W)]
                          for y in range(SCENERY_H)])
    return cells


def tree_oak():                              # 32x128, broad and lumpy
    c = cell(32, 128)
    rect(c, 12, 62, 19, 127, TRUNK)
    rect(c, 12, 62, 13, 127, BARK)           # the sunlit side
    rect(c, 9, 120, 22, 127, TRUNK)          # roots flaring out
    rect(c, 6, 124, 25, 127, TRUNK)
    rect(c, 15, 70, 24, 72, TRUNK)           # a branch
    ellipse(c, 15.5, 44, 16, 42, LEAF)
    for cx, cy, r in ((7, 30, 8), (24, 34, 9), (16, 14, 11),
                      (5, 56, 8), (27, 58, 8)):
        ellipse(c, cx, cy, r, r * 0.95, LEAF)
    for cx, cy, r in ((10, 32, 5), (22, 44, 6), (16, 18, 6), (24, 60, 4)):
        ellipse(c, cx, cy, r, r * 0.8, LEAF2)
    return c


def tree_pine():                             # 32x128, a narrow spire
    c = cell(32, 128)
    rect(c, 13, 96, 18, 127, TRUNK)
    rect(c, 13, 96, 14, 127, BARK)
    rect(c, 10, 123, 21, 127, TRUNK)
    triangle(c, [(15, 2), (7, 38), (24, 38)], LEAF)
    triangle(c, [(15, 24), (3, 70), (28, 70)], LEAF)
    triangle(c, [(15, 54), (0, 104), (31, 104)], LEAF)
    for y in range(10, 100, 8):
        rect(c, 13, y, 18, y, LEAF2)
    return c


def bush(big):                               # 32x64
    c = cell(32, 64)
    base = 24 if big else 32
    ellipse(c, 15.5, 62, 16, 63 - base, LEAF)
    for cx, dy, r in ((7, 6, 8), (24, 9, 9), (16, 1, 10)):
        ellipse(c, cx, base + dy, r, r * 0.85, LEAF)
    for cx, dy, r in ((11, 10, 4), (21, 15, 5), (16, 5, 4)):
        ellipse(c, cx, base + dy, r, r * 0.7, LEAF2)
    rect(c, 0, 63, 31, 63, LEAF)
    return c


def cloud(fat):                              # 64x64
    c = cell(64, 64)
    if fat:
        ellipse(c, 31.5, 40, 30, 15, WHITE)
        for cx, cy, r in ((14, 30, 13), (34, 22, 16), (50, 32, 12)):
            ellipse(c, cx, cy, r, r * 0.85, WHITE)
    else:
        ellipse(c, 31.5, 38, 31, 8, WHITE)
        for cx, cy, r in ((20, 32, 10), (43, 30, 11)):
            ellipse(c, cx, cy, r, r * 0.7, WHITE)
    underside(c, SHADE, 3)
    return c


def slingshot(front):
    """32x64. `front` returns only the near prong, which is blitted back
    over the bird so the bird sits IN the fork instead of on top of it."""
    c = cell(32, 64)
    if not front:
        rect(c, 12, 36, 19, 63, TRUNK)       # the stem, driven into the turf
        rect(c, 12, 36, 13, 63, BARK)        # sunlit edge
        rect(c, 9, 57, 22, 63, TRUNK)        # a wedge of earth around it
        rect(c, 7, 60, 24, 63, TRUNK)
        triangle(c, [(11, 41), (17, 41), (4, 12)], TRUNK)    # far prong
        triangle(c, [(11, 41), (13, 41), (4, 12)], BARK)
        rect(c, 2, 8, 8, 14, TRUNK)          # the leather grip
        rect(c, 2, 8, 8, 9, BARK)
    else:
        triangle(c, [(14, 41), (20, 41), (27, 12)], TRUNK)   # near prong
        triangle(c, [(18, 41), (20, 41), (27, 12)], BARK)
        rect(c, 23, 8, 29, 14, TRUNK)
        rect(c, 23, 8, 29, 9, BARK)
    outline(c)
    return c


def boulder():                               # 64x64
    c = cell(64, 64)
    rect(c, 2, 50, 61, 63, STONE)
    triangle(c, [(6, 60), (28, 14), (50, 60)], STONE)
    triangle(c, [(40, 58), (54, 30), (62, 58)], STONE)
    triangle(c, [(28, 14), (38, 42), (20, 42)], STONE2)
    triangle(c, [(54, 30), (60, 50), (48, 50)], STONE2)
    rect(c, 8, 56, 24, 57, SHADE)
    rect(c, 0, 63, 63, 63, BLACK)
    return c


# ---------------------------------------------------------------------------
#  Sheet builders
# ---------------------------------------------------------------------------
def build_creatures():
    cells = []
    for _name, body, belly, beak, brow in BIRDS:
        for f in CREATURE_FRAMES:
            cells.append(draw_bird(body, belly, beak, brow, f))
    for _name, body, belly, snout, gear in PIGS:
        for f in CREATURE_FRAMES:
            cells.append(draw_pig(body, belly, snout, gear, f))
    return cells


def build_blocks():
    cells = []
    for _set, _tough, pens in BLOCK_SETS:
        for piece, _hp in BLOCK_PIECES:
            cells.append(draw_block(piece, pens))
    return cells


def build_scenery():
    cells = (slice_object(tree_oak()) + slice_object(tree_pine())
             + slice_object(bush(True)) + slice_object(bush(False))
             + slice_object(cloud(True)) + slice_object(cloud(False))
             + slice_object(boulder())
             + [slingshot(False), slingshot(True)])
    if len(cells) != len(SCENERY_CELLS):
        raise SystemExit('scenery: built %d cells, sheetdefs wants %d'
                         % (len(cells), len(SCENERY_CELLS)))
    return cells


BUILDERS = {
    'creatures': (build_creatures, CREATURE_W, CREATURE_H, CREATURE_COLS),
    'blocks':    (build_blocks, BLOCK_W, BLOCK_H, BLOCK_COLS),
    'scenery':   (build_scenery, SCENERY_W, SCENERY_H, SCENERY_COLS),
}


def main(argv):
    force = '--force' in argv
    want = [a for a in argv[1:] if not a.startswith('-')] or sorted(BUILDERS)
    os.makedirs('assets/sheets', exist_ok=True)
    artlib.write_gpl('assets/sheets/fowls.gpl')
    for name in want:
        if name not in BUILDERS:
            raise SystemExit('unknown sheet %r (have: %s)'
                             % (name, ', '.join(sorted(BUILDERS))))
        path = SHEETS[name]['path']
        if os.path.exists(path) and not force:
            print('%-28s kept (use --force to overwrite your edits)' % path)
            continue
        build, cw, ch, cols = BUILDERS[name]
        cells = build()
        artlib.sheet_write(path, cells, cw, ch, cols)
        print('%-28s %d cells of %dx%d' % (path, len(cells), cw, ch))


if __name__ == '__main__':
    main(sys.argv)
