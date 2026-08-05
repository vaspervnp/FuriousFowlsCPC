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
        include "hardware.inc"
        include "state.inc"

        org     CODE_BASE
        run     CODE_BASE

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
        call    palette_black

        ld      hl,CREATURE_STAGE   ; rescue the art from video RAM before
        ld      de,CREATURE_ART     ; anything draws over it
        ld      bc,CREATURE_ART_SIZE
        ldir
        ld      hl,SCREEN_BASE      ; ...then wipe the screen clean
        ld      de,SCREEN_BASE+1
        ld      bc,#3FFF
        ld      (hl),0
        ldir
        ld      hl,STATE_BASE       ; and start from a known state, rather
        ld      de,STATE_BASE+1     ; than from whatever the loader left
        ld      bc,STATE_END-STATE_BASE-1
        ld      (hl),0
        ldir

        call    gen_line_lut
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
        call    game_update
        call    ui_refresh          ; ...if anything it shows has changed
        call    scroll_prep         ; stage the next column, in the border
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
hotkeys:
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
        jp      crtc_set_offset

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
;  flip, alias the LEFTMOST visible column one row down — so drawing it
;  while the beam is still crossing the display rewrites what the player is
;  looking at, and the left edge of the turf crawls and tears. Started in
;  slice 2 the draw is always behind the beam for this frame (it writes row
;  r at ~104+11r, the beam showed that cell at 40+8r) and always ahead of
;  it for the next (344+8r), for every row.
        ld      bc,0
sp_wait:
        ld      a,(int_slice)
        cp      2
        jr      z,sp_go
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
        xor     a                   ; the WHOLE column, row 0 included:
        ld      (rr_y0),a           ; ui_blit repaints the status strip
        ld      a,SCREEN_LINES      ; immediately afterwards anyway
        ld      (rr_n),a
        call    redraw_rect
        call    ui_blit             ; row 0 scrolls too: lay it down again
        ld      a,(sp_oldcam)       ; the flip has not happened yet
        ld      (cam_x),a
        ld      a,1
        ld      (flip_dir),a
        ret

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

; ---- generated tables ------------------------------------------------------
        include "art_tables.inc"    ; block strengths, scenery strip offsets
        include "level_tables.inc"  ; where each of the forty records starts
        include "tables.inc"        ; font, strings, sine
        include "rot_tables.inc"    ; the four tilt maps

scenery_rle:
        incbin  "scenery.raw"
level_data:
        incbin  "levels.raw"

        assert  $ < BLOCK_ART       ; the code bank must not reach the art
code_end:

; ---- block art, at its permanent address and needing no move ---------------
        org     BLOCK_ART
block_art_image:
        incbin  "blocks.raw"
        assert  $ <= STATE_BASE
