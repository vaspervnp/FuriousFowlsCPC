# FURIOUS FOWLS

An Angry Birds for the **Amstrad CPC 464/6128**, written in Z80 assembly.
Mode 0 (160x200, 16 colours) over a 320 px world panned by CRTC hardware
scrolling; a slingshot, six birds, three kinds of pig, forty forts built
from ten piece shapes in five materials, and a collapse model that drops
the roof on whatever is underneath.

Boot `dist/fowls.dsk` in any CPC emulator (or on real hardware) and
`RUN"FOWLS"`.

| Key | Action |
|-----|--------|
| ↑ ↓ | raise / lower the aim |
| SPACE | hold to haul the sling back, release to launch |
| SPACE | (on a banner) continue |
| R | restart this fort |
| N | skip to the next fort |

The bird itself is the power gauge: winding up drags it back down the
launch line, so how far it has moved *is* how hard it will go.

## Building

```sh
make               # assemble + build dist/fowls.dsk
make asm           # assemble only
make sprites-export  # write assets/sheets/*.png so you can edit the art
make levels-export   # write assets/levels/*.txt so you can edit the forts
make run           # boot the DSK in RetroVirtualMachine
make clean
```

| Tool | Purpose | Tested |
|------|---------|--------|
| [RASM](https://github.com/EdouardBERGE/rasm) | Z80 assembler | v3.2.5 |
| [iDSK](https://github.com/cpcsdk/idsk) | DSK image tool | 0.20 |
| python3 | the art and level pipelines (no third-party modules) | 3.14 |

## Editing the art

Every pixel in the game is authored as a **spritesheet PNG** under
`assets/sheets/`, and those files are the source of truth — `make` reads
them back on every build.

```sh
make sprites-export          # writes any sheet that is missing
make sprites-export FORCE=1  # overwrite with the built-in defaults
```

Load `assets/sheets/fowls.gpl` in your editor (Aseprite, LibreSprite,
GIMP, Piskel — the PNG reader is deliberately forgiving) so the palette is
right. **Magenta is transparent.** Anything off-palette is a build error
naming the offending pixel, because a wrong pen is invisible until it is
on screen in the wrong colour.

| Sheet | Cells | Contents |
|-------|-------|----------|
| `creatures.png` | 54 of 16x32 | 6 birds + 3 pigs, one per row, **six states each** |
| `blocks.png` | 50 of 16x16 | 10 piece shapes x **5 material sets**, one set per row |
| `scenery.png` | 14 of 32x64 | trees, bushes, clouds, a boulder, the slingshot |

The six creature states, in sheet order, are `idle`, `blink`, `ready`,
`fly`, `hurt`, `dead`. A bird is *ready* when it is hauled back on the
sling and *flying* with its eyes screwed shut; a pig is *ready* when it
has seen what is coming and *flying* when it is laughing at you because
the shot missed. Pigs blink on their own clock, deliberately out of phase
with each other.

Scenery cells combine into objects: a tree is two cells stacked (32x128),
a cloud or a boulder is two side by side (64x64), a bush is one. The
slingshot is two cells — the fork, and the near prong that is drawn back
over the bird.

## Editing the levels

Forty forts live in `assets/levels/levelNN.txt` as editable text.

```sh
make levels-export           # writes any level file that is missing
make levels-export FORCE=1   # overwrite all forty with the defaults
```

```
name    FIRST PERCH
set     wood
sling   24
birds   red red yellow
scenery cloud_a 16 10 ; tree_a 248 40 ; bush_a 88 104
map
....................
..............//....
.............hhhh...
.............i.pi...
.............i..i...
```

The map is the fort on the game's 20x10 grid of 16x16 cells; the **last**
line rests on the ground, so a short map is fine.

```
.  empty     h beam_h   v beam_v   c cube    b brick
/  roof_l    \ roof_r   a arch     i pillar  s slab    x crate
p  pig       P helmet pig          K king pig
Y  the slingshot
```

A pig is two cells tall: the character marks its **feet** and the cell
above has to be clear. The compiler refuses a fort with a pig in a wall,
two pieces in one cell, a piece off the grid, or scenery off a 4-pixel
column, and tells you which line.

## Project layout

```
FuriousFowlsCPC/
├── Makefile
├── src/
│   ├── main.asm        entry, hardware takeover, frame loop, scroll pipeline
│   ├── video.asm       CRTC ring scroll, row-address LUT, palette
│   ├── scene.asm       sky / turf / scenery column renderer, redraw_rect
│   ├── sprite.asm      masked Mode 0 blitter and its lookup tables
│   ├── blocks.asm      the 20x10 grid, damage, and the collapse sweep
│   ├── entity.asm      pigs: poses, falling, being crushed
│   ├── shot.asm        slingshot, ballistics, collision
│   ├── level.asm       unpacking one of the forty records
│   ├── game.asm        turn machine and camera
│   ├── ui.asm          status strip and banners
│   ├── input.asm       keyboard matrix scanner
│   ├── art.asm         the creature bank, assembled as its own file
│   ├── hardware.inc    ports, memory map, tuning constants
│   └── state.inc       every mutable table, as addresses
├── assets/
│   ├── sheets/         SOURCE OF TRUTH for all art
│   └── levels/         SOURCE OF TRUTH for all forty forts
├── tools/
│   ├── artlib.py       dependency-free PNG codec + the 16-pen palette
│   ├── sheetdefs.py    the shape of every sheet, in one place
│   ├── mksheets.py     EXPORT the editable sheets
│   ├── gen_art.py      IMPORT them into the build
│   ├── levels.py       levels: txt <-> packed records, both directions
│   ├── gen_tables.py   font, strings, sine table
│   ├── cpcshot.py      run the real binary headless and screenshot it
│   ├── make_loader.sh  the AMSDOS BASIC bootloader
│   └── dsk2ext.py      standard DSK -> extended (emulators mangle the rest)
├── build/              (generated)
└── dist/               (generated) fowls.dsk
```

## Memory map

| Range | Use |
|-------|-----|
| `#0000-#003F` | IM 1 vector at `#0038` |
| `#0100-#02FF` | np2mask / np2data: art byte -> Mode 0 mask and data |
| `#0300-#03FF` | np2nib: the same, for compositing art over art |
| `#0400-#38FF` | creature art, 54 frames x 256 B |
| `#3F80-#3FFF` | stack |
| `#4000-#7FFF` | code, scenery run-length streams, the forty level records |
| `#8000-#98FF` | block art, 50 pieces x 128 B |
| `#9900-#BFFF` | game state |
| `#C000-#FFFF` | video RAM |

The art does not fit in one loadable image below `#C000`, so the BASIC
loader parks the creature bank in **video RAM** — which is ordinary memory
until something draws on it — and boot copies it down to `#0400` before
wiping the screen. Every ink is black through all of it.

## How it works

**Scrolling** is the CRTC ring trick: R12/R13 make the 16K of video RAM a
ring of 1024 characters per scanline block, and because the visible window
covers world column *x* at ring index `40*row + x` regardless of the
scroll offset, the world-to-ring mapping is camera-independent. One
primitive — "render world column *x* into its ring cells" — serves the
initial fill, both scroll seams, and every erase. The incoming column is
drawn a **frame early**, in the bottom border, into cells the beam has
already passed; the flip at the next VSYNC just reveals it.

**Scenery is run-length coded column-wise.** Fourteen 32x64 cells is 14 KB
raw and there is no 14 KB left. But scenery is only ever read by the column
renderer, which walks one 4-pixel strip top to bottom — so each cell is
stored as eight independent strips of `(count, byte, byte)` runs and read
in place, with no buffer and no decompression step. It packs 5.4:1, and it
makes the renderer *faster*: forty rows of sky are one loop iteration
instead of forty.

**Sprites land on even pixels.** A Mode 0 byte interleaves its two pixels
plane by plane, so moving an image one pixel sideways is not a bit shift —
it is `((in[i] AND #AA) >> 1) OR ((in[i-1] AND #55) << 1)`, which on a
16x32 sprite costs most of a video frame for half a pixel of precision in
a mode whose pixels are four screen pixels wide and whose camera pans in
steps of four. So x rounds down to even and the blitter has one path.

**Forts collapse cellularly, not physically.** Rigid-body physics is not
happening on a 4 MHz Z80, and it is not what makes the genre work anyway —
what makes it work is that structures *lose their footing*. Every piece
owns one grid cell; once something has been disturbed, a sweep runs from
the bottom row upward (the order matters: a block can only fall into a
cell the one below has already vacated) and anything unsupported starts
accelerating downward, dealing damage on landing in proportion to its
speed. Pigs are in the same grid, so a falling wall crushes them without a
line of special-case code.

A piece is supported by the ground, by whatever is in the cell below, or —
and this is what lets a lintel span a doorway — by being **wedged**, with
occupied cells to both left and right. Knock the pillar out from under one
end and that end loses its floor, falls, and takes its neighbour's support
with it, so the run unzips from the outside in, one block per sweep.

The sweep reads two hundred cells and costs the better part of half a
frame, so it does not run unconditionally: it is armed by damage and
disarmed by the first sweep that finds nothing moving. A bird in mid-air
over an untouched fort costs nothing.

## Verifying without an emulator in front of you

`tools/cpcshot.py` boots the **real binary** on an emulated CPC — Gate
Array, CRTC, PPI, and the PSG's keyboard port — and decodes the real
screen to PNG.

```sh
python3 tools/cpcshot.py 120 250 --keys 70:space+ 130:space-
```

Frames to capture are positional; `--keys` takes `frame:key+` and
`frame:key-` events. Shots land in `build/shots/`. This is how the
scrolling, the collapse and the blitter were debugged.

## State of play

Working: the build pipeline and both asset pipelines, the scroll engine
and scene renderer, the blitter, level loading, the slingshot and
ballistics, block damage and collapse, pigs falling and being crushed, the
turn machine, level progression, and the status strip.

Not there yet: sound, bird special abilities, a title screen, a score
table, and the between-level scoring flourish. The flight frame currently
runs at about 25 Hz while the camera is tracking a shot; the remaining
cost is the bird's erase-and-redraw and the scroll seam, both of which have
obvious room left.
