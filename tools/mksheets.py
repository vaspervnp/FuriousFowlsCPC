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
from sheetdefs import (DRAW_CREATURE_W, DRAW_CREATURE_H,
                       BIRDS, PIGS, CREATURE_FRAMES, CREATURE_W, CREATURE_H,
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


def reduce_cell(c, dw, dh):
    """Shrink a finished cell to dw x dh.

    Pixel art does not survive averaging: a beak two pixels wide averages
    into the body and disappears. So each destination pixel takes the
    commonest pen in the source area it covers, and ANY ink beats the
    background — a feature that is outnumbered still shows, which for a
    sprite this small is the difference between an eye and a smudge.
    """
    sh, sw = len(c), len(c[0])
    out = cell(dw, dh)
    for dy in range(dh):
        y0, y1 = dy * sh // dh, max(dy * sh // dh + 1, (dy + 1) * sh // dh)
        for dx in range(dw):
            x0, x1 = dx * sw // dw, max(dx * sw // dw + 1, (dx + 1) * sw // dw)
            n = {}
            for y in range(y0, y1):
                for x in range(x0, x1):
                    p = c[y][x]
                    n[p] = n.get(p, 0) + 1
            ink = {p: k for p, k in n.items() if p != T}
            src = ink or n
            out[dy][dx] = max(src, key=lambda p: src[p])
    return out


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
    c = cell(DRAW_CREATURE_W, DRAW_CREATURE_H)
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
    c = cell(DRAW_CREATURE_W, DRAW_CREATURE_H)
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
    """One piece of timber, drawn at the size it is shown at.

    These used to be sixteen-pixel drawings put through reduce_cell, and
    that is why they came out off-centre and clipped: the coordinates said
    sixteen and the canvas said ten. Ten is not a size you reduce INTO.
    Every feature here is one or two pixels across, and a majority vote on
    a two-pixel feature is a coin toss — so the pieces are drawn by hand
    at ten by ten instead.

    A Mode 0 pixel is twice as wide as it is tall, so a cell shows up on
    screen as a wide rectangle. That is what makes the members read as
    timber: an upright three pixels across is under a third of the cell,
    and a plank two rows deep is a plank rather than a wall with a hole
    in it. Nothing fills its cell except the brick.
    """
    face, light, dark, _detail = pens
    w, h = BLOCK_W, BLOCK_H
    c = cell(w, h)

    def plank_h(y0, y1):
        """A member lying flat: lit along the top, in shadow underneath,
        with sawn ends and grain running the long way."""
        rect(c, 0, y0, w - 1, y1, face)
        rect(c, 0, y0, w - 1, y0, light)
        rect(c, 0, y1, w - 1, y1, dark)
        rect(c, 0, y0, 0, y1, dark)
        rect(c, w - 1, y0, w - 1, y1, dark)
        if y1 - y0 >= 2:                     # grain, if there is a face left
            for x in range(2, w - 2, 3):     # to put it on
                put(c, x, (y0 + y1) // 2, dark)

    def plank_v(x0, x1):
        """...and one standing on end. The lit edge goes on the left, so a
        row of uprights all catch the light from the same side."""
        rect(c, x0, 0, x1, h - 1, face)
        rect(c, x0, 0, x0, h - 1, light)
        rect(c, x1, 0, x1, h - 1, dark)
        rect(c, x0, 0, x1, 0, dark)
        rect(c, x0, h - 1, x1, h - 1, dark)
        if x1 - x0 >= 2:
            for y in range(2, h - 2, 3):
                put(c, (x0 + x1) // 2, y, dark)

    if piece == 'beam_h':                    # the standard lintel
        plank_h(4, 6)
    elif piece == 'beam_v':                  # the standard upright
        plank_v(4, 6)
    elif piece == 'cube':                    # a sawn offcut, load bearing
        rect(c, 2, 2, 7, 7, face)
        rect(c, 2, 2, 7, 2, light)
        rect(c, 2, 7, 7, 7, dark)
        rect(c, 2, 2, 2, 7, light)
        rect(c, 7, 2, 7, 7, dark)
        for y in (4, 6):
            for x in range(3, 7, 2):
                put(c, x, y, dark)
    elif piece == 'brick':                   # the one piece that IS its cell
        rect(c, 0, 1, w - 1, h - 2, face)
        rect(c, 0, 1, w - 1, 1, light)
        rect(c, 0, h - 2, w - 1, h - 2, dark)
        for y in (4, 7):                     # courses...
            rect(c, 0, y, w - 1, y, dark)
        for i, y in enumerate((2, 5, 8)):    # ...broken by staggered joints
            for x in range(1 + 4 * (i % 2), w, 5):
                put(c, x, y, dark)
    elif piece in ('roof_l', 'roof_r'):      # a rafter, not a solid wedge
        for i in range(h):
            x = i if piece == 'roof_r' else w - 1 - i
            put(c, x, i, light)
            put(c, x - 1 if piece == 'roof_r' else x + 1, i, face)
        rect(c, 0, h - 1, w - 1, h - 1, dark)
    elif piece == 'arch':                    # a lintel on two short legs
        plank_h(0, 1)
        rect(c, 0, 2, 1, h - 1, face)
        rect(c, w - 2, 2, w - 1, h - 1, face)
        rect(c, 0, 2, 0, h - 1, light)
        rect(c, 1, 2, 1, h - 1, dark)
        rect(c, w - 2, 2, w - 2, h - 1, light)
        rect(c, w - 1, 2, w - 1, h - 1, dark)
    elif piece == 'pillar':                  # a bare stick, the slenderest
        plank_v(4, 5)
        put(c, 4, 3, dark)                   # a knot or two
        put(c, 5, 7, face)
    elif piece == 'slab':                    # a shelf, one plank deep
        rect(c, 0, 5, w - 1, 5, light)
        rect(c, 0, 6, w - 1, 6, dark)
        rect(c, 0, 5, 0, 6, dark)
        rect(c, w - 1, 5, w - 1, 6, dark)
    elif piece == 'crate':                   # hollow, and the weak point
        rect(c, 1, 1, w - 2, h - 2, face)
        rect(c, 3, 3, w - 4, h - 4, T)
        rect(c, 1, 1, w - 2, 1, light)
        rect(c, 1, h - 2, w - 2, h - 2, dark)
        rect(c, 1, 1, 1, h - 2, light)
        rect(c, w - 2, 1, w - 2, h - 2, dark)
        for i in range(2, h - 2):            # a diagonal brace across it
            put(c, 1 + (i - 2) * (w - 4) // (h - 5), i, dark)
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
    """Nothing here is centred and nothing is mirrored. The canopy leans
    right, the trunk leans with it, and the lobes are all different sizes —
    a tree drawn symmetrically reads as a logo, not as a plant."""
    c = cell(32, 128)
    rect(c, 13, 66, 20, 127, TRUNK)          # trunk, leaning a little right
    rect(c, 12, 84, 19, 127, TRUNK)
    rect(c, 13, 66, 14, 100, BARK)           # the sunlit edge, and it stops
    rect(c, 12, 100, 13, 122, BARK)          # short of the roots
    ellipse(c, 10, 124, 9, 5, TRUNK)         # roots, unevenly flared
    ellipse(c, 23, 125, 7, 4, TRUNK)
    rect(c, 19, 74, 27, 76, TRUNK)           # two branches, different lengths
    rect(c, 25, 71, 27, 76, TRUNK)
    rect(c, 6, 88, 13, 90, TRUNK)

    ellipse(c, 17, 42, 15, 40, LEAF)         # the mass, off centre
    for cx, cy, rx, ry in ((6, 34, 8, 7), (25, 30, 10, 9), (14, 11, 12, 9),
                           (4, 58, 7, 8), (27, 61, 9, 7), (20, 68, 8, 6),
                           (9, 70, 6, 5)):
        ellipse(c, cx, cy, rx, ry, LEAF)
    for cx, cy, rx, ry in ((12, 26, 8, 5), (18, 14, 8, 5)):
        ellipse(c, cx, cy, rx, ry, LEAF2)    # where the sun gets in
    return c


def tree_pine():                             # 32x128, a narrow spire
    """Built from staggered tufts rather than three triangles. The spire
    still reads as a conifer, but every bough is a different width and
    hangs a different distance, and there is not a straight edge or a point
    anywhere on it."""
    c = cell(32, 128)
    rect(c, 14, 98, 19, 127, TRUNK)
    rect(c, 14, 98, 15, 127, BARK)
    ellipse(c, 12, 125, 8, 4, TRUNK)
    ellipse(c, 22, 126, 6, 3, TRUNK)

    #  (centre x, centre y, half width, half depth) — boughs, widening as
    #  they go down, alternately reaching further left and further right.
    for cx, cy, rx, ry in ((16, 8, 5, 6), (14, 17, 8, 6), (18, 25, 9, 6),
                           (13, 35, 12, 7), (19, 45, 13, 7), (14, 56, 15, 8),
                           (18, 67, 15, 8), (15, 79, 16, 8), (17, 90, 14, 8)):
        ellipse(c, cx, cy, rx, ry, LEAF)
    for cx, cy, rx, ry in ((13, 34, 7, 3), (12, 66, 8, 3)):
        ellipse(c, cx, cy, rx, ry, LEAF2)    # the lit top of each bough
    return c


def bush(big):                               # 32x64
    """Two different shrubs, not one shrub at two sizes: the big one is
    lopsided to the right, the small one to the left, and neither has a
    lobe the same size as its neighbour."""
    c = cell(32, 64)
    base = 24 if big else 32
    ellipse(c, 15.5, 62, 16, 63 - base, LEAF)
    if big:
        lobes = ((6, 8, 8, 7), (24, 5, 10, 9), (15, 0, 11, 8),
                 (29, 13, 6, 6), (2, 16, 5, 5))
        lit = ((13, 9, 9, 4),)

    else:
        lobes = ((9, 4, 10, 8), (22, 8, 8, 7), (16, 1, 8, 6), (3, 12, 5, 5))
        lit = ((11, 6, 8, 4),)

    for cx, dy, rx, ry in lobes:
        ellipse(c, cx, base + dy, rx, ry, LEAF)
    for cx, dy, rx, ry in lit:
        ellipse(c, cx, base + dy, rx, ry, LEAF2)
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


def boulder_round():                         # 64x64
    """Weathered and rounded, to sit beside the jagged one — a skyline of
    nothing but sharp peaks reads as scenery from a different game."""
    c = cell(64, 64)
    ellipse(c, 28, 45, 29, 22, STONE)        # the mass, sitting left of centre
    ellipse(c, 13, 51, 13, 12, STONE)
    ellipse(c, 48, 48, 16, 15, STONE)
    ellipse(c, 58, 55, 7, 8, STONE)
    rect(c, 0, 56, 63, 63, STONE)
    ellipse(c, 24, 33, 16, 7, STONE2)        # the sunlit crown, off centre
    ellipse(c, 47, 39, 10, 4, STONE2)
    for x, y, rx, ry in ((21, 53, 7, 2), (41, 56, 6, 3)):
        ellipse(c, x, y, rx, ry, SHADE)      # hollows worn into the face
    rect(c, 0, 63, 63, 63, BLACK)
    return c


def boulder():                               # 64x64
    """The craggy one — but crags made of overlapping lumps, not triangles.
    It keeps its broken silhouette and loses the points, which on a Mode 0
    pixel that is twice as wide as it is tall came out looking like torn
    paper anyway."""
    c = cell(64, 64)
    rect(c, 2, 52, 61, 63, STONE)
    for cx, cy, rx, ry in ((26, 34, 20, 20), (46, 44, 16, 14),
                           (12, 47, 12, 12), (35, 25, 11, 10),
                           (56, 50, 9, 9), (20, 22, 8, 7)):
        ellipse(c, cx, cy, rx, ry, STONE)
    for cx, cy, rx, ry in ((23, 27, 12, 5), (48, 41, 8, 4)):
        ellipse(c, cx, cy, rx, ry, STONE2)   # faces catching the light
    for cx, cy, rx, ry in ((33, 46, 8, 3),):
        ellipse(c, cx, cy, rx, ry, SHADE)    # clefts and hollows
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
    return [reduce_cell(c, CREATURE_W, CREATURE_H) for c in cells]


def build_blocks():
    cells = []
    for _set, _tough, pens in BLOCK_SETS:
        for piece, _hp, _tall in BLOCK_PIECES:
            cells.append(draw_block(piece, pens))
    return cells


def build_scenery():
    cells = (slice_object(tree_oak()) + slice_object(tree_pine())
             + slice_object(bush(True)) + slice_object(bush(False))
             + slice_object(cloud(True)) + slice_object(cloud(False))
             + slice_object(boulder())
             + slice_object(boulder_round())
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
