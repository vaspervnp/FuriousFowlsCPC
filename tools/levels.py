#!/usr/bin/env python3
# ============================================================================
#  levels.py — the fifty forts, as text you can edit.
#
#      python3 tools/levels.py --export        write any missing level file
#      python3 tools/levels.py --export --force  overwrite ALL of them
#      python3 tools/levels.py                 compile -> build/  (via make)
#
#  A level lives in assets/levels/levelNN.txt and looks like this:
#
#      name    FIRST PERCH
#      set     wood
#      sling   24
#      birds   red red yellow
#      scenery cloud_a 20 12 ; tree_a 240 40 ; bush_a 96 104
#      map
#      ....................
#      ..............hhhh..
#      ..............v..v..
#      ..............v.pv..
#      Y.............cccc..
#
#  The map is the fort, on the game's 20x10 grid of 16x16 cells. The LAST
#  map line rests on the ground; leading lines you leave out are sky, so a
#  short map is fine. One character per cell:
#
#      .  empty          h  beam_h    v  beam_v    c  cube     b  brick
#      /  roof_l         \  roof_r    a  arch      i  pillar   s  slab
#      x  crate
#      p  pig            P  helmet pig             K  king pig
#      Y  the slingshot (its column; `sling` overrides with an exact x)
#
#  A pig is two cells tall: the character marks its FEET, and the cell
#  above it has to be empty — the compiler says so if it is not.
#
#  Compiling writes build/levels.raw (a packed record per level, addressed
#  through an offset table) and build/level_defs.inc.
# ============================================================================
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sheetdefs import (BLOCK_PIECES, BLOCK_SETS, SCENERY_CELLS, BIRDS, PIGS)

LEVELS = 50
GRID_W, GRID_H = 32, 16
CELL = 10                       # pixels per grid cell, both ways. 32x10 is
                                # the same 320-pixel world as 20x16 was, and
                                # 16 rows of 10 still starts at y=8.
GROUND_Y = 168                  # world y of the top of the turf
TOP_Y = GROUND_Y - GRID_H * CELL        # y of grid row 0 == 8
WORLD_PX = GRID_W * CELL        # 320
MAX_BIRDS = 6
MAX_PIGS = 8
MAX_BLOCKS = 72        # what is left of the state block after
                       # seam_buf took four hundred bytes of it
MAX_SCENERY = 12       # 10 for the level, 2 reserved for the slingshot
MAX_LEVEL_SCENERY = 10

DIR = 'assets/levels'
BUILD = 'build'

PIECE_CH = {'h': 0, 'v': 1, 'c': 2, 'b': 3, '/': 4,
            '\\': 5, 'a': 6, 'i': 7, 's': 8, 'x': 9,
            '-': 10, '|': 11, 'o': 12, 'T': 13, 'g': 14, 'S': 15}

#  Pieces that are PLANKS: a run of them side by side is one rigid beam,
#  not a row of independent cubes. That is what lets a lintel tip over the
#  pillar it still has instead of dissolving into its cells — and it is
#  also what makes a rope a rope rather than a row of knots.
BEAM_CH = set('hs-')
ROPE_CH = set('-|')
MAX_BEAM = 8            # the length field is three bits
CH_PIECE = {v: k for k, v in PIECE_CH.items()}
PIG_CH = {'p': 0, 'P': 1, 'K': 2}
CH_PIG = {v: k for k, v in PIG_CH.items()}
SLING_CH = 'Y'

SET_NAMES = [s[0] for s in BLOCK_SETS]

# ===========================================================================
#  Themes — the sky and the ground under it.
#
#  This is the whole of the per-level background, and it costs no art at
#  all. The sky is PEN 0, which is also the sprite transparency key, so
#  nothing in the game ever draws in it: change the hardware colour behind
#  it and only the sky moves. The ground is a stack of bands built from the
#  pens that are already loaded, so a theme is a handful of bytes rather
#  than a second set of tiles.
#
#  Each theme: sky pen (a PEN_ index, whose HARDWARE colour is overridden),
#  the hardware colour to put there, and the strata as (scanlines, pen)
#  from the grass line down. The strata must add up to SCREEN_LINES minus
#  GROUND_Y, and assert_strata says so if they do not.
# ===========================================================================
GROUND_BANDS = SCREEN_LINES_TOTAL = 200

#  THE SKY MUST BE A COLOUR NO PEN IS USING. Pen 0 is only the sky, but
#  the sixteen hardware colours behind the other fifteen pens belong to
#  the art — set the sky to HW_ORANGE and every wooden thing in the game
#  is the same colour as the sky behind it, which is what the first cut of
#  this did. The six below are drawn from the eleven CPC colours the
#  palette does not otherwise load.
THEMES = [
    # name      sky hardware colour     strata: (lines, pen) top to bottom
    ('day',     'HW_SKY_BLUE',       [(4, 6), (4, 7), (10, 4), (2, 11),
                                      (6, 4), (2, 11), (4, 4)]),
    ('dawn',    'HW_PASTEL_MAGENTA', [(4, 6), (4, 7), (10, 13), (2, 4),
                                      (6, 13), (2, 4), (4, 13)]),
    ('dusk',    'HW_MAUVE',          [(4, 7), (4, 11), (8, 11), (2, 4),
                                      (8, 11), (2, 4), (4, 11)]),
    #  HW_CYAN is (0,128,128) — the darkest colour the palette is not
    #  already using. HW_PURPLE was tried and it is (255,0,128): a hot
    #  magenta, which is a great many things but is not night.
    ('night',   'HW_CYAN',           [(4, 7), (4, 11), (10, 11), (2, 1),
                                      (6, 11), (2, 1), (4, 11)]),
    ('snow',    'HW_PASTEL_CYAN',    [(6, 2), (4, 14), (8, 2), (2, 10),
                                      (6, 14), (2, 10), (4, 2)]),
    ('desert',  'HW_YELLOW',         [(4, 13), (4, 4), (10, 13), (2, 4),
                                      (6, 13), (2, 4), (4, 13)]),
]
THEME_NAMES = [t[0] for t in THEMES]

# ---------------------------------------------------------------------------
#  ...and what stands about in it.
#
#  Scenery draws BEHIND the blocks, so it may go where the forts go — a
#  rock at the far right reads as an outcrop behind the annexe rather than
#  as something in the way. The two patches of BARE ground are narrow,
#  though: x 40..80 between the slingshot and the outbuilding, and
#  x 208..240 between the main fort and the annexe. Both are 32 px, which
#  is one cell, so a tree or a bush fits there and the 64-px-wide rock does
#  not — it goes at the edge of the world instead.
#
#  Per theme: the clouds, what stands in each of the two gaps, and whether
#  there is an outcrop. `None` means nothing goes there, which is how the
#  desert gets no trees and the night sky gets almost no cloud.
# ---------------------------------------------------------------------------
DECOR = {
    #           clouds: (kind, x, y)              left      right     far
    'day':    ([('cloud_a', 16, 10), ('cloud_a', 188, 26)],
               'tree_a', 'bush_a', None),
    'dawn':   ([('cloud_b', 120, 14)],
               'tree_b', 'bush_b', 'boulder'),
    'dusk':   ([('cloud_b', 24, 30), ('cloud_b', 180, 40)],
               'tree_a', 'tree_a', None),
    'night':  ([('cloud_b', 96, 8)],
               'tree_b', 'tree_b', 'rock'),
    'snow':   ([('cloud_a', 8, 34), ('cloud_a', 176, 20)],
               'tree_b', 'tree_b', None),
    'desert': ([('cloud_b', 140, 12)],
               'bush_b', 'bush_a', 'rock'),
}

