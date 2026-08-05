#!/usr/bin/env python3
# ============================================================================
#  levels.py — the forty forts, as text you can edit.
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

LEVELS = 40
GRID_W, GRID_H = 20, 10
CELL = 16                       # pixels per grid cell, both ways
GROUND_Y = 168                  # world y of the top of the turf
TOP_Y = GROUND_Y - GRID_H * CELL        # y of grid row 0 == 8
WORLD_PX = GRID_W * CELL        # 320
MAX_BIRDS = 6
MAX_PIGS = 8
MAX_BLOCKS = 48        # six sets of block art pushed the state block up
MAX_SCENERY = 12       # 10 for the level, 2 reserved for the slingshot
MAX_LEVEL_SCENERY = 10

DIR = 'assets/levels'
BUILD = 'build'

PIECE_CH = {'h': 0, 'v': 1, 'c': 2, 'b': 3, '/': 4,
            '\\': 5, 'a': 6, 'i': 7, 's': 8, 'x': 9}

#  Pieces that are PLANKS: a run of them side by side is one rigid beam,
#  not a row of independent cubes. That is what lets a lintel tip over the
#  pillar it still has instead of dissolving into its cells.
BEAM_CH = set('hs')
MAX_BEAM = 8            # the length field is three bits
CH_PIECE = {v: k for k, v in PIECE_CH.items()}
PIG_CH = {'p': 0, 'P': 1, 'K': 2}
CH_PIG = {v: k for k, v in PIG_CH.items()}
SLING_CH = 'Y'

SET_NAMES = [s[0] for s in BLOCK_SETS]

#  The tiers run from the flimsiest material to the toughest, so a fort
#  gets harder to knock down as well as more elaborate. The order is
#  derived from the sets' own toughness rather than written out, so adding
#  a material drops it into the right place by itself.
SET_ORDER = [i for i, _ in sorted(enumerate(BLOCK_SETS),
                                  key=lambda e: e[1][1])]
BIRD_NAMES = [b[0] for b in BIRDS]
PIG_NAMES = [p[0] for p in PIGS]


# ===========================================================================
#  The default forty. Each is a couple of structures on the right-hand
#  side of the world, with the slingshot on the left; they get taller,
#  wider and better defended as the numbers go up.
# ===========================================================================
def s_tower(col, floors, piece_wall='v', piece_floor='h'):
    """A hollow tower `floors` high, two cells wide."""
    out = []
    for f in range(floors):
        base = GRID_H - 1 - f * 3
        out.append((piece_wall, col, base))
        out.append((piece_wall, col + 3, base))
        out.append((piece_wall, col, base - 1))
        out.append((piece_wall, col + 3, base - 1))
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


def s_keep(col):
    """A little castle: an arched gateway with a pig in it, brick walls
    either side, and a crenellated top."""
    return [('b', col, GRID_H - 1), ('b', col, GRID_H - 2),
            ('b', col + 3, GRID_H - 1), ('b', col + 3, GRID_H - 2),
            ('h', col, GRID_H - 3), ('h', col + 3, GRID_H - 3),
            ('a', col + 1, GRID_H - 3), ('a', col + 2, GRID_H - 3),
            ('c', col, GRID_H - 4), ('c', col + 2, GRID_H - 4)]


def s_stack(col, n):
    return [('x', col, GRID_H - 1 - i) for i in range(n)]


def default_level(n):
    """n is 1..40."""
    tier = (n - 1) * len(SET_ORDER) // LEVELS   # every material gets a turn
    step = (n - 1) % 8                          # ...and every fort shape too
    mset = SET_NAMES[SET_ORDER[tier]]

    blocks, pigs = [], []
    if step in (0, 1):
        blocks += s_hut(13)
        pigs.append(('p', 14, GRID_H - 1))
        if step == 1:
            blocks += s_stack(9, 2)
            pigs.append(('p', 10, GRID_H - 1))
    elif step in (2, 3):
        blocks += s_tower(13, 2)
        pigs.append(('p', 14, GRID_H - 1))
        pigs.append(('P' if step == 3 else 'p', 15, GRID_H - 4))
    elif step == 4:
        blocks += s_pyramid(12, 4)
        pigs.append(('p', 17, GRID_H - 1))
        pigs.append(('p', 10, GRID_H - 1))
    elif step == 5:
        blocks += s_bridge(11, 4)
        blocks += s_stack(18, 2)
        pigs.append(('p', 13, GRID_H - 1))
        pigs.append(('P', 15, GRID_H - 1))
    elif step == 6:
        blocks += s_keep(13)
        pigs.append(('P', 14, GRID_H - 1))
        pigs.append(('p', 18, GRID_H - 1))
    else:
        blocks += s_keep(14)
        blocks += s_hut(9)
        pigs.append(('K', 15, GRID_H - 1))
        pigs.append(('p', 10, GRID_H - 1))
        pigs.append(('P', 18, GRID_H - 1))

    # the deeper you get, the more it is worth reinforcing the ground floor
    if n > 12:
        blocks += [('c', 19, GRID_H - 1), ('c', 19, GRID_H - 2)]
    if n > 24:
        blocks += [('b', 8, GRID_H - 1), ('h', 8, GRID_H - 2)]

    # birds: more of them, and a wider cast, as the forts get harder
    n_birds = min(MAX_BIRDS, 3 + n // 10)
    cast = BIRD_NAMES[:min(len(BIRD_NAMES), 2 + n // 7)]
    birds = [cast[i % len(cast)] for i in range(n_birds)]

    scenery = [('cloud_a', 16, 10), ('cloud_b', 188, 26)]
    if n % 5:
        scenery.append(('tree_a' if n % 2 else 'tree_b', 248, GROUND_Y - 128))
    scenery.append(('bush_a' if n % 3 else 'bush_b', 88, GROUND_Y - 64))
    if n % 4 == 0:
        scenery.append(('rock' if n % 8 else 'boulder', 140, GROUND_Y - 64))

    return dict(name='FORT %02d' % n, set=mset, sling=24, birds=birds,
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
    out.append('sling   %d' % lv['sling'])
    out.append('birds   %s' % ' '.join(lv['birds']))
    out.append('scenery %s' % ' ; '.join('%s %d %d' % s for s in lv['scenery']))
    out.append('map')
    for r in range(top, GRID_H):
        out.append(''.join(grid[r]))
    return '\n'.join(out) + '\n'


def from_text(path):
    lv = dict(name='', set='wood', sling=24, birds=[], scenery=[],
              blocks=[], pigs=[])
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
#    1    slingshot x, in pixels / 2   (0..159 covers the 320 px world)
#    2    bird count      3..8  bird types
#    9    scenery cell count
#    10   block count
#    11   pig count
#    12.. scenery cells: cell id, x/2, y      (3 bytes each)
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
    recs = []
    for n in range(1, LEVELS + 1):
        path = '%s/level%02d.txt' % (DIR, n)
        if not os.path.exists(path):
            raise SystemExit('%s is missing — run `make levels-export`' % path)
        recs.append(compile_level(from_text(path), path))

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
    print('levels.raw     %6d bytes  (%d levels, largest %d)'
          % (len(data), LEVELS, max(len(r) for r in recs)))


if __name__ == '__main__':
    main(sys.argv)
