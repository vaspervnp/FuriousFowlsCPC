# ============================================================================
#  sheetdefs.py — the shape of every spritesheet, in one place.
#
#  Both the exporter (mksheets.py, writes the editable PNGs) and the
#  importer (gen_art.py, reads them back into the build) work from these
#  tables, so a sheet can never drift out of agreement with the game.
#
#  Sizes are in MODE 0 PIXELS. A Mode 0 pixel is twice as wide as it is
#  tall on a real display, so a 16x32 cell shows up on screen as a square
#  and a 16x16 block as a wide brick — which is exactly what a plank of
#  masonry should look like.
# ============================================================================

# ---------------------------------------------------------------------------
#  CREATURES — 16x32, six birds and three pigs, SIX states each. One row of
#  the sheet is one creature; the six columns are, in order:
#
#    idle    at rest — the default pose
#    blink   the same pose with its eyes shut; the idle animation flicks
#            through this every couple of seconds, out of phase per bird
#    ready   bird: hauled back on the sling, straining and furious
#            pig:  it has seen what is coming, eyes wide
#    fly     bird: in flight, eyes screwed shut, wings swept back
#            pig:  laughing at you, because the shot missed
#    hurt    took a hit and is still standing — squashed, cross-eyed
#    dead    finished: birds flatten into a puddle, pigs pop
#
#  Frame order here IS the order in the sheet and the FR_* order in
#  src/hardware.inc.
# ---------------------------------------------------------------------------
CREATURE_FRAMES = ['idle', 'blink', 'ready', 'fly', 'hurt', 'dead']

BIRDS = [
    # name      body  belly  beak   brow   the six of them, by plumage
    ('red',     3,    13,    5,     1),
    ('yellow',  5,    13,    4,     1),
    ('blue',    9,    14,    5,     1),
    ('black',   1,    10,    5,     1),
    ('white',   2,    13,    4,     1),
    ('green',   6,     7,    5,     1),
]

PIGS = [
    # name      body  belly  snout  gear   gear = helmet / crown pen, 0 = none
    ('pig',     6,     7,    7,     0),
    ('helmet',  6,     7,    7,    10),
    ('king',    6,     7,    7,     5),
]

CREATURE_NAMES = [b[0] for b in BIRDS] + [p[0] for p in PIGS]
CREATURE_W, CREATURE_H = 16, 32
CREATURE_COUNT = len(CREATURE_NAMES) * len(CREATURE_FRAMES)
CREATURE_COLS = len(CREATURE_FRAMES)          # one creature per sheet row

BIRD_COUNT = len(BIRDS)
PIG_COUNT = len(PIGS)

# ---------------------------------------------------------------------------
#  BLOCKS — 16x16. Ten pieces, in FIVE material sets, so every level can
#  pick the look that suits it. The piece SHAPES are the same across sets;
#  only the material changes. Piece order IS the BLK_* order in
#  hardware.inc, and the per-piece hit points below are what the physics
#  engine uses (scaled by the set's toughness).
# ---------------------------------------------------------------------------
#  `tall` marks the UPRIGHTS. A piece standing on end does not just get
#  dislodged when something shoves it — it goes over, which is why they
#  have to be told apart from the things that merely sit there.
BLOCK_PIECES = [
    # name        hp   tall   what it is
    ('beam_h',    30,  False),  # 0  horizontal plank, floor and lintel
    ('beam_v',    30,  True),   # 1  vertical plank, the standard upright
    ('cube',      45,  False),  # 2  solid square, load bearing
    ('brick',     40,  False),  # 3  coursed brick, a heavier cube
    ('roof_l',    25,  False),  # 4  wedge rising to the right
    ('roof_r',    25,  False),  # 5  wedge rising to the left
    ('arch',      35,  False),  # 6  rounded top, doorways and windows
    ('pillar',    28,  True),   # 7  slender column with a cap and a base
    ('slab',      20,  False),  # 8  thin shelf, snaps easily
    ('crate',     18,  False),  # 9  hollow box — the weak point of a fort
]

# set name, toughness (percent of the base hp), the pens the drawing code
# paints with — (face, light edge, dark edge, detail) — and whether the
# whole set is drawn THIN.
BLOCK_SETS = [
    ('wood',   100, (4, 13, 11, 11), False),
    ('stone',  170, (10, 2, 1, 1),   False),
    ('ice',     60, (8, 2, 14, 14),  False),
    ('sand',    85, (13, 2, 4, 4),   False),
    ('metal',  220, (14, 2, 9, 9),   False),
    ('twig',    50, (4, 13, 11, 11), True),   # thin wood: light, and it
]                                             # goes over if you look at it

BLOCK_W, BLOCK_H = 16, 16
BLOCK_COUNT = len(BLOCK_SETS) * len(BLOCK_PIECES)
BLOCK_COLS = len(BLOCK_PIECES)                # one material set per sheet row

# ---------------------------------------------------------------------------
#  SCENERY — 32x64 cells. Big background furniture, assembled from cells:
#    a tree  is two cells stacked   -> 32x128
#    a cloud is two cells abreast   -> 64x64
#    a rock  is two cells abreast   -> 64x64
#    a bush  is one cell            -> 32x64
#  Cell order IS the SC_* order in hardware.inc.
# ---------------------------------------------------------------------------
#  The last two cells are the slingshot, which is scenery in every way
#  that matters — it is fixed, it is big, and the level file places it —
#  except that it is drawn in TWO passes: the fork behind the bird, and
#  the near prong over the top of it, so the bird really sits in the sling.
SCENERY_CELLS = [
    'tree_a_top', 'tree_a_bot',      # 0,1   oak: broad canopy
    'tree_b_top', 'tree_b_bot',      # 2,3   pine: narrow spire
    'bush_a', 'bush_b',              # 4,5   two shrubs
    'cloud_a_l', 'cloud_a_r',        # 6,7   fat cumulus
    'cloud_b_l', 'cloud_b_r',        # 8,9   thin streak
    'rock_l', 'rock_r',              # 10,11 boulder
    'sling_back', 'sling_front',     # 12,13 the slingshot, in two passes
]
SCENERY_W, SCENERY_H = 32, 64
SCENERY_COUNT = len(SCENERY_CELLS)
SCENERY_COLS = 4

# ---------------------------------------------------------------------------
#  Where each sheet lives, and how the build addresses it.
# ---------------------------------------------------------------------------
SHEETS = {
    'creatures': dict(path='assets/sheets/creatures.png',
                      w=CREATURE_W, h=CREATURE_H,
                      cols=CREATURE_COLS, count=CREATURE_COUNT),
    'blocks':    dict(path='assets/sheets/blocks.png',
                      w=BLOCK_W, h=BLOCK_H,
                      cols=BLOCK_COLS, count=BLOCK_COUNT),
    'scenery':   dict(path='assets/sheets/scenery.png',
                      w=SCENERY_W, h=SCENERY_H,
                      cols=SCENERY_COLS, count=SCENERY_COUNT),
}
