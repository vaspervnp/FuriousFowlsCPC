# Added features, round 1

Four changes, to be done **in order**, each checked before the next starts.

---

## 0. Narrow the display to 39 characters

Set CRTC R1 to 39 instead of 40, the way CreepersCPC does.

The 6845 advances each character row's start by R1, so **R1 is the ring
row stride**. Changing it changes the world-to-ring mapping with it:
`40*row + x` becomes `39*row + x`, and every place that assumed a
40-character row — `world_to_screen`, `gen_line_lut`, the HUD stride,
`CAM_MAX` — has to follow.

The visible playfield becomes 156 pixels wide instead of 160.

**Status: done.** See the notes at the bottom for what it did and did not
fix.

---

## 1. Sprites at two thirds of their present size

**Status: done.** See the notes at the bottom.

Creatures were 16x32 and blocks 16x16. Two thirds is 11x21 and 11x11, which
is awkward on a Mode 0 pixel (two pixels to the byte, so widths want to be
even), so the scale used is **five eighths** — the even fraction nearest two
thirds.

Touches `tools/sheetdefs.py`, every draw routine in `tools/mksheets.py`,
the blitter's row width, and the grid geometry in `tools/levels.py` —
`CELL_PX` is 16 today and the whole collapse model is built on it.

---

## 2. One material only, and thinner

**Status: done.** See the notes at the bottom.

Keep **wood**. Drop stone, ice, sand and metal. The pieces get thinner
again — thinner than the old `thin=True`, which already halved them.

---

## 3. Forts that get more complex every level

Today the shape comes from `step = (n-1) % 8`, so the eighth level and
the sixteenth are built the same way and only the material differs. The
complexity should **grow with n** instead of cycling: more structures,
more storeys, more interlocking, all the way to level forty.

`MAX_BLOCKS` is 48 and the grid is 20x10, so there is a ceiling; the
generator already trims from the top down when a fort overflows, and that
trimming should stay honest rather than silently dropping the roof.

---

## Notes on 0, after doing it

Done, and the screen is correct at 39 columns: R1, `SCREEN_BYTES_PER_LINE`,
`world_to_screen`'s row stride (x80 became x80 minus 2r, which is x78) and
`CAM_MAX` all follow `VIEW_CHARS` now, and the playfield is 156 px wide.

**It did not fix the seam, and by the arithmetic it cannot.** A ring cell
is `R1*row + x`. Two world columns share a cell when they differ by R1,
one row apart — and the window is exactly R1 wide, so column `x` and
column `x+R1` are never both visible but their rows both are. Writing the
incoming off-screen column therefore always writes over a visible column
one row up, whatever R1 is. Measured stray cells mid-scroll: 69 at forty
columns, 95 at thirty-nine.

Two of my own tools were wrong along the way and both blamed the game:
`cpcshot.py` hard-coded 40 columns and decoded the screen into diagonal
stairs; the residue oracle hard-coded the state addresses, which all moved
sixteen bytes down when `HUD_SIZE` shrank with the stride. Both now read
R1 and compute the layout.

The 39-column change is therefore **a cost with no measured benefit** —
four pixels of width — unless it is wanted for something else. The seam
is still mitigated only by timing: the column is drawn in raster slice 2,
after the beam has passed those cells, and the flip lands on the next
VSYNC.

---

## Notes on 1, after doing it

**Five eighths, not two thirds.** Creatures 16x32 -> **10x20**, blocks
16x16 -> **10x10**, `CELL_PX` 16 -> **10**. Two thirds would have been 11
wide, and a Mode 0 byte holds two pixels, so every odd width costs a shift
per row in the blitter for ever.

**The world did not shrink; the grid got finer.** 20x10 cells of 16 px
became **32x16 cells of 10 px** — 320 px across and 160 px tall either
way, so the ground stays at 168 and the same forts have twice the cells to
be built from. That is most of item 3 handed over for free.

**The art is redrawn by reduction, not by hand.** `mksheets.py` still
draws on its old 16x32 and 16x16 canvases and each finished cell goes
through a new `reduce_cell`: every destination pixel takes the commonest
pen in the source area it covers, and ANY ink beats the background. At this
size that is the difference between an eye and a smudge. Creature art fell
from 13824 bytes to **5400**, block art from 6400 to **2500**.

**Ten is not a power of two, and that is where the work was.** Every
cell-to-pixel conversion in the engine was a run of four `add hl,hl`, and
every pixel-to-cell one a run of four `srl`. They are now three routines in
`blocks.asm`:

  * `cell_pix` — cell -> its first pixel, x10 as 4n+n doubled
  * `pix_cell` — pixel -> its cell, /10 as halve then `(x*205)>>10`, no loop
  * `cell_cols` — cell -> the char columns it covers, which is no longer a
    constant: ten pixels is two and a half characters, so a cell spans
    three or four depending on which cell it is

