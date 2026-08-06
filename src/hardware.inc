; ============================================================================
;  FURIOUS FOWLS — hardware.inc
;  Amstrad CPC 464/6128 hardware, memory map and game constants.
;
;  Hex convention: '#' prefix throughout (unambiguous in RASM).
; ============================================================================

; ---------------------------------------------------------------------------
;  MEMORY MAP (64K baseline — no 6128 banking, so a 464 runs it too)
;
;    #0000-#003F  IM 1 vector at #0038
;    #0100-#01FF  np2mask   : art byte -> Mode 0 mask byte   (page aligned)
;    #0200-#02FF  np2data   : art byte -> Mode 0 data byte   (page aligned)
;    #0400-#191F  creature art, 54 frames x 100 B             (5400)
;    #3A00-#3F7B  the read-only tables the code bank has no room for, in
;                 one contiguous run: sin_table (page aligned, so it must
;                 come first), the sounds, the font, the scenery offsets,
;                 and then line_lut which is BUILT at boot rather than
;                 loaded. Their addresses are computed from each other
;                 below, so editing a sound cannot silently shift the rest
;                 into the stack — the assert in main.asm catches it.
;    #3F80-#3FFF  stack (grows down from #4000)
;    #4000-#87FF  code, scenery RLE, level records, tables
;    #8800-#8B1F  block art, 16 pieces x 50 B                 (800)
;    #8C00-#8D8F  rot_map   : the four tilt maps              (400)
;    #9E00-#BFFF  game state
;    #C000-#FFFF  video RAM
;
;  The art is too big to live in one loadable image below #C000, so the
;  loader puts the creature bank in VIDEO RAM (which is just RAM until we
;  start drawing) and boot copies it down to #0300 before clearing the
;  screen. Block art needs no move: it is simply part of the main image at
;  its final address. Scenery is run-length coded and read in place — see
;  scene.asm for why that costs nothing.
; ---------------------------------------------------------------------------
;  The scanline lookup is BUILT at boot by gen_line_lut, so it needs an
;  address but not a single byte of the loaded image. Keeping it in the
;  code bank cost 400 bytes of a 16K budget that had run out; down here it
;  costs nothing, and the spare below the stack was doing nothing anyway.
;  Three read-only tables that the code bank has no room for. They are
;  appended to the creature bank and copied down with it at boot, in THIS
;  ORDER — art.asm asserts each one lands where it is declared here.
sin_table               equ #3A00   ; page aligned: ld h,sin_table/256
SIN_TABLE_SIZE          equ 256
SOUNDS_BASE             equ sin_table+SIN_TABLE_SIZE
font5x7                 equ SOUNDS_BASE+SOUNDS_SIZE
FONT_SIZE               equ 39*7
scenery_ofs             equ font5x7+FONT_SIZE
SCENOFS_SIZE            equ 256
line_lut                equ scenery_ofs+SCENOFS_SIZE
LOW_TABLES_END          equ line_lut+SCREEN_LINES*2

CODE_BASE               equ #4000
STACK_TOP               equ #4000
SCREEN_BASE             equ #C000

; Three page-aligned lookup tables turn a byte of art (two 4-bit pens,
; high nibble = left pixel) into what the hardware wants, so a lookup is
; just "ld l,art / ld h,page":
;   np2data  the Mode 0 byte for those two pens
;   np2mask  the Mode 0 AND-mask that preserves the background under any
;            pen-0 (transparent) pixel
;   np2nib   the same idea one level up: the AND-mask that preserves
;            background ART under a transparent pen, used when compositing
;            scenery into the column buffer
NP2MASK                 equ #0100
NP2DATA                 equ #0200
NP2NIB                  equ #0300
CREATURE_ART            equ #0400
CREATURE_STAGE          equ #C000   ; where the loader parks it

;  ONE material set is 800 bytes of block art where five sets of ten
;  pieces were 2500, so the art starts two kilobytes later and the code
;  bank gets those two kilobytes — the scarce thing here is code space,
;  not the space above #8000.
BLOCK_ART               equ #8800
;  The tilt maps are read once per level load and never written. They
;  used to sit in the code bank, where a kilobyte was a sixteenth of
;  everything; there is room for them here, behind the block art and
;  still inside the same loaded image.
ROT_MAP_BASE            equ #8C00
STATE_BASE              equ #9E00