GAP_LEFT, GAP_RIGHT, FAR_EDGE = 44, 208, 256


def assert_strata():
    want = SCREEN_LINES_TOTAL - GROUND_Y
    for name, _sky, bands in THEMES:
        got = sum(n for n, _p in bands)
        if got != want:
            raise SystemExit('theme %r: strata are %d lines, the ground is %d'
                             % (name, got, want))


assert_strata()

#  There is one material now, so `set` is a constant and the tiering that
#  used to walk from the flimsiest to the toughest is gone with it. What
#  makes a late level hard is how the fort is BUILT, not what it is made
#  of. The field stays in the file format: it costs one byte and it is the
#  hook a second material would hang on.
BIRD_NAMES = [b[0] for b in BIRDS]
PIG_NAMES = [p[0] for p in PIGS]


# ===========================================================================
#  The default fifty.
#
#  Complexity GROWS with the level number; it does not cycle. The old
#  generator picked a shape with (n-1) % 8, so the eighth fort and the
#  sixteenth were built identically and only the material told them apart —
#  and once there is one material, nothing did. Here `grade` climbs from 0
#  to 7 across the fifty and decides how MUCH is built: how many
#  structures, how tall the tallest, whether there is a charge buried in
#  it, whether the base is stone. `shape` still rotates, but it only
#  decides WHICH shapes, for variety within a grade.
#
#  The world is 32 columns. The sling stands at column 2, so the forts
#  live in three zones that never overlap:
#
#      cols  8..14   the outbuilding
#      cols 15..22   the main fort
#      cols 24..30   the annex
# ===========================================================================
#  ONE EMPTY COLUMN BETWEEN THE ZONES, and it is not decoration. A run of
#  identical floor cells in the same row merges into one rigid beam
#  whatever built them — so an outbuilding seven cells wide starting at 8
#  reached column 14, the main fort's floor started at 15, and the two
#  merged into a single beam whose ends were over thin air. Three forts
#  came down at load because of it. The outbuilding starts at 7 now.
ZONE_OUT, ZONE_MAIN, ZONE_ANNEX = 7, 15, 24
ZONE_GAP = 22           # nothing is ever built here, so a stray pig can go
                        # in it without knocking a leg out from under a
                        # structure — see the "pigs win" rule below


def s_tower(col, floors, piece_wall='v', piece_floor='h'):
    """A hollow tower `floors` high and four cells wide, braced across the
    middle of every storey above the first. The bracing is what turns it
    from a stack of independent floors into something that has to be
    brought down rather than nibbled at."""
    out = []
    for f in range(floors):
        base = GRID_H - 1 - f * 3
        out.append((piece_wall, col, base))
        out.append((piece_wall, col + 3, base))
        out.append((piece_wall, col, base - 1))
        out.append((piece_wall, col + 3, base - 1))
        if f:
            out.append((piece_wall, col + 1, base - 1))
        for dx in range(4):
            out.append((piece_floor, col + dx, base - 2))
    return out


def s_hut(col):
    """Two uprights, a lintel and a pitched roof — the classic pig house.
    The two middle ground cells are left hollow: that is where the pig
    lives, and a pig needs two clear cells."""
    return [('i', col, GRID_H - 1), ('i', col + 3, GRID_H - 1),
            ('i', col, GRID_H - 2), ('i', col + 3, GRID_H - 2),
            ('h', col, GRID_H - 3), ('h', col + 1, GRID_H - 3),
            ('h', col + 2, GRID_H - 3), ('h', col + 3, GRID_H - 3),
            ('/', col + 1, GRID_H - 4), ('\\', col + 2, GRID_H - 4)]


def s_pyramid(col, size):
    out = []
    for r in range(size):
        for dx in range(size - r):
            out.append(('c' if r == 0 else 'b', col + r + dx,
                        GRID_H - 1 - r))
    return out


def s_bridge(col, span):
    out = [('i', col, GRID_H - 1), ('i', col + span + 1, GRID_H - 1),
           ('i', col, GRID_H - 2), ('i', col + span + 1, GRID_H - 2)]
    for dx in range(span + 2):
        out.append(('s', col + dx, GRID_H - 3))
    return out


def s_manor(col):
    """Two bays under one roof. Three posts carry a first floor, two more
    carry the loft, and the roof sits on top of that — five cells wide and
    six tall, so a shot into the ground floor brings the whole thing down
    rather than knocking a hole in it."""
    out = []
    for dx in (0, 2, 4):
        out += [('i', col + dx, GRID_H - 1), ('i', col + dx, GRID_H - 2)]
    out += [('h', col + dx, GRID_H - 3) for dx in range(5)]
    out += [('i', col + 1, GRID_H - 4), ('i', col + 3, GRID_H - 4)]
    #  The loft floor ends ON its two posts. A beam is judged at its ENDS,
    #  so a floor that overhangs both of them is a free fall — and the
    #  manor stood there leaning before the player had taken a shot.
    out += [('h', col + dx, GRID_H - 5) for dx in range(1, 4)]
    out += [('/', col + 1, GRID_H - 6), ('\\', col + 3, GRID_H - 6)]
    return out


def s_gatehouse(col):
    """Twin brick towers with a walkway between them. The two cells of the
    gateway are left empty on purpose: that is where a pig stands, under
    everything, which is the shot worth finding."""
    out = []
    for dx in (0, 5):
        out += [('b', col + dx, GRID_H - 1), ('b', col + dx, GRID_H - 2),
                ('b', col + dx, GRID_H - 3)]
    out += [('h', col + dx, GRID_H - 4) for dx in range(6)]
    out += [('c', col + 1, GRID_H - 5), ('c', col + 4, GRID_H - 5)]
    out += [('a', col + 2, GRID_H - 5), ('a', col + 3, GRID_H - 5)]
    return out


def s_keep(col):
    """A little castle: an arched gateway at the bottom, a floor over that,
    an upper chamber, and crenellations."""
    return [('b', col, GRID_H - 1), ('b', col, GRID_H - 2),
            ('b', col + 3, GRID_H - 1), ('b', col + 3, GRID_H - 2),
            ('h', col, GRID_H - 3), ('h', col + 1, GRID_H - 3),
            ('h', col + 2, GRID_H - 3), ('h', col + 3, GRID_H - 3),
            ('i', col, GRID_H - 4), ('i', col + 3, GRID_H - 4),
            ('a', col + 1, GRID_H - 4), ('a', col + 2, GRID_H - 4),
            ('h', col, GRID_H - 5), ('h', col + 1, GRID_H - 5),
            ('h', col + 2, GRID_H - 5), ('h', col + 3, GRID_H - 5),
            ('c', col, GRID_H - 6), ('c', col + 2, GRID_H - 6)]