Call sites fixed: `block_y`, `block_bbox`, the tile walk in `block_draw`,
`pig_y`, `pig_draw`, `pdr_test`, `pig_erase`, and the grid probe in
`shot_collide`.

**Two art strides stopped being shifts and silently drew nothing.**
`block_art_base` and `bt_tilted` both multiplied the piece index by 128
with `ld b,7 / add hl,hl`. A piece is fifty bytes now, so every fort in the
game indexed past its own art and the forts rendered as empty sky — pigs
drew, blocks did not. Both go through `rb_mul` (x50) like `rot_build`
already did. `grid_at` and `art_for_creature` had been converted earlier.

**Physics constants that were really sprite constants:** `BIRD_R` 11 -> 7,
`SHOT_CY` 19 -> 12, and the two "half a bird" offsets in `shot_aim_pos`
are now `CR_WIDTH/2` and `CR_HEIGHT/2` so they can never drift again.
`SHOT_BACK_SIZE` was `9*CR_HEIGHT` for an eight-byte sprite; it is now
`(CR_BYTES_PER_ROW+1)*CR_HEIGHT`. `GRAVITY` is unchanged — it was tuned to
the 320 px world, which did not move.

**The level files had to be re-exported**, since a map is 32 columns wide
now and the old ones were 20. `python3 tools/levels.py --export --force`.

**Scenery was left at 32x64 on purpose.** It is scaled to the world, not
to a creature: a tree three times a pig's height is right, and the
slingshot's whole geometry (`SLING_*`, the fork tips, the pouch) is tuned
to that cell. Say the word if it should come down with the rest.

Verified headless: title screen, fort rendering, a full shot from the pull
through the flight to a hit that collapsed the left stack and killed a pig
(`PIGS 2` -> `PIGS 1`), the camera follow, and the bird coming to rest on
the grass. Code ends at #7F5E.

---

## Notes on 2, after doing it

**The pieces were being drawn wrong, and item 1 is what broke them.**
`draw_block` took its canvas size from `BLOCK_W`/`BLOCK_H` but every
coordinate in it was written for sixteen — `8 - hy`, `ellipse(c, 7.5, ..)`,
`range(2, w - 2, 3)`. On a ten-wide cell that put the pillar hard against
the right edge, turned the arch into a broken hook and clipped the cube to
a bar. It was visible in the game and I had read past it twice.

Ten is not a size you reduce INTO, either: every feature here is one or
two pixels across and a majority vote on a two-pixel feature is a coin
toss. So the ten shapes are now **drawn by hand at 10x10** and
`reduce_cell` is out of the block path entirely. Creatures still go
through it, because a bird has enough pixels to survive a vote.

**What each piece is now**, all in timber and none of them filling its
cell except the brick:

| piece | what it is |
|---|---|
| `beam_h` | three rows: lit top, shadowed underside, sawn ends, grain |
| `beam_v` | the same on end, three columns, lit down the left |
| `cube` | a 6x6 sawn offcut |
| `brick` | the one solid piece — courses and staggered joints |
| `roof_l`/`roof_r` | a two-pixel rafter, not a wedge |
| `arch` | a lintel on two short legs, open underneath |
| `pillar` | a bare stick two pixels across, with knots |
| `slab` | a shelf two rows deep |
| `crate` | a hollow box with a diagonal brace |

Grain is only drawn where there is a face left to draw it on: a two-pixel
member is a lit edge and a shadow with nothing in between, and putting
specks on the shadow turned the pillar into a candy stripe.

**One set: 500 bytes of block art where five were 2500.** The 2000 bytes
went to the CODE bank, not to the space above it — `BLOCK_ART` moved from
`#8000` to `#8800` and `ROT_MAP_BASE` from `#9900` to `#8A00`, so the code
bank now runs to `#8800`. It ends at `#7F36`, which is 2250 bytes of
headroom where there were 162.

`SET_ORDER` and the material tiering are gone from `tools/levels.py` —
what makes a late level hard is how the fort is BUILT, not what it is
painted with. The `set` byte stays in the file format: it costs one byte
and it is the hook a second material would hang on. All forty level files
were re-exported to `set wood`.

**A bug found while checking, and fixed.** `repaint_window` runs at every
turn boundary and takes about a second, and `draw_world_column` painted
lines 0..199 — including char row 0, which is the status strip. So the
strip was visibly eaten away from the left, one column per frame, and
then laid back on at the end. It starts at `PLAY_TOP` now and never
touches it. (Panning to the far right still can: ring cell `40r + x`
means world column 64 and up at char row 24 wraps onto row 0. That is the
seam aliasing and no line window fixes it.)

I lost an hour to that one believing it was mine, because it appeared the
moment level one turned to wood. It was not: wood is tougher than ice, the
collapse took longer, and the screenshot landed in the middle of a sweep
that had always been there. Checking out the previous commit and changing
one word in one level file is what settled it — and that is the check to
run first next time, not last.