; ---------------------------------------------------------------------------
;  Playfield. The world is 320 px (80 CRTC chars) and the window shows
;  160 px (40 chars), panned by the CRTC ring scroll in 4 px steps.
;  Char row 0 is the HUD strip; the play area is rows 1..24.
; ---------------------------------------------------------------------------
SCREEN_BYTES_PER_LINE   equ 80      ; Mode 0: 160 px, 2 px per byte
SCREEN_LINES            equ 200
SCREEN_CHAR_ROWS        equ 25
VIEW_CHARS              equ 40      ; visible width, in CRTC chars — and the
                                    ; ring row stride, because the 6845
                                    ; advances each char row by R1. Narrowing
                                    ; it to 39 was tried and reverted: the
                                    ; incoming column aliases the trailing
                                    ; visible one for ANY R1, so it bought
                                    ; four pixels of loss and nothing else.
WORLD_CHARS             equ 80      ; world width, in CRTC chars
CAM_MAX                 equ WORLD_CHARS-VIEW_CHARS
CRTC_R12_BASE           equ #30     ; screen page #C000 (MA13..12 = 11)

HUD_LINES               equ 8       ; char row 0
PLAY_TOP                equ HUD_LINES

; GRID_W / GRID_H / CELL_PX / GROUND_Y / GRID_TOP_Y / WORLD_PX and the
; MAX_* limits come from build/level_defs.inc — tools/levels.py owns them,
; because the level compiler has to agree with the engine exactly.

; ---------------------------------------------------------------------------
;  Pens. Fixed roles, so art and palette can never disagree; the pen
;  numbers here ARE the indices in tools/artlib.py's ART_PALETTE.
; ---------------------------------------------------------------------------
PEN_SKY                 equ 0
PEN_BLACK               equ 1
PEN_WHITE               equ 2
PEN_RED                 equ 3
PEN_ORANGE              equ 4
PEN_YELLOW              equ 5
PEN_GREEN               equ 6
PEN_DGREEN              equ 7
PEN_CYAN                equ 8
PEN_BLUE                equ 9
PEN_GREY                equ 10
PEN_BROWN               equ 11
PEN_PINK                equ 12
PEN_SAND                equ 13
PEN_PALEBLUE            equ 14
PEN_PURPLE              equ 15

; ---------------------------------------------------------------------------
;  Entities. Birds and pigs share the 10x20 creature art and one struct.
; ---------------------------------------------------------------------------
ENT_SIZE                equ 16
ENT_STATE               equ 0       ; ES_*
ENT_TYPE                equ 1       ; creature index (bird 0..5, pig 6..8)
ENT_COL                 equ 2       ; grid column (pigs)
ENT_ROW                 equ 3       ; grid row of its FEET (pigs)
ENT_HP                  equ 4
ENT_FRAME               equ 5       ; FR_*
ENT_ANIM                equ 6       ; frames left in the current pose
ENT_YOFF                equ 7       ; sub-cell fall offset, pixels
ENT_VY                  equ 8       ; fall speed, 8.8
ENT_VY_I                equ 9
ENT_PX                  equ 10      ; last drawn position, for the erase
ENT_PY                  equ 11
ENT_PHASE               equ 12      ; blink phase, so they are out of step

ES_FREE                 equ 0
ES_REST                 equ 1       ; standing on something
ES_FALL                 equ 2       ; unsupported, on its way down
ES_DYING                equ 3       ; playing the death pose
ES_DEAD                 equ 4       ; gone

PIG_HP_BASE             equ 34      ; pig / helmet / king get x1, x2, x3
BLINK_PERIOD            equ 150     ; frames between idle blinks
BLINK_LEN               equ 8
HURT_LEN                equ 20
DIE_LEN                 equ 24

