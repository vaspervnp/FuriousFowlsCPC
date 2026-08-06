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

Keep **wood**. Drop stone, ice, sand and metal.

Five sets of ten pieces is 6400 bytes of block art; one set is 1280, so
this frees 5120 bytes immediately below `STATE_BASE`. That is more room
than the code bank has ever had, and several things currently exiled to
low memory could come back.

The pieces themselves get thinner again — thinner than the current
`thin=True`, which already halves them.

Levels that name another set need rewriting to `wood`; `tools/levels.py`
picks the set per level from `BLOCK_SETS`, so with one entry it collapses
to a constant.

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
