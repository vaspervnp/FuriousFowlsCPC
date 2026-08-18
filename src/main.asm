; ============================================================================
;  FURIOUS FOWLS — an Angry Birds for the Amstrad CPC 464/6128
;  ----------------------------------------------------------------------------
;  main.asm — entry point, hardware takeover, and the master frame loop.
;
;  Mode 0, 160x200 in sixteen colours, over a 320 px world panned by the
;  CRTC ring scroll. One frame is:
;
;    1. wait for VSYNC
;    2. apply any staged scroll — R12/R13 are latched at the top of the
;       frame, so this is the only safe moment
;    3. scan the keyboard
;    4. run the game: physics, collapse, sprites
;    5. stage the NEXT scroll column, down in the bottom border where the
;       beam has already gone
;
;  Step 5 is a frame early on purpose. A full 200-line column costs more
;  than the beam takes to cross the display, so drawing it just after the
;  flip would lose the race and show the incoming column half-rendered.
;  Drawn a frame ahead, into ring cells that currently alias a column the
;  beam has already passed, it is simply finished when the flip happens.
; ============================================================================

        include "level_defs.inc"    ; the level compiler owns the geometry
        include "art_defs.inc"      ; the sheet importer owns the art shapes
        include "rot_defs.inc"      ; ...and gen_rot.py the tilt steps
        include "sound_defs.inc"
        include "music_defs.inc"
        include "hardware.inc"
        include "state.inc"

        org     CODE_BASE
        run     CODE_BASE

;  The creature bank is copied down to CREATURE_ART at boot; anything else
;  parked in low memory has to start above where it ENDS. The map comment
;  is not the authority — this is.
        assert  CREATURE_ART+CREATURE_ART_SIZE <= sin_table
        assert  sin_table+SIN_TABLE_SIZE <= SOUNDS_BASE
        assert  LOW_TABLES_END < STACK_TOP-128