def s_derrick(col):
    """A mast, a pulley at the top of it, and a dressed stone hanging on a
    rope with NOTHING UNDER IT — held up by the rope and by nothing else.
    The pig stands in the empty two cells below.

    Nothing in this engine swings, so it is not a crane. It does not have
    to be: the rope snaps for almost nothing, the load is the heaviest
    piece in the game, and the moment the rope goes the load is in free
    fall onto whatever is beneath it."""
    return [('i', col, GRID_H - 1), ('i', col, GRID_H - 2),
            ('i', col, GRID_H - 3), ('i', col, GRID_H - 4),
            ('i', col, GRID_H - 5), ('i', col, GRID_H - 6),
            ('o', col + 1, GRID_H - 6),
            ('|', col + 1, GRID_H - 5), ('|', col + 1, GRID_H - 4),
            ('S', col + 1, GRID_H - 3)]


def s_citadel(col):
    """The biggest thing the generator builds: a stone base, two storeys of
    timber over it, a glazed upper chamber and a rope walk across the top.
    Seven wide and seven tall, which is most of a screen."""
    out = []
    for dx in (0, 6):
        out += [('S', col + dx, GRID_H - 1), ('S', col + dx, GRID_H - 2)]
    out += [('i', col + 3, GRID_H - 1), ('i', col + 3, GRID_H - 2)]
    out += [('h', col + dx, GRID_H - 3) for dx in range(7)]
    out += [('i', col + 1, GRID_H - 4), ('i', col + 5, GRID_H - 4)]
    out += [('g', col + 3, GRID_H - 4)]
    out += [('h', col + dx, GRID_H - 5) for dx in range(1, 6)]
    out += [('a', col + 2, GRID_H - 6), ('a', col + 4, GRID_H - 6)]
    #  The rope walk ends ON the two arches, not past them. A beam is
    #  judged at its ENDS: overhang both and it is a free fall, and the
    #  walk collapsed into a tangle before the player had taken a shot.
    out += [('-', col + dx, GRID_H - 7) for dx in range(2, 5)]
    return out


def s_deadfall(col):
    """Two posts, a ROPE strung between them, and two dressed stones
    sitting on the rope. The pig stands underneath.

    This is what a rope is for in a grid engine. It has almost no hit
    points, a horizontal run merges into one rigid beam, and the heaviest
    piece in the game is resting on it — so the shot is not "knock the
    building over", it is "cut that one cell", and the building does the
    rest."""
    return [('i', col, GRID_H - 1), ('i', col, GRID_H - 2),
            ('i', col + 3, GRID_H - 1), ('i', col + 3, GRID_H - 2),
            ('i', col, GRID_H - 3), ('i', col + 3, GRID_H - 3),
            ('i', col, GRID_H - 4), ('i', col + 3, GRID_H - 4),
            #  STRUNG BETWEEN the posts, not resting on them: each end of
            #  the rope is butted against a post, which is what ties it.
            #  Knock either post out and the whole rope comes down at once,
            #  because a rope has no stiffness to pivot on.
            ('-', col + 1, GRID_H - 4), ('-', col + 2, GRID_H - 4),
            ('S', col + 1, GRID_H - 5), ('S', col + 2, GRID_H - 5)]


def top_of(blocks, c0, c1):
    """The row ABOVE the highest cell between columns c0 and c1, or the
    ground if there is nothing there. This is how a structure gets built
    on the roof of another one: the grid is sixteen rows and almost every
    fort in this game has sat in the bottom five of them."""
    rows = [r for _ch, c, r in blocks if c0 <= c <= c1]
    return (min(rows) - 1) if rows else GRID_H - 1


def s_nest(col, base):
    """A crow's nest: two posts, a floor and a rail, standing on whatever
    is underneath. Three wide so it fits on any roof, and the two cells
    between the posts are left open because that is where the pig sits."""
    return [('i', col, base), ('i', col + 2, base),
            ('h', col, base - 1), ('h', col + 1, base - 1),
            ('h', col + 2, base - 1),
            ('x', col + 1, base - 2)]


def s_watchtower(col, base, storeys):
    """A tower built upward from `base`. Every floor ends ON its posts — a
    floor that overhangs is a free fall, which is the rule that has caught
    more of these than any other.

    The storeys are NOT identical. Five copies of the same three rows read
    as scaffolding rather than as a building, which is what the first cut
    of this looked like: a brick ground floor, timber above it, an arch
    where a pig can stand, windows only on the upper floors, and a pitched
    roof to stop it. Four storeys is the cap for the same reason — past
    that it is a ladder however it is dressed."""
    storeys = max(1, min(4, storeys))
    out = []
    for f in range(storeys):
        b = base - f * 3
        wall = 'b' if f == 0 else 'v'            # brick foundation, timber up
        out += [(wall, col, b), (wall, col + 3, b),
                (wall, col, b - 1), (wall, col + 3, b - 1)]
        out += [('h', col + dx, b - 2) for dx in range(4)]
        if f == 0 and storeys > 1:
            out += [('a', col + 1, b), ('a', col + 2, b)]   # a way in
        elif f:
            out += [('g', col + 1, b - 1)]                  # a window
            if f == 2:
                out += [('x', col + 2, b - 1)]              # ...and a crate
    top = base - storeys * 3 + 1
    if storeys > 1:                              # a roof, so it ends
        out += [('/', col + 1, top - 1), ('\\', col + 2, top - 1)]
    return out


#  ---------------------------------------------------------------------
#  Five more, so that the eight-shape rotation is not the whole of the
#  variety. Each was designed against the support rules and then put
#  through check_standing before it was let in — the argument for why a
#  fort stands up is not the same thing as it standing up.
#  ---------------------------------------------------------------------
def s_granary(col):
    r"""A grain store held clear of the ground on four upright planks —
    floor, walls and roof standing on the legs and on nothing else.

        . / \ .        the rafters
        c h h c        the loft, boarded across
        h h h h        the floor, ENDING on its posts
        v . . v        the legs...
        v . . v        ...and the doorway between them

    This is the lesson the first fort has to teach: HIT THE LEG. Six of
    the ten objects are up in the body, where a bird that lands on them
    knocks a hole and stops. All six are carried by four uprights, and a
    'v' topples. Take out a ground post and the post above it has nothing
    underneath, which leaves the floor held at ONE end — and a beam held
    at one end tips. The store comes off its legs in one piece.

    Four wide, five tall, ten objects. The floor stops dead on the posts:
    overhang them and it is a free fall before the player has taken a
    shot, which is the mistake s_manor and s_citadel were each built with
    once. The two middle cells of the bottom two rows are the doorway,
    and that is where the pig stands."""
    out = [('v', col, GRID_H - 1), ('v', col + 3, GRID_H - 1),
           ('v', col, GRID_H - 2), ('v', col + 3, GRID_H - 2)]
    out += [('h', col + dx, GRID_H - 3) for dx in range(4)]
    #  The loft: two offcut shoulders with boarding between them, and the
    #  boarding is what the rafters sit on. That short beam ends on the
    #  floor below at both of its ends, so it is held at both.
    out += [('c', col, GRID_H - 4), ('c', col + 3, GRID_H - 4)]
    out += [('h', col + dx, GRID_H - 4) for dx in (1, 2)]
    out += [('/', col + 1, GRID_H - 5), ('\\', col + 2, GRID_H - 5)]
    return out


