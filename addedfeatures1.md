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

**Status: done.** See the notes at the bottom.

The shape used to come from `step = (n-1) % 8`, so the eighth level and the
sixteenth were built the same way and only the material differed. The
complexity should **grow with n** instead of cycling.

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
and it is the hook a second material would hang on. All the level files
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

---

## Notes on the six new pieces

Asked for: rope (horizontal and vertical), a pulley, and whatever else
Angry Birds has that a level can use. Added six, and **that is the lot** —
the level format packs the piece into four bits, so sixteen is the ceiling
and we are now standing on it.

| piece | char | hp | what it does |
|---|---|---|---|
| `rope_h` | `-` | 8 | a run merges into ONE beam, so it snaps rather than fraying |
| `rope_v` | `|` | 8 | hangs; marked `tall`, so it goes over rather than sliding |
| `pulley` | `o` | 22 | a wheel on a bracket |
| `tnt` | `T` | 10 | **explodes** — see below |
| `glass` | `g` | 6 | the most fragile thing in the game: the cell worth aiming at |
| `stone` | `S` | 90 | the least: what stops the cheap ground-floor shot |

Losing the material sets in item 2 did not have to mean losing every
material. Glass and stone are PIECES now, so a level can put a pane and a
dressed block into a timber fort instead of being cast wholesale in one
substance — which is more useful than five sets ever were, and costs 100
bytes instead of 2000.

**Rope is honest about what it is.** Nothing in this engine swings, so a
rope is a beam with almost no hit points. What makes it worth having is
what you hang off it: `s_deadfall` is two posts, a rope between them and
two dressed stones sitting on the rope, with a pig underneath. The shot is
not "knock the building over", it is "cut that one cell".

### TNT

`tnt_blast` in `blocks.asm`. Everything within two cells takes 200 damage,
which is more than any piece can hold, and pigs in it die outright.

Two things had to be got right:

* **Throw, do not merely drop.** Nothing is ever removed from this engine.
  A piece knocked into `BS_FALL` that still has something under it falls
  zero cells and sits exactly where it was — so the first version dealt
  enormous damage and looked like it had done nothing at all. Each victim
  now gets `BLK_SHOVE` set away from the charge first, and *away* is what
  an explosion means.
* **A spent charge becomes a crate.** Same reason: the block is still
  there afterwards, and leaving it a charge means the next bird sets off
  the same explosion again. It is in `BS_FALL` when we change it, so the
  settle sweep redraws it that frame, and a crate is the same ten by ten
  footprint so nothing is left showing.

Chains work — a second charge inside the radius is still `BS_REST`, so it
goes off too. That is a recursive call on a machine with 128 bytes of
stack, so `TNT_CHAIN` bounds it at three: past that a charge merely falls,
and the player sees a chain that stops rather than a machine that does.

---

## Notes on 3, after doing it

`grade` climbs 0..7 across the fifty and decides **how much** is built;
`shape` still rotates 0..7 but only decides **which** shapes. So:

* grade 0 — one structure, one pig. Level one is a hut.
* grade 1 — an outbuilding as well
* grade 2 — a charge buried in the main fort, and an armoured pig above it
* grade 3 — a pane of glass where the fort is weakest
* grade 4 — a third structure: a derrick, a deadfall or a hut
* grade 5 — a second charge, and a king
* grade 6 — a stone footing, and the citadel appears
* grade 7 — all of it

The world is 32 columns and the forts now live in three zones that never
overlap: `8..14` the outbuilding, `15..22` the main fort, `24..30` the
annex. `ZONE_GAP` at column 22 is where a stray pig goes, because pigs win
the cell they stand in and a pig placed on a structure's leg is a
structure that falls over before the player has taken a shot.

`MAX_BLOCKS` is 64, up from 48. Ten-pixel cells need more of them.

**A beam is judged at its ENDS, and two structures had forgotten that.**
The manor's loft floor and the citadel's upper floor both spanned the full
width of the building while their posts were set in one cell from either
side — overhang both ends and the beam is a free fall, so both buildings
were leaning before the player had taken a shot. Both floors now end ON
their posts. The citadel's rope walk had the same fault and now ends on
the two arches.

**Scenery had to move.** Three zones of building leave only two gaps of
bare ground: x 40..80 and x 208..240. Both are 32 px, which is one cell,
so the 64-px rock and boulder go unused by the default fifty — still there
for a hand-built level with room for them.

### And a note on measuring, again

Two of the three hours here went into "the TNT does not explode". It did.
`tnt_depth` reached 2, so it had even chained. What had actually happened
is that my scripted shot was falling short of the fort, and then that the
blast was invisible for the reason above.