; ============================================================================
;  ENTRY — reached from the BASIC loader, which has already parked the
;  creature art in video RAM for us (see tools/make_loader.sh).
; ============================================================================
entry_point:
        di
        ld      sp,STACK_TOP

        ld      a,#C3               ; JP: our own IM 1 vector
        ld      (#0038),a
        ld      hl,frame_interrupt
        ld      (#0039),hl

        ld      bc,GA_PORT          ; Mode 0, both ROMs out of the way
        ld      a,GA_RMR|GA_ROM_OFF|GA_INT_RESET|VID_MODE0
        out     (c),a
        ld      a,GA_RMR|GA_ROM_OFF|VID_MODE0
        out     (c),a
        ld      a,GA_MMR            ; plain 64K map (ignored on a 464)
        out     (c),a

        call    crtc_init
        call    psg_init            ; ...or the keyboard reads as stuck
        call    palette_black

        ld      hl,STATE_BASE       ; start from a known state, rather than
        ld      de,STATE_BASE+1     ; from whatever the loader left. This has
        ld      bc,STATE_END-STATE_BASE-1   ; to come FIRST: the theme lands
        ld      (hl),0              ; in that range a few lines below, and
        ldir                        ; this would wipe it straight back out

        ld      hl,CREATURE_STAGE   ; rescue the art from video RAM before
        ld      de,CREATURE_ART     ; anything draws over it
        ld      bc,line_lut-CREATURE_ART
        ldir

;  The title theme, out of video RAM and into the block-art workspace. Both
;  ends of this are borrowed: the source is about to be wiped by the screen
;  clear below, and the destination by the first level load. That is the
;  point — the music should stop exactly when the game starts.
        ld      hl,CREATURE_STAGE+(line_lut-CREATURE_ART)
        ld      de,music_base
        ld      bc,MUSIC_SIZE
        ldir
        ld      a,1
        ld      (music_ok),a

        ld      hl,SCREEN_BASE      ; ...and only now wipe the screen clean
        ld      de,SCREEN_BASE+1
        ld      bc,#3FFF
        ld      (hl),0
        ldir

        call    gen_line_lut
        call    snd_init
        call    spr_init
        call    scene_init
        call    game_init

        im      1
        ei

; ============================================================================
;  MAIN LOOP — one pass per video frame
; ============================================================================
main_loop:
        call    wait_vsync
        call    apply_scroll        ; the flip, at the only safe moment
        ld      hl,frame_counter
        inc     (hl)
        call    kbd_scan
        call    hotkeys
;  THE SEAM GOES EARLY, not last. It has to start just after the beam has
;  cleared the top of the display and be finished before the next VSYNC,
;  and it is the longest single thing in the frame — so it wants the whole
;  of the frame after that point, not whatever is left once the physics has
;  had its turn. Called last it arrived at slice two or four, spun most of
;  a frame waiting for slice one to come round again, and then ran off the
;  end: the flip landed a frame late and the cells it had written were the
;  left edge of the screen for that whole frame.
;
;  It stages from the previous frame's world, which at the edge of the
;  window is one frame of staleness on a column the player is not looking
;  at yet.
        call    scroll_prep
        call    game_update
        call    snd_update          ; one step of every voice
        call    ui_refresh          ; ...if anything it shows has changed
        jr      main_loop

; ----------------------------------------------------------------------------
;  ui_refresh — recompose the status strip when something it shows has
;  changed. Pigs die deep inside the collapse sweep, where stopping to
;  redraw thirteen thousand T-states of text would be absurd; they raise a
;  flag instead and it is honoured here.
; ----------------------------------------------------------------------------
ui_refresh:
        ld      a,(ui_dirty)
        or      a
        ret     z
        xor     a
        ld      (ui_dirty),a
        call    ui_compose
        jp      ui_blit

; ----------------------------------------------------------------------------
;  hotkeys — R restarts the fort, N skips it (they are handy while you are
;  designing levels, and harmless to leave in).
; ----------------------------------------------------------------------------
;  ESC TWICE goes back to the menu. Once does nothing, and the arming
;  lapses after a second or so, because a single stray ESC in the middle of
;  a shot should not cost you the game.
hotkeys:
        ld      a,(kbd_edge+KEY_ESC_ROW)
        and     KEY_ESC_MASK
        jr      z,hk_esc_idle
        ld      hl,esc_armed
        ld      a,(hl)
        or      a
        jr      nz,hk_bail          ; the second press
        inc     (hl)
        ld      a,ESC_WINDOW
        ld      (esc_t),a
        jr      hk_keys
hk_esc_idle:
        ld      a,(esc_t)
        or      a
        jr      z,hk_keys
        dec     a
        ld      (esc_t),a
        jr      nz,hk_keys
        ld      (esc_armed),a       ; the window closed: disarm
hk_keys:
        ld      a,(kbd_edge+KEY_R_ROW)
        and     KEY_R_MASK
        jp      nz,game_start_level
        ld      a,(kbd_edge+KEY_N_ROW)
        and     KEY_N_MASK
        ret     z
        ld      a,(level_no)
        inc     a
        cp      LEVEL_COUNT
        jr      c,hk_go
        xor     a
hk_go:
        ld      (level_no),a
        jp      game_start_level

hk_bail:
        xor     a                   ; back to the menu, and back to level one
        ld      (esc_armed),a
        ld      (esc_t),a
        jp      game_to_menu

; ============================================================================
;  Scrolling, in two halves.
; ============================================================================

; ---- apply_scroll — right after VSYNC: nothing but the flip ----------------
apply_scroll:
        ld      a,(flip_dir)
        or      a
        ret     z
        xor     a
        ld      (flip_dir),a
        ld      a,(spr_cam)
        ld      (cam_x),a
        call    crtc_set_offset
;  THE STRIP GOES DOWN AFTER THE FLIP, not before it. Row 0's ring cells
;  are the forty consecutive chars starting at cam_x, so a strip written
;  for the new camera while the OLD offset is still programmed appears one
;  character to the right — the last of its cells is not on row 0 at all,
;  it is row 1 column 0 — and for that frame the player sees the strip
;  shifted with a black gap at the left and a stray character in it.
;
;  It is safe here because it is a straight run of stores into row 0 and we
;  are in the border: eighty bytes a scanline against a beam that has not
;  started, and row 0 is only eight scanlines long.
        jp      ui_blit

; ---- scroll_prep — end of frame: stage the incoming column -----------------
;  Drawn with cam_x already moved to where it WILL be. The world-to-ring
;  mapping does not depend on the camera, so the cells written are the right
;  ones either way; setting cam_x early just makes the clipping in
;  redraw_rect and spr_blit agree with the frame we are drawing for.
; ----------------------------------------------------------------------------
;  The clamp here is the one that matters. The world is only CAM_MAX+1
;  camera positions wide, and past that the window asks for world columns
;  that do not exist — whose ring cells still hold whatever was last drawn
;  in them, so the level appears to repeat. Whoever set scroll_dir is not
;  trusted to have checked.
; ----------------------------------------------------------------------------
scroll_prep:
        ld      a,(flip_dir)
        or      a
        ret     nz                  ; one step in flight at a time
        ld      a,(scroll_dir)
        or      a
        ret     z
        ld      c,a
        ld      a,(cam_x)
        bit     7,c
        jr      z,sp_right
        or      a
        ret     z                   ; already hard against the left edge
        ld      (sp_oldcam),a
        dec     a                   ; left: the new camera IS the new column
        ld      (spr_cam),a
        ld      (spr_col),a
        jr      sp_draw
sp_right:
        cp      CAM_MAX
        ret     nc                  ; already hard against the right edge
        ld      (sp_oldcam),a
        inc     a
        ld      (spr_cam),a
        add     a,VIEW_CHARS-1      ; right: the new trailing edge
        ld      (spr_col),a
sp_draw:
;  WAIT FOR THE BEAM. The seam column lands in ring cells that, until the
;  flip, alias the LEFTMOST visible column one row down, so the draw has to
;  be BEHIND the beam.
;
;  SLICE 2, AND NOT SLICE 1. Work the geometry from crtc_table: R4=38 and
;  R9=7 make the frame 39 char rows of 8 = 312 lines; R6=25 puts the
;  display on lines 0..199; R7=30 starts VSYNC at line 240. The Gate Array
;  resync interrupt — the one frame_interrupt sees with the VSYNC bit set,
;  which zeroes int_slice — fires about two lines into that pulse, at 242,
;  and the other five follow every 52 lines. So slice 1 is line 294, which
;  is EIGHTEEN LINES BEFORE the display top, and slice 2 is line 34, which
;  is thirty-four lines INTO it. Starting at slice 1 puts the draw AHEAD of
;  the beam and paints the incoming column down the left edge — which is
;  what it did, and it was mine.
;
;  ...OR ANY LATER SLICE, which is how CreepersCPC writes it. Insisting on
;  one slice exactly costs a whole frame whenever the rest of the loop has
;  already run past it, and that wait was the other half of the problem.
        ld      bc,0
sp_wait:
        ld      a,(int_slice)
        cp      2
        jr      nc,sp_go
        dec     bc                  ; never hang if the ISR is not ticking
        ld      a,b
        or      c
        jr      nz,sp_wait
sp_go:
        ld      a,(spr_cam)
        ld      (cam_x),a
        ld      a,(spr_col)
        ld      (rr_col0),a
        ld      a,1
        ld      (rr_ncol),a
;  Rows 8..199 only. Row 0 is the status strip and it is not drawn from
;  the world; it goes down in apply_scroll, after the flip — see there for
;  why it cannot go down here.

;  TAKE THE AIM DOTS OFF, do not merely forget them. The rebuild below
;  touches ONE column and the dotted line spans several: forgetting them
;  leaves every dot outside that column on the screen with nothing left
;  that knows how to erase it, which is one ghost of the line per pan.
;  Restoring puts them all back to background; an impossible angle then
;  makes the next frame lay the line down again where it now belongs.
        call    aim_undot
        ld      a,#FF
        ld      (ad_angle),a

        ld      a,PLAY_TOP
        ld      (rr_y0),a
        ld      a,SCREEN_LINES-PLAY_TOP
        ld      (rr_n),a
        call    redraw_rect
        ld      a,(sp_oldcam)       ; the flip has not happened yet
        ld      (cam_x),a
        ld      a,1
        ld      (flip_dir),a
;  AND FLIP IT HERE, not on the next pass round the loop.
;
;  The cells just written alias the leftmost visible column until the flip,
;  and the draw ends about where VSYNC is — so the flip is one wait away.
;  Left to main_loop it happened a pass later, and a pass is longer than a
;  frame while the seam is being drawn: the aliased cells were the left
;  edge of the screen for a whole display frame, which is the strip of the
;  far side of the world the player was seeing. Profiling says a third of
;  the loop is already spent waiting for VSYNC, so the wait costs nothing
;  that was not being spent anyway.
        call    wait_vsync
        jp      apply_scroll


; ============================================================================
;  frame_interrupt — the Gate Array fires six of these a frame. Nothing
;  needs them yet (there is no sound engine), but with both ROMs paged out
;  #0038 has to go somewhere deliberate.
; ============================================================================
frame_interrupt:
        push    af
        push    bc
        push    hl
        ld      bc,PPI_PORT_B
        in      a,(c)
        rra                         ; the one that fires during VSYNC is the
        jr      nc,fi_mid           ; anchor for the raster slice counter
        xor     a
        ld      (int_slice),a
        jr      fi_count
fi_mid:
        ld      hl,int_slice
        inc     (hl)
        ld      a,(hl)
        cp      6                   ; six per frame; if the anchor was missed
        jr      c,fi_count          ; (a long DI section) resync anyway
        xor     a
        ld      (int_slice),a
fi_count:
        ld      hl,(irq_counter)
        inc     hl
        ld      (irq_counter),hl
        pop     hl
        pop     bc
        pop     af
        ei
        ret

sp_oldcam:      db      0

; ============================================================================
;  Modules
; ============================================================================
        include "video.asm"
        include "scene.asm"
        include "sprite.asm"
        include "blocks.asm"
        include "entity.asm"
        include "shot.asm"
        include "level.asm"
        include "game.asm"
        include "ui.asm"
        include "input.asm"
        include "title.asm"
        include "sound.asm"
        include "disk.asm"

; ---- generated tables ------------------------------------------------------
        include "art_tables.inc"    ; block strengths, scenery strip offsets
        include "level_tables.inc"  ; where each of the fifty records starts
        include "tables.inc"        ; font, strings, sine

scenery_rle:
        incbin  "scenery.raw"

        assert  $ < BLOCK_ART       ; the code bank must not reach the art
code_end:

; ---- the level records, out of the code bank and behind the tilt maps ------
        org     LEVEL_DATA_BASE
level_data:
        incbin  "levels.raw"
        assert  $ <= STATE_BASE

;  Not code: RASM only writes a symbol for a LABEL, and every address in
;  state.inc is an equate, so the headless tools had to guess the layout
;  from arithmetic and were wrong twice. These put the ones the tools ask
;  about into the .sym where they cannot drift.
 org score
sym_score:
 org hi_score
sym_hi_score:
 org tries
sym_tries:
 org difficulty
sym_difficulty:
 org blocks
sym_blocks:
 org grid
sym_grid:
 org pigs
sym_pigs:
 org cam_x
sym_cam_x:
 org game_state
sym_game_state:
 org frame_counter
sym_frame_counter:

; ---- block art, at its permanent address and needing no move ---------------
        org     BLOCK_ART
block_art_image:
        incbin  "blocks.raw"
        assert  $ <= ROT_MAP_BASE

; ---- the tilt maps, behind the art and out of the code bank ---------------
        org     ROT_MAP_BASE
        include "rot_tables.inc"
        assert  $ <= STATE_BASE