def s_storehouse(col):
    r"""A store: two thick walls, a roof over them, and CRATES for feet.

        . / . \ .      the rafters
        h h h h h      the roof plate
        c . . . c      offcut walls, forty-five points apiece
        c . . x c      ...and the goods stacked inside
        x . . x x      THE CRATES, carrying the lot

    The lesson is that a wall is only as strong as its worst cell. The
    fort reads as solid — five cells of plate on two stacks of offcut —
    but the whole of it stands on two crates, eighteen points each, at
    bird height and in the open. A shot that would bounce off an offcut
    goes clean through a crate; the wall above it then has nothing
    underneath, and the plate is left held at one end.

    The two crates on the floor hold nothing up. They are there because a
    store has crates in it, and because a bird that rolls in through the
    doorway should find something it can break — the same lesson, given
    away for free.

    Five wide, five tall, eleven objects."""
    out = []
    for dx in (0, 4):
        out += [('x', col + dx, GRID_H - 1), ('c', col + dx, GRID_H - 2),
                ('c', col + dx, GRID_H - 3)]
    #  The plate ends ON the walls, and five cells of it merge to ONE
    #  object — the roof is the cheapest part of the building.
    out += [('h', col + dx, GRID_H - 4) for dx in range(5)]
    out += [('/', col + 1, GRID_H - 5), ('\\', col + 3, GRID_H - 5)]
    #  Loose goods: standing on the ground, holding nothing.
    out += [('x', col + 3, GRID_H - 1), ('x', col + 3, GRID_H - 2)]
    return out


def s_porch(col):
    r"""A gateway with a roof on it: two pillars, an offcut on each head
    to spring from, an arch thrown across, and the roof sitting on that.

        . / \ .        the rafters
        h h h h        the roof plate
        c a a c        THE ARCH, and the blocks it thrusts against
        i . . i        the pillars...
        i . . i        ...and the gateway, with the pig in it

    The lesson is that the pig is not the target. It stands under the
    arch with two cells of clear air over its head, and everything that
    lands on the roof stops at the roof: knock the rafters off and the
    pig is still down there in the same doorway, entirely unbothered.

    What has to come down is the ARCH — and an arch is held by nothing
    underneath it. The two arch cells are WEDGED, each between its
    neighbour and the offcut on a pillar head, which is how an arch
    stands in the first place. Take a pillar out and there is nothing
    left to thrust against: the arch drops into the gateway with the
    plate and both rafters still on top of it, which is the whole upper
    half of the fort arriving in the cell the pig is standing in. A
    pillar is twenty-eight points, the slenderest upright in the game,
    and it topples.

    Four wide, five tall, eleven objects."""
    out = [('i', col, GRID_H - 1), ('i', col + 3, GRID_H - 1),
           ('i', col, GRID_H - 2), ('i', col + 3, GRID_H - 2)]
    #  c-a-a-c, the spelling s_gatehouse already uses — but with the two
    #  cells UNDER the arch left empty, which is the whole point of it.
    out += [('c', col, GRID_H - 3), ('c', col + 3, GRID_H - 3)]
    out += [('a', col + 1, GRID_H - 3), ('a', col + 2, GRID_H - 3)]
    out += [('h', col + dx, GRID_H - 4) for dx in range(4)]
    out += [('/', col + 1, GRID_H - 5), ('\\', col + 2, GRID_H - 5)]
    return out


def s_belfry(col):
    """NINE ROWS. More than half of this tower stands above the line every
    other fort in the game stops at, and it is five cells wide, so it is a
    spike rather than a block.

    A bell tower. The ringing chamber at the bottom, a shaft over it, and
    an open gallery at the top with a rope strung between two pillars and
    a dressed stone hanging off the rope with NOTHING UNDER IT for two
    rows. That is the deadfall idea stood on end and finally given
    somewhere to fall to — s_deadfall drops its stones one row onto a pig;
    this drops ninety hit points through three floors' worth of tower.

    THREE ANSWERS, ONE PER STOREY, at wildly different prices:

      the rope, 8 hp    cut it and the bell falls two rows onto a SHELF,
                        which has twenty. The shelf snaps, the two posts
                        standing on it lose their base, and the entire
                        top half of the tower follows the bell down into
                        the chamber the pigs are in.
      the glass, 6 hp   that shelf ENDS ON the two panes. Break one and
                        the shelf is held at one end only, so it tips over
                        the other — and the tower tips with it.
      the charge, 10 hp it is not buried. It IS the left wall cell of the
                        ground storey, at the height of a flat shot, and
                        the chamber floor's left end rests on it. Two
                        cells of blast takes the stone foot beneath it and
                        that floor above it, which is the storey the whole
                        tower is standing on.

    The rope is TIED AT BOTH ENDS: each end is butted against a pillar,
    which is what ties it, and it correctly has nothing whatever
    underneath it. check_standing skips ropes for exactly this reason.
    Everything else is judged the ordinary way and every floor ends on its
    posts.
    """
    out = []
    #  The ringing chamber. The CHARGE does a wall's work here, which is
    #  why it costs no extra object and why hitting it costs the storey.
    out += [('S', col, GRID_H - 1), ('S', col + 4, GRID_H - 1)]
    out += [('T', col, GRID_H - 2), ('b', col + 4, GRID_H - 2)]
    out += [('h', col + dx, GRID_H - 3) for dx in range(5)]
    #  THE WINDOWS, carrying the shelf above them.
    out += [('g', col, GRID_H - 4), ('g', col + 4, GRID_H - 4)]
    #  A SHELF, not a plank: twenty hit points is what the bell lands on.
    out += [('s', col + dx, GRID_H - 5) for dx in range(5)]
    #  The shaft the bell falls down — two rows of nothing, on purpose.
    out += [('v', col, GRID_H - 6), ('v', col + 4, GRID_H - 6)]
    out += [('v', col, GRID_H - 7), ('v', col + 4, GRID_H - 7)]
    out += [('S', col + 2, GRID_H - 7)]
    #  The gallery: two pillars with the rope strung between them, and the
    #  bell hanging from the middle of it.
    out += [('i', col, GRID_H - 8), ('i', col + 4, GRID_H - 8)]
    out += [('-', col + dx, GRID_H - 8) for dx in range(1, 4)]
    out += [('h', col + dx, GRID_H - 9) for dx in range(5)]
    return out