Worse: I wrote a watcher that ran the emulator in 120-tick slices instead
of whole raster slices, and it reported the blocks never moving in a frame
where the screenshot plainly shows them thrown across the screen. The
screenshots were right and the watcher was wrong. **That is the fifth
measurement tool in this project to blame the game for its own bug.** The
rule that keeps earning its keep: before believing a tool that says
"nothing happened", make it say "something happened" on a case where
something demonstrably did.

---

## Rope physics

A rope was a beam with almost no hit points. Now it is a rope.

**It carries tension and nothing else.** Everything else in this engine is
held from below; a rope is held by its anchors, whatever is under it hangs
FROM it, and it never tips — a rope has no stiffness to tip with, so it is
either taut or it is on the floor. `rope_v` lost its `tall` flag for the
same reason.

* `rope_v` — tied by the cell above, or standing on something that can
  take the weight.
* `rope_h` — BOTH ends have to be tied, to the cell above, beside or under
  each end, or the edge of the world. If either lets go the whole rope
  **drops**, it does not tip: one end of a plank letting go pivots on the
  other because a plank is rigid, and a rope is not.
* `bsup_hang` — a cell with a rope directly above it is held BY the rope,
  with nothing under it and nothing beside it. This is the whole point.

### Two circular supports, and what broke them

The rule "a rope may rest on what is below it" is needed, or a rope lying
on the ground falls zero cells, is judged unsupported next sweep, and
falls zero cells for ever. But it creates cycles:

1. **The rope rests on the load that is hanging from the rope.** Both float
   in mid-air propping each other up, and cutting the rope changes nothing.
   Broken by `BLK_HANG`: a block that got its support from ABOVE is marked,
   and `rope_hold` refuses to be held up by a marked block. The sweep runs
   bottom row first, so the cell below has already had its flag decided
   this frame.
2. **The top of a cut rope hangs from the cell above it, and the cell below
   hangs from the top.** Broken by `rope_tied`: an anchor that is itself
   falling is not an anchor.

Without the second, the cut rope sat in `BS_FALL` for ever and the settle
never ended. Without the first, the load never fell at all.

Verified by construction rather than by aim, which is the lesson from the
TNT: build the rig with its anchor MISSING and check that the load ends on
the ground, then build it with the anchor and check that nothing moves in
four hundred frames, then cut it with a bird and check the stone lands on
the pig. All three pass.

---

## Fifty levels, and forts that stop killing their own pigs

**Levels 13, 21, 29 and 37 lost a pig before the first bird flew.** The
cause was the rule that a pig WINS the cell it stands in: the block there
was deleted, the pig stayed. In those four the deleted cell was part of a
gatehouse walkway, so the beam left behind was supported at one end only —
and a beam supported at one end does not fall, it TIPS, straight onto the
pig it had just made room for.

**So move the pig, not the block.** A pig that lands in a fort's cell goes
up on to the roof of its own column, standing on the fort rather than
inside it. The fort loses nothing and the player gets a different shot to
work out.

**`check_standing` now runs on every build.** It is the engine's own
support rule written out in Python: a merged beam is judged at its ends,
and one held at exactly one end will tip at load. Deliberately not
exhaustive — it does not model wedging, ropes or the sub-cell fall — but
it catches the one failure that has now happened twice (the manor and
citadel overhangs, then these four), and it costs nothing. Ropes are
excluded: they are tied at their ends, so a rope strung between two posts
correctly has nothing whatever under it. All fifty forts are clean.

**LEVELS is 50.** That needed 900 more bytes of level record than the code
bank had, so the records moved out of it entirely:

| | was | now |
|---|---|---|
| code bank | #4000-#87FF, ending #83C6 | #4000-#87FF, ending **#7640** |
| block art | #8800 | #8800 |
| rot_map | #8C00 | #8B20 |
| level records | *inside the code bank* | **#8CC0-#A1FF** (5440 B) |
| game state | #9E00 | **#A200** |

The records are read-only and already part of the loaded image, so putting
them behind the tilt maps costs nothing and hands the code bank back a
fifth of itself. The state block moved up to make room; it is 6.5 KB and
there is still 1153 bytes between its end and video RAM, which the assert
at the foot of `state.inc` is watching.

---

## Score, high score on the disc, retries and difficulty

**The score is how hard the pigs were hit.** Every blow that lands on a
pig adds its own force, so a shot that catches three of them beats a shot
that flattens one — plus `BIRD_BONUS` (100) for every bird still in the
queue when a fort clears. Nothing is scored for damage to the fort: the
fort is the means, not the end, and paying for it rewarded knocking a wall
down and walking away from the pig behind it. Twenty-four bits, because
fifty forts does not fit in sixteen and a score that wraps is worse than
no score.