; ---------------------------------------------------------------------------
;  Blocks. One 16x16 cell each, anchored to the grid; a block only ever
;  moves DOWN, which is what makes a collapse cheap enough to run at 50 Hz.
; ---------------------------------------------------------------------------
BLK_SIZE                equ 16
BLK_STATE               equ 0       ; BS_*
BLK_PIECE               equ 1       ; 0..9, indexes the current material set
BLK_COL                 equ 2       ; its LEFTMOST cell
BLK_ROW                 equ 3
BLK_HP                  equ 4
BLK_YOFF                equ 5       ; sub-cell fall offset, 0..15 pixels
BLK_VY                  equ 6       ; sub-frame counter for the fall
BLK_VY_I                equ 7       ; fall speed, whole pixels per frame
BLK_LEN                 equ 8       ; cells wide: planks merge into beams
BLK_TILT                equ 9       ; 0 upright, else a rot_slope index
BLK_TIPT                equ 10      ; frames until the next tilt step
BLK_SHOVE               equ 11      ; #FF / 1: which side it was pushed from
BLK_FELL                equ 12      ; 1 = it has actually changed row

BS_FREE                 equ 0
BS_REST                 equ 1
BS_FALL                 equ 2
BS_TIP                  equ 3       ; going over the end it still has

;  What block_support decides about a piece
SUP_STABLE              equ 0
SUP_TIPR                equ 1       ; held on the left: the right end drops
SUP_TIPL                equ 2       ; held on the right: the left end drops
SUP_FALL                equ 3       ; nothing under it anywhere
TIP_FRAMES              equ 7       ; how long each tilt step is held
SLIDE_FRAMES            equ 4       ; ...and how long a slide down one is
MAX_BEAM                equ 8

GRID_EMPTY              equ #FF     ; occupancy grid: no tenant
GRID_PIG                equ #80     ; ...or this bit set means "pig N"

; ---------------------------------------------------------------------------
;  The shot. Position is 24-bit signed (16-bit pixel + 8-bit fraction) so
;  the bird can fly off the world and come back; velocity is 8.8 signed.
; ---------------------------------------------------------------------------
SHOT_SUBSTEPS           equ 2       ; collision steps per frame
GRAVITY                 equ #28     ; 0.156 px/frame^2 — tuned so a full-power
                                    ; shot at 45 degrees just crosses the
                                    ; 320 px world
VY_TERMINAL             equ 8       ; px/frame
POWER_MAX               equ 60
POWER_RATE              equ 3       ; charge per frame while SPACE is held
AIM_MIN                 equ 0       ; angle, in 1/256 turns
AIM_MAX                 equ 72      ; ...just past 100 degrees
AIM_RATE                equ 1
BIRD_R                  equ 7       ; collision radius about the bird centre
BOUNCE_NUM              equ 3       ; keep 3/8 of the speed off a surface
BOUNCE_DEN              equ 8
REST_SPEED              equ 1       ; below this the bird has stopped
MAX_HITS                equ 10      ; ...and after this many it has spent
                                    ; itself, wherever it happens to be

DMG_PER_SPEED           equ 12      ; block damage per px/frame of impact
; ---- how a blow is handed out ----------------------------------------------
;  1 = work the whole chain out first, then play it back OUTWARD from the
;      impact, one ring of contacts at a time.
;  0 = the original: apply it in block-table order as the walk leaves it.
;  The old path is kept whole under the switch, not deleted.
HIT_ORDERED             equ 1

CRUSH_PER_SPEED         equ 17      ; ...and per px/frame of a falling block.
                                    ; Calibrated, not picked: the slowest
                                    ; fall block_land will act on is 2 px a
                                    ; frame, so one cell of it comes to
                                    ; 2x17 = 34 = PIG_HP_BASE. Anything that
                                    ; genuinely drops on a plain pig kills
                                    ; it; helmets and kings still need
                                    ; weight or height behind it.

; ---------------------------------------------------------------------------
;  Game state machine
; ---------------------------------------------------------------------------
GS_AIM                  equ 0       ; a bird is on the sling
GS_FLY                  equ 1       ; it is in the air
GS_SETTLE               equ 2       ; waiting for the dust to fall
GS_CLEAR                equ 3       ; every pig popped
GS_FAIL                 equ 4       ; out of birds
GS_TITLE                equ 5       ; the screen it opens on
SETTLE_FRAMES           equ 60      ; quiet frames before the turn ends
SETTLE_MAX              equ 250     ; ...and the longest a settle may run
BANNER_FRAMES           equ 100

; ---------------------------------------------------------------------------
;  Slingshot geometry, relative to the level's sling x.
; ---------------------------------------------------------------------------
SLING_CELL_DX           equ -16     ; scenery cell x = sling_x - 16
SLING_CELL_Y            equ GROUND_Y-SC_H
SLING_POUCH_DY          equ 14      ; pouch centre, within the cell
SLING_POUCH_Y           equ SLING_CELL_Y+SLING_POUCH_DY
PULL_MAX                equ 14      ; how far back the bird is drawn