def s_barbican(col):
    """A gate tower: SEVEN WIDE, EIGHT TALL, three storeys, and the whole
    of the answer is one pane of glass on the middle one.

    The gate passage is dressed stone — ninety hit points a cell, four of
    them, with a pillar down the middle so it is two narrow bays and not
    one seven-cell hall. Nobody is coming in at the ground. The magazine
    on the top storey is easy to lob into, but taking it only takes the
    top storey off, and the pigs are not up there.

    THE MIDDLE STOREY IS THE LEVEL. Its guard room is walled in brick, and
    THE BRICK IS SITTING ON GLASS: six hit points, on the outside face,
    with clear air in front of it. A flat shot at GRID_H-4 breaks the
    pane, the brick above drops, the upper floor is left held at ONE END
    and tips over that end, and the top storey — pillars, magazine, deck
    and all — goes over with it. The charge tumbles on the way down and
    two cells of blast finishes whatever is still standing.

    One bird, six hit points, through a window. The alternative is three
    hundred and eight hit points of stone and pillar at the bottom, which
    is exactly the choice this fort exists to offer.

    Seven-cell floors are ONE OBJECT each — MAX_BEAM is eight — so the
    widest structure in this tier is also nearly the cheapest, and both
    floors end on their piers.
    """
    out = []
    #  The gate passage: two stone piers and a pillar down the middle, so
    #  a bird that rolls in finds two narrow bays rather than a hall.
    for dy in (1, 2):
        out += [('S', col, GRID_H - dy), ('i', col + 3, GRID_H - dy),
                ('S', col + 6, GRID_H - dy)]
    #  The passage ceiling, ending on the piers.
    out += [('h', col + dx, GRID_H - 3) for dx in range(7)]
    #  THE WINDOWS. Six hit points, on the outside face, and carrying the
    #  brick that carries the upper floor. This is the shot.
    out += [('g', col, GRID_H - 4), ('g', col + 6, GRID_H - 4)]
    out += [('b', col, GRID_H - 5), ('b', col + 6, GRID_H - 5)]
    out += [('h', col + dx, GRID_H - 6) for dx in range(7)]
    #  The magazine: a charge standing on the upper floor, under the deck.
    #  Two cells of blast either way takes the floor it stands on and the
    #  deck over it — the whole top storey, from the inside.
    out += [('i', col, GRID_H - 7), ('T', col + 3, GRID_H - 7),
            ('i', col + 6, GRID_H - 7)]
    #  A shelf, not a plank: the watch deck a pig stands on is the
    #  flimsiest floor in the fort, and it is the highest.
    out += [('s', col + dx, GRID_H - 8) for dx in range(7)]
    return out


def s_stack(col, n, ch='x'):
    return [(ch, col, GRID_H - 1 - i) for i in range(n)]