**The strip had to be compacted.** 160 pixels at six per glyph is
twenty-six of them, and LEVEL / BIRDS / PIGS used all but three. It reads
`LV01 BD3 PG2 SC000450` now.

**A bug worth naming**: `ui_num6` used `B` as both the pen and the `djnz`
counter, so the six digits came out in pens 6,5,4,3,2,1 — and pen 1 is
BLACK on a black strip, so the score silently lost its units column. It
looked like clipping and it was a register.

**And another**: `ui_compose` fills `hud_buf` and nothing more; the strip
only reaches the screen through `ui_refresh` or the scroll seam. Both
banner paths ended in `jp ui_compose`, so OUT OF BIRDS was composed and
never blitted — invisible since the day it was written. FORT DOWN! got
away with it only because a dying pig raises `ui_dirty` on its own.

### The high score, on the floppy

`src/disk.asm` is CreepersCPC's uPD765 driver, lifted whole. It is not
worth re-deriving: every warning in its header is a bug that once cost
somebody a working disc image. It talks to the controller through
`#FB7E`/`#FB7F` with both ROMs paged out and interrupts off — no AMSDOS,
no firmware — writes track 0 sector `#C5`, and only trusts a save after
reading it back and comparing. `SCORES.BIN` is imported onto the DSK
FIRST so that its data block lands on that sector; it is never opened at
runtime.

The payload is the high score and the difficulty, adjacent in RAM on
purpose so both go out in one `ldir`. The write happens at the menu and
nowhere else: spinning the motor stops the machine for about a second,
which is unnoticeable at a menu and unforgivable mid-shot.

**`cpcshot.py` now emulates the controller** — the four commands the
driver sends, one sector, read from and written back to the DSK on disc.
Without it the driver is untestable: every wait times out, the game boots
six seconds late, and a save can never be proved to have happened. With
it, "seed the sector, play, ESC to the menu, read the sector" is a
four-line test, and it is what proved the round trip: `disc: hi=276
writes=1`.

**And RASM only writes symbols for LABELS.** Every address in `state.inc`
is an equate, so the headless tools had to derive the layout by
arithmetic — and were wrong twice, which is what made one watcher report
that blocks never moved in a frame where the screenshot showed them
thrown across the screen. `main.asm` now emits `sym_*` labels for the
addresses the tools ask about, so they cannot drift again.

### Retries and difficulty

Five goes at a fort used to be unlimited goes. Now the count is the
difficulty, chosen with DOWN at the menu: **Easy 5, Medium 3, Hard 2**.
Run out and it is GAME OVER — written big and two-tone across the middle
of the screen, the same lettering as the title, with SPACE to go back to
the menu. The camera snaps to the sling first, both because `title_text`
keeps its x in a single byte and because the fort that beat you is worth
looking at from the place you were throwing at it.

---

## Big lettering, at both ends of a level

The title's two-tone lettering does duty over the playfield now. `big_line`
takes a string and a position and lays one line of it down; everything
below is a caller.

* **LEVEL nn / START**, two seconds before play begins. `GS_INTRO` holds
  it while the fort settles underneath — which is exactly where a fort
  built leaning wants to do its settling.
* **VICTORY** when the last pig goes.
* **NICE TRY / NO GAME / NO DICE / OINK OINK** when the birds run out and
  there is still a go left, chosen off the frame counter.
* **GAME OVER** when there is not.

Widths at `TB_SCALE_BIG`: a glyph is 15 pixels of ink on an 18 pixel
pitch, so a line of n glyphs is 18n-3 and the 160-pixel window holds nine
of them and not one more. OINK OINK is exactly nine — 159 pixels, starting
at x 0, with a single pixel to spare. The x that centres each length is
worked out once in the comment above `big_line` rather than guessed at
every call.

**All four banners snap the camera to the sling first.** `title_text`
keeps its x in a single byte, so the lettering can only be laid down with
the camera at the left of the world — and the drift that used to happen
during a banner had to go with it, or the lettering scrolled out from
under itself.

**The intro erases with a box, not a repaint.** The lettering covers about
a fifth of the screen and `world_repaint` is the whole of it: four times
the work to undo a quarter of the damage.

That box takes the AIM DOTS with it, and they are not part of any sprite's
backing store — so `gu_intro` forgets them (`dot_n = 0`) before asking for
a redraw. Restoring the table instead would have painted five stale pixels
over freshly rebuilt scenery.