; ---------------------------------------------------------------------------
;  I/O ports (the CPC decodes the HIGH byte: always use BC + OUT (C))
; ---------------------------------------------------------------------------
GA_PORT                 equ #7F00   ; Gate Array (write only)
CRTC_SEL                equ #BC00
CRTC_DAT                equ #BD00
PPI_PORT_A              equ #F400   ; PSG data bus
PPI_PORT_B              equ #F500   ; bit 0 = VSYNC
PPI_PORT_C              equ #F600   ; PSG control, keyboard row
PPI_CONTROL             equ #F700

GA_SEL_PEN              equ #00
GA_SEL_BORDER           equ #10
GA_SET_COLOUR           equ #40
GA_RMR                  equ #80
GA_MMR                  equ #C0

GA_INT_RESET            equ #10
GA_UROM_OFF             equ #08
GA_LROM_OFF             equ #04
GA_ROM_OFF              equ GA_UROM_OFF|GA_LROM_OFF

VID_MODE0               equ 0
VID_MODE1               equ 1

; ---------------------------------------------------------------------------
;  Keyboard matrix (10 rows x 8 columns, read through PSG register 14).
;  kbd_state bytes are inverted on store: a set bit means pressed.
; ---------------------------------------------------------------------------
KBD_ROWS                equ 10
KEY_UP_ROW              equ 0
KEY_UP_MASK             equ #01
KEY_RIGHT_ROW           equ 0
KEY_RIGHT_MASK          equ #02
KEY_DOWN_ROW            equ 0
KEY_DOWN_MASK           equ #04
KEY_LEFT_ROW            equ 1
KEY_LEFT_MASK           equ #01
KEY_COPY_ROW            equ 1
KEY_COPY_MASK           equ #02
KEY_SHIFT_ROW           equ 2
KEY_SHIFT_MASK          equ #20
KEY_SPACE_ROW           equ 5
KEY_SPACE_MASK          equ #80
KEY_N_ROW               equ 5
KEY_N_MASK              equ #40
KEY_ESC_ROW             equ 8       ; line 8 bit 2 on the CPC matrix
KEY_ESC_MASK            equ #04
ESC_WINDOW              equ 60      ; game frames the first press stays armed
KEY_R_ROW               equ 6
KEY_R_MASK              equ #04

; ---------------------------------------------------------------------------
;  Hardware colour values (already OR'ed with GA_SET_COLOUR).
;  The comment is the firmware ink number, for cross reference.
; ---------------------------------------------------------------------------
HW_BLACK                equ #54     ; fw 0
HW_BLUE                 equ #44     ; fw 1
HW_BRIGHT_BLUE          equ #55     ; fw 2
HW_RED                  equ #5C     ; fw 3
HW_MAGENTA              equ #58     ; fw 4
HW_MAUVE                equ #5D     ; fw 5
HW_BRIGHT_RED           equ #4C     ; fw 6
HW_PURPLE               equ #45     ; fw 7
HW_BRIGHT_MAGENTA       equ #4D     ; fw 8
HW_GREEN                equ #56     ; fw 9
HW_CYAN                 equ #46     ; fw 10
HW_SKY_BLUE             equ #57     ; fw 11
HW_YELLOW               equ #5E     ; fw 12
HW_WHITE                equ #40     ; fw 13
HW_PASTEL_BLUE          equ #5F     ; fw 14
HW_ORANGE               equ #4E     ; fw 15
HW_PINK                 equ #47     ; fw 16
HW_PASTEL_MAGENTA       equ #4F     ; fw 17
HW_BRIGHT_GREEN         equ #52     ; fw 18
HW_SEA_GREEN            equ #42     ; fw 19
HW_BRIGHT_CYAN          equ #53     ; fw 20
HW_LIME                 equ #5A     ; fw 21
HW_PASTEL_GREEN         equ #59     ; fw 22
HW_PASTEL_CYAN          equ #5B     ; fw 23
HW_BRIGHT_YELLOW        equ #4A     ; fw 24
HW_PASTEL_YELLOW        equ #43     ; fw 25
HW_BRIGHT_WHITE         equ #4B     ; fw 26