#  The eight shapes, in the order the rotation meets them. Each takes a
#  column and the grade; the ones that can grow, grow with it.
#  TWELVE shapes now, not eight, so the rotation takes twelve forts to
#  come round instead of eight — and each entry grows with the grade, so
#  meeting a shape a second time is not meeting the same building.
SHAPES = [
    lambda col, g: s_hut(col) + (s_nest(col, GRID_H - 5) if g >= 3 else []),
    lambda col, g: s_bridge(col, 3 + g // 3),
    lambda col, g: s_granary(col) if g < 5 else s_belfry(col),
    lambda col, g: s_watchtower(col, GRID_H - 1, 1 + (g + 2) // 3),
    lambda col, g: s_gatehouse(col) + (s_nest(col + 1, GRID_H - 6)
                                       if g >= 4 else []),
    lambda col, g: s_storehouse(col) if g < 4 else s_barbican(col),
    lambda col, g: s_manor(col) + (s_nest(col + 1, GRID_H - 7)
                                   if 2 <= g <= 6 else []),
    lambda col, g: s_citadel(col) if g >= 4 else s_keep(col),
    lambda col, g: s_porch(col) + (s_nest(col, GRID_H - 6) if g >= 5 else []),
    lambda col, g: s_pyramid(col, 3 + g // 3),
    lambda col, g: s_belfry(col) if g >= 3 else s_porch(col),
    lambda col, g: s_keep(col) + (s_watchtower(col, GRID_H - 7, g // 3)
                                  if g >= 3 else []),
]
SHAPE_COUNT = len(SHAPES)


def clamp4(x, lo, hi):
    """Scenery x must be a multiple of four: the column renderer works in
    4-pixel columns and compile_level refuses anything else."""
    return max(lo, min(hi, x)) // 4 * 4


def place(blocks, ch, col, row):
    """Add a piece, but NEVER INTO A BEAM.

    A floor is a merged beam judged at its two ends. Drop a pane of glass
    into the middle of one and it becomes two beams that each overhang
    their posts, and a beam held at one end tips — so the "weak point"
    brought the building down before the player had taken a shot. That is
    exactly what happened to the outbuilding on levels 26, 34, 42 and 50.

    If the target cell belongs to a beam the piece goes ON TOP of it
    instead, where it is one cell resting on a floor and breaks nothing.
    """
    occ = {(x, y): c for c, x, y in blocks}
    for _ in range(3):
        if occ.get((col, row)) not in BEAM_CH:
            blocks.append((ch, col, row))
            return
        row -= 1
        if row < 0:
            return


def default_level(n):
    """n is 1..LEVELS."""
    #  TWELVE grades, not eight, and the FIRST one is not empty. Level one
    #  used to be a four-cell hut with a single pig in it, which reads as
    #  an unfinished game rather than as a gentle one; it is a hut and a
    #  shed and two pigs now, still one or two shots to solve.
    grade = (n - 1) * 12 // LEVELS      # 0..11: how much gets built
    shape = (n - 1) % SHAPE_COUNT       # ...and which shapes, for variety

    #  The sky, the ground and what stands about in it change every few
    #  forts, so the run does not look like one long afternoon. Seven is
    #  coprime with six, so the cycle does not line up with the eight-shape
    #  rotation and no two neighbouring forts share a look.
    theme = THEME_NAMES[(n // 7) % len(THEME_NAMES)]

    blocks, pigs = [], []

    #  Two structures from the very first fort, three from grade three,
    #  and from grade seven something built on the ROOF of the main one —
    #  which is where the height is. Almost every fort in this game used to
    #  sit in the bottom five of sixteen rows.
    #  THE LAST FORTS ARE THE BIGGEST ONES, and not whatever the rotation
    #  happened to land on. Left to the rotation the fiftieth came out
    #  lighter than the forty-sixth, which is the wrong shape for the end
    #  of a game: the three tallest structures take it in turn instead.
    main = shape
    if grade >= 10:
        main = (7, 5, 10)[n % 3]        # citadel, barbican, belfry
    blocks += SHAPES[main](ZONE_MAIN, grade)
    pigs += [('p', ZONE_MAIN + 1, GRID_H - 1)]

    blocks += SHAPES[(shape + 5) % SHAPE_COUNT](ZONE_OUT, max(0, grade - 3))
    pigs += [('p', ZONE_OUT + 1, GRID_H - 1)]

    if 3 <= grade < 10:
        annex, pcol = ((s_derrick, 3), (s_deadfall, 1),
                       (s_hut, 1))[shape % 3]
        blocks += annex(ZONE_ANNEX)
        pigs += [('p', ZONE_ANNEX + pcol, GRID_H - 1)]

    if grade >= 7:
        top = top_of(blocks, ZONE_MAIN, ZONE_MAIN + 3)
        if top >= 2:
            blocks += s_nest(ZONE_MAIN + 1, top)
            pigs += [('P', ZONE_MAIN + 2, top - 1)]

    #  ...and at the very end the annexe stops being a shed and becomes a
    #  third fort in its own right. A nest on a nest on a nest is height
    #  without variety — the outbuilding came out a fifteen-row ladder of
    #  the same three cells — so this adds a different SHAPE instead.
    if grade >= 10:
        blocks += SHAPES[(shape + 8) % SHAPE_COUNT](ZONE_ANNEX, grade - 7)
        pigs += [('p', ZONE_ANNEX + 2, GRID_H - 1)]

    #  A CHARGE, buried where it will take the fort with it. From grade 2:
    #  a player who has not yet worked out what a fort does should not be
    #  handed the answer on level two. A second one later, and a third at
    #  the very end.
    if grade >= 2:
        place(blocks, 'T', ZONE_MAIN + 2, GRID_H - 1)
    if grade >= 6:
        place(blocks, 'T', ZONE_OUT + 2, GRID_H - 2)
    if grade >= 11:
        place(blocks, 'T', ZONE_ANNEX + 1, GRID_H - 3)

    #  Glass is a weak point on purpose — the cell worth aiming at. Stone
    #  is the opposite, and it goes at the foot of the main fort where it
    #  stops the cheap ground-floor shot working for ever.
    if grade >= 2:
        place(blocks, 'g', ZONE_MAIN + 4, GRID_H - 2)
    if grade >= 5:
        place(blocks, 'g', ZONE_OUT + 3, GRID_H - 4)
    if grade >= 4:
        place(blocks, 'S', ZONE_MAIN - 1, GRID_H - 1)
        place(blocks, 'S', ZONE_MAIN - 1, GRID_H - 2)
    if grade >= 8:
        place(blocks, 'S', ZONE_MAIN + 5, GRID_H - 1)
        place(blocks, 'S', ZONE_MAIN + 5, GRID_H - 2)
        place(blocks, 'S', ZONE_OUT - 1, GRID_H - 1)

    #  The pigs the fort is FOR. Armour and a crown arrive with the grade,
    #  and the late ones stand on TOP of things rather than under them,
    #  which is a different shot.
    if grade >= 2:
        pigs += [('P', ZONE_MAIN + 2, GRID_H - 4)]
    if grade >= 5:
        pigs += [('p', ZONE_OUT + 2, GRID_H - 4)]
    if grade >= 6:
        pigs += [('K', ZONE_MAIN + 1, GRID_H - 7)]
    if grade >= 9:
        pigs += [('P', ZONE_GAP, GRID_H - 1)]

    #  A cell holds one thing, and it used to be the PIG that won it: the
    #  block was deleted and the pig stayed. That is how levels 13, 21, 29
    #  and 37 killed their own pigs before the player had taken a shot —
    #  the deleted cell was part of a walkway, the beam it left behind was
    #  supported at one end only, and a beam supported at one end TIPS. It
    #  tipped straight onto the pig it had just made room for.
    #
    #  So MOVE THE PIG instead. A pig that lands in a fort's cell goes up
    #  on to the roof of its own column, where it is standing on the fort
    #  rather than inside it — which is a different shot to work out and
    #  costs the fort nothing.
    seen = {}
    for ch, cx, cy in blocks:
        if 0 <= cx < GRID_W and 0 <= cy < GRID_H:
            seen[(cx, cy)] = ch
    blocks = [(ch, cx, cy) for (cx, cy), ch in seen.items()]
    occupied = set(seen)

    def perch(col):
        """The row a pig's FEET take standing on top of this column."""
        here = [r for _c, r in occupied if _c == col]
        feet = (min(here) - 1) if here else GRID_H - 1
        return feet if feet >= 1 else None

    placed, taken = [], set()
    for ch, cx, cy in pigs:
        if not 0 < cx < GRID_W:
            continue
        cells = [(cx, cy), (cx, cy - 1)]        # a pig is two cells tall
        if any(c in occupied or c in taken for c in cells):
            r = perch(cx)
            if r is None:
                continue
            cells = [(cx, r), (cx, r - 1)]
            if any(c in occupied or c in taken for c in cells):
                continue
            cy = r
        taken.update(cells)
        placed.append((ch, cx, cy))
    pigs = placed[:MAX_PIGS]

    #  A fort that overflows the block table would be silently truncated at
    #  load, which looks like a level designed wrong rather than one built
    #  wrong. Trim from the top down, where a missing cell costs least —
    #  and SAY SO, because a roof that quietly went missing is exactly the
    #  failure this trimming exists to prevent.
    def objects(bs):
        return len(merge_beams(bs, '<generated>'))
    if objects(blocks) > MAX_BLOCKS:
        blocks.sort(key=lambda b: -b[2])
        dropped = 0
        while objects(blocks) > MAX_BLOCKS:
            blocks.pop()
            dropped += 1
        print('  level %02d: dropped %d cells from the top to fit %d objects'
              % (n, dropped, MAX_BLOCKS))

    # birds: more of them, and a wider cast, as the forts get harder
    n_birds = min(MAX_BIRDS, 3 + n // 8)
    cast = BIRD_NAMES[:min(len(BIRD_NAMES), 2 + n // 7)]
    birds = [cast[i % len(cast)] for i in range(n_birds)]

    #  The decoration follows the theme. Cloud positions drift with the
    #  fort number so that two forts sharing a theme are not the same
    #  picture — a multiple of four, because the renderer works in
    #  4-pixel columns and the compiler refuses anything else.
    clouds, left, right, far = DECOR[theme]
    scenery = []
    for i, (kind, x, y) in enumerate(clouds):
        drift = ((n * 12 + i * 40) % 48) - 24
        scenery.append((kind, clamp4(x + drift, 0, WORLD_PX - 64), y))
    if left:
        scenery.append((left, GAP_LEFT,
                        GROUND_Y - (128 if left.startswith('tree') else 64)))
    if right:
        scenery.append((right, GAP_RIGHT,
                        GROUND_Y - (128 if right.startswith('tree') else 64)))
    if far:
        scenery.append((far, FAR_EDGE, GROUND_Y - 64))

    return dict(name='FORT %02d' % n, set=SET_NAMES[0], theme=theme,
                sling=24, birds=birds,
                scenery=scenery, blocks=blocks, pigs=pigs)


# ===========================================================================
#  Text form
# ===========================================================================
def to_text(lv):
    grid = [['.'] * GRID_W for _ in range(GRID_H)]
    for ch, col, row in lv['blocks']:
        grid[row][col] = ch
    for ch, col, row in lv['pigs']:
        grid[row][col] = ch
    scol = lv['sling'] // CELL
    if 0 <= scol < GRID_W:
        grid[GRID_H - 1][scol] = SLING_CH

    top = 0
    while top < GRID_H - 1 and all(c == '.' for c in grid[top]):
        top += 1

    out = []
    out.append('# %s — edit freely, then run make.' % lv['name'])
    out.append('# grid is %dx%d cells of %d px; the last map line sits on '
               'the ground.' % (GRID_W, GRID_H, CELL))
    out.append('name    %s' % lv['name'])
    out.append('set     %s' % lv['set'])
    out.append('theme   %s' % lv['theme'])
    out.append('sling   %d' % lv['sling'])
    out.append('birds   %s' % ' '.join(lv['birds']))
    out.append('scenery %s' % ' ; '.join('%s %d %d' % s for s in lv['scenery']))
    out.append('map')
    for r in range(top, GRID_H):
        out.append(''.join(grid[r]))
    return '\n'.join(out) + '\n'


def from_text(path):
    lv = dict(name='', set='wood', theme=THEME_NAMES[0], sling=24,
              birds=[], scenery=[], blocks=[], pigs=[])
    maplines = []
    in_map = False
    for lineno, raw in enumerate(open(path), 1):
        line = raw.rstrip('\n')
        if in_map:
            if not line.strip() or line.lstrip().startswith('#'):
                continue
            maplines.append(line)
            continue
        s = line.strip()
        if not s or s.startswith('#'):
            continue
        parts = s.split(None, 1)
        key = parts[0].lower()
        val = parts[1].strip() if len(parts) > 1 else ''
        if key == 'map':
            in_map = True
        elif key == 'name':
            lv['name'] = val.upper()
        elif key == 'set':
            if val not in SET_NAMES:
                die(path, lineno, 'unknown block set %r (have: %s)'
                    % (val, ', '.join(SET_NAMES)))
            lv['set'] = val
        elif key == 'theme':
            if val not in THEME_NAMES:
                die(path, lineno, 'unknown theme %r (have: %s)'
                    % (val, ', '.join(THEME_NAMES)))
            lv['theme'] = val
        elif key == 'sling':
            lv['sling'] = int(val)
        elif key == 'birds':
            for b in val.split():
                if b not in BIRD_NAMES:
                    die(path, lineno, 'unknown bird %r (have: %s)'
                        % (b, ', '.join(BIRD_NAMES)))
                lv['birds'].append(b)
        elif key == 'scenery':
            for item in val.split(';'):
                item = item.split()
                if not item:
                    continue
                if len(item) != 3:
                    die(path, lineno, 'scenery wants "name x y", got %r'
                        % ' '.join(item))
                nm, x, y = item[0], int(item[1]), int(item[2])
                if nm not in SCENERY_OBJECTS:
                    die(path, lineno, 'unknown scenery %r (have: %s)'
                        % (nm, ', '.join(sorted(SCENERY_OBJECTS))))
                lv['scenery'].append((nm, x, y))
        else:
            die(path, lineno, 'unknown key %r' % key)

    if not maplines:
        die(path, 0, 'no map')
    if len(maplines) > GRID_H:
        die(path, 0, 'map has %d lines, at most %d fit above the ground'
            % (len(maplines), GRID_H))
    base = GRID_H - len(maplines)            # the map hangs from the ground
    for r, line in enumerate(maplines):
        if len(line) > GRID_W:
            die(path, 0, 'map line %d is %d cells wide, the world is %d'
                % (r + 1, len(line), GRID_W))
        for col, ch in enumerate(line):
            row = base + r
            if ch in '. ':
                continue
            elif ch in PIECE_CH:
                lv['blocks'].append((ch, col, row))
            elif ch in PIG_CH:
                lv['pigs'].append((ch, col, row))
            elif ch == SLING_CH:
                lv['sling'] = col * CELL + CELL // 2
            else:
                die(path, 0, 'map line %d column %d: %r is not a piece'
                    % (r + 1, col + 1, ch))
    return lv


def merge_beams(blocks, path):
    """Runs of identical plank cells in the same row become ONE beam.

    The map file still writes `hhhh`, because that is the readable way to
    draw a lintel; the engine gets a single four-cell object, because that
    is the only way it can fall like one."""
    out, byrow = [], {}
    for ch, col, row in blocks:
        if ch in BEAM_CH:
            byrow.setdefault((row, ch), []).append(col)
        else:
            out.append((ch, col, row, 1))
    for (row, ch), cols in byrow.items():
        cols.sort()
        run = [cols[0]]
        for c in cols[1:]:
            if c == run[-1] + 1 and len(run) < MAX_BEAM:
                run.append(c)
            else:
                out.append((ch, run[0], row, len(run)))
                run = [c]
        out.append((ch, run[0], row, len(run)))
    out.sort(key=lambda b: (b[2], b[1]))
    return out


def check_standing(lv, name):
    """Warn about anything that will move before the player has taken a shot.

    This is the engine's own support rule, written out in Python: a merged
    beam is judged at its ENDS, and a beam held at exactly one end TIPS
    over that end. A fort that tips at level load looks like a level
    designed wrong rather than one built wrong, and it is how levels 13,
    21, 29 and 37 killed their own pigs before the first bird flew.

    It is deliberately not exhaustive — it does not model wedging, ropes or
    the sub-cell fall — but it catches the one failure that has actually
    happened, twice, and it costs nothing to run on every build.
    """
    beams = merge_beams(lv['blocks'], name)
    occ = {(c, r) for _ch, c, r, ln in beams for c in range(c, c + ln)}
    occ |= {(c, r) for _ch, c, r in lv['pigs']}
    bad = []
    for ch, col, row, ln in beams:
        #  Rope is not judged this way — it is tied at its ends, to the
        #  cell above, beside or under each of them, so a rope strung
        #  between two posts correctly has nothing whatever underneath it.
        if ln < 2 or row >= GRID_H - 1 or ch in ROPE_CH:
            continue
        lo = (col, row + 1) in occ
        hi = (col + ln - 1, row + 1) in occ
        if lo != hi:
            bad.append('%r at %d,%d (%d wide) is held at one end only'
                       % (ch, col, row, ln))
        elif not lo and not any((c, row + 1) in occ
                                for c in range(col, col + ln)):
            bad.append('%r at %d,%d (%d wide) has nothing under it'
                       % (ch, col, row, ln))
    for msg in bad:
        print('  %s: %s' % (name, msg))
    return len(bad)


def die(path, lineno, msg):
    where = '%s:%d' % (path, lineno) if lineno else path
    raise SystemExit('%s: %s' % (where, msg))


# ---------------------------------------------------------------------------
#  Scenery objects are named per OBJECT in the level file (a tree, not a
#  tree-half); the compiler expands one into its cells.
# ---------------------------------------------------------------------------
def _cell(name):
    return SCENERY_CELLS.index(name)


SCENERY_OBJECTS = {
    #  name    : list of (cell, dx, dy) making up the whole thing
    'tree_a':   [('tree_a_top', 0, 0), ('tree_a_bot', 0, 64)],
    'tree_b':   [('tree_b_top', 0, 0), ('tree_b_bot', 0, 64)],
    'bush_a':   [('bush_a', 0, 0)],
    'bush_b':   [('bush_b', 0, 0)],
    'cloud_a':  [('cloud_a_l', 0, 0), ('cloud_a_r', 32, 0)],
    'cloud_b':  [('cloud_b_l', 0, 0), ('cloud_b_r', 32, 0)],
    'rock':     [('rock_l', 0, 0), ('rock_r', 32, 0)],
    'boulder':  [('boul_l', 0, 0), ('boul_r', 32, 0)],
    'sling':    [('sling_back', 0, 0)],
}


# ===========================================================================
#  Binary form
#
#    0    block set
#    1    theme        sky colour and ground strata
#    2    slingshot x, in pixels / 2   (0..159 covers the 320 px world)
#    3    bird count      4..9  bird types
#    10   scenery cell count
#    11   block count
#    12   pig count
#    13.. scenery cells: cell id, x/2, y      (3 bytes each)
#    ..   blocks: piece | col<<4, row         (2 bytes each)
#    ..   pigs:   type  | col<<4, row         (2 bytes each)
#
#  Everything is byte-addressed and unpacked straight into the live tables
#  at level start; nothing here needs arithmetic beyond a shift.
# ===========================================================================
def compile_level(lv, path):
    if len(lv['birds']) > MAX_BIRDS:
        die(path, 0, '%d birds, at most %d fit' % (len(lv['birds']), MAX_BIRDS))
    if not lv['birds']:
        die(path, 0, 'no birds — the level is unplayable')
    if len(lv['pigs']) > MAX_PIGS:
        die(path, 0, '%d pigs, at most %d fit' % (len(lv['pigs']), MAX_PIGS))
    if not lv['pigs']:
        die(path, 0, 'no pigs — the level can never be won')
    if len(merge_beams(lv['blocks'], path)) > MAX_BLOCKS:
        die(path, 0, '%d pieces after merging planks into beams, at most %d '
            'fit' % (len(merge_beams(lv['blocks'], path)), MAX_BLOCKS))

    occupied = set()
    for ch, col, row in lv['blocks'] + lv['pigs']:
        if not (0 <= col < GRID_W and 0 <= row < GRID_H):
            die(path, 0, '%r is off the grid at column %d row %d'
                % (ch, col, row))
        if (col, row) in occupied:
            die(path, 0, 'two things share column %d row %d' % (col, row))
        occupied.add((col, row))
    for ch, col, row in lv['pigs']:
        if row == 0:
            die(path, 0, 'pig at column %d is against the sky — a pig is two '
                'cells tall and needs the cell above it' % col)
        if (col, row - 1) in occupied:
            die(path, 0, 'pig at column %d row %d has no headroom: a pig is '
                'two cells tall' % (col, row))

    cells = []
    for nm, x, y in lv['scenery']:
        for cellname, dx, dy in SCENERY_OBJECTS[nm]:
            cells.append((_cell(cellname), x + dx, y + dy))
    if len(cells) > MAX_LEVEL_SCENERY:
        die(path, 0, '%d scenery cells, at most %d fit (a tree or a cloud '
            'is two)' % (len(cells), MAX_LEVEL_SCENERY))
    for cid, x, y in cells:
        if x % 4:
            die(path, 0, 'scenery x must be a multiple of 4 (the renderer '
                'works in 4-pixel columns); got %d' % x)
        if not (0 <= x <= WORLD_PX - 32 and 0 <= y <= 255 - 64):
            die(path, 0, 'scenery cell %d is off the world at (%d,%d)'
                % (cid, x, y))

    beams = merge_beams(lv['blocks'], path)

    out = bytearray()
    out.append(SET_NAMES.index(lv['set']))
    out.append(THEME_NAMES.index(lv['theme']))
    out.append(lv['sling'] // 2)
    out.append(len(lv['birds']))
    for i in range(MAX_BIRDS):
        out.append(BIRD_NAMES.index(lv['birds'][i])
                   if i < len(lv['birds']) else 0)
    out.append(len(cells))
    out.append(len(beams))
    out.append(len(lv['pigs']))
    for cid, x, y in cells:
        out += bytes((cid, x // 4, y))
    for ch, col, row, ln in beams:
        out += bytes((PIECE_CH[ch] | (col << 4) & 0xF0,
                      row | (col & 0x10) | ((ln - 1) << 5)))
    for ch, col, row in lv['pigs']:
        out += bytes((PIG_CH[ch] | (col << 4) & 0xF0, row | (col & 0x10)))
    return bytes(out)


# `col` is 0..19, which does not fit the 4 bits above. Store the low nibble
# in byte 0 and the fifth bit in byte 1's bit 4 — the unpacker reassembles
# it with one rotate. Guard the assumption here rather than in Z80.
assert GRID_W <= 32 and GRID_H <= 16


def main(argv):
    if '--export' in argv:
        force = '--force' in argv
        os.makedirs(DIR, exist_ok=True)
        kept = 0
        for n in range(1, LEVELS + 1):
            path = '%s/level%02d.txt' % (DIR, n)
            if os.path.exists(path) and not force:
                kept += 1
                continue
            open(path, 'w').write(to_text(default_level(n)))
        print('%s: %d levels written, %d kept%s'
              % (DIR, LEVELS - kept, kept,
                 '' if force else ' (--force overwrites your edits)'))
        return

    os.makedirs(BUILD, exist_ok=True)
    recs, moving = [], 0
    for n in range(1, LEVELS + 1):
        path = '%s/level%02d.txt' % (DIR, n)
        if not os.path.exists(path):
            raise SystemExit('%s is missing — run `make levels-export`' % path)
        lv = from_text(path)
        moving += check_standing(lv, 'level%02d' % n)
        recs.append(compile_level(lv, path))
    if moving:
        print('  %d structure(s) will move before the first shot' % moving)

    data, offs = bytearray(), []
    for r in recs:
        offs.append(len(data))
        data += r
    open(os.path.join(BUILD, 'levels.raw'), 'wb').write(bytes(data))
    with open(os.path.join(BUILD, 'level_defs.inc'), 'w') as f:
        f.write('; AUTO-GENERATED by tools/levels.py — do not edit\n')
        f.write('; equates only: hardware.inc is built on top of these, so\n')
        f.write('; this file is included BEFORE the org.\n')
        for k, v in (('LEVEL_COUNT', LEVELS), ('GRID_W', GRID_W),
                     ('GRID_H', GRID_H), ('CELL_PX', CELL),
                     ('GROUND_Y', GROUND_Y), ('GRID_TOP_Y', TOP_Y),
                     ('WORLD_PX', WORLD_PX), ('MAX_BIRDS', MAX_BIRDS),
                     ('MAX_PIGS', MAX_PIGS), ('MAX_BLOCKS', MAX_BLOCKS),
                     ('MAX_SCENERY', MAX_SCENERY),
                     ('LEVEL_DATA_SIZE', len(data))):
            f.write('%-16s equ %d\n' % (k, v))
    with open(os.path.join(BUILD, 'level_tables.inc'), 'w') as f:
        f.write('; AUTO-GENERATED by tools/levels.py — do not edit\n')
        f.write('level_ofs:\n')
        for i in range(0, LEVELS, 8):
            f.write('        dw      %s\n'
                    % ','.join(str(v) for v in offs[i:i + 8]))
        #  One sky colour and one stack of ground bands per theme. The
        #  strata run (lines, art byte) with a zero terminator, which is
        #  the format scene_init already reads.
        f.write('\ntheme_sky:              ; hardware ink for PEN 0\n')
        f.write('        db      %s\n'
                % ','.join(t[1] for t in THEMES))
        f.write('\ntheme_ofs:              ; ...and where its strata start\n')
        off, bodies = 0, []
        offsets = []
        for name, _sky, bands in THEMES:
            offsets.append(off)
            body = ''.join('        db      %d,#%X%X   ; %s\n'
                           % (n, pen, pen, name) for n, pen in bands)
            body += '        db      0\n'
            bodies.append(body)
            off += len(bands) * 2 + 1
        f.write('        db      %s\n'
                % ','.join(str(v) for v in offsets))
        f.write('\ntheme_strata:\n')
        for body in bodies:
            f.write(body)
        f.write('\nTHEME_COUNT      equ %d\n' % len(THEMES))
    print('levels.raw     %6d bytes  (%d levels, largest %d)'
          % (len(data), LEVELS, max(len(r) for r in recs)))


if __name__ == '__main__':
    main(sys.argv)
