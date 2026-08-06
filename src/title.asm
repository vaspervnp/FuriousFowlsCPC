; ============================================================================
;  FURIOUS FOWLS — title.asm
;  The screen the game opens on.
;
;  There is no second font. The 5x7 glyphs the status strip uses are drawn
;  here through plot_px with every lit pixel expanded into a square block,
;  so (tb_scale) is the whole difference between the title and the credit
;  line — three hundred bytes of big lettering that cost nothing but a
;  loop, on a machine with none to spare.
;
;  The colour is chosen per ROW rather than per string: the top four rows
;  of every glyph in one pen and the bottom three in another. At three
;  times scale that reads as a two-tone arcade logo rather than as text
;  that happens to be large, and it costs one compare inside a loop that
;  was already there.
;
;  The birds and the pigs below it blink together. The two poses differ
;  only in the eyes, so the second one is simply blitted over the first;
;  the silhouette is identical and there is nothing left showing round the
;  edges. That saves clearing two thirty-two-line bands sixty times a
;  second for an animation that is two frames long.
; ============================================================================

TB_SCALE_BIG    equ 3
TITLE_BIRD_Y    equ 74
TITLE_PIG_Y     equ 104
BLINK_MASK      equ 63              ; a blink roughly every second...
BLINK_SHUT      equ 6               ; ...lasting this long

; ----------------------------------------------------------------------------
;  title_show — paint it once. Reached from game_init, so the game opens
;  here instead of on level one.
; ----------------------------------------------------------------------------
title_show:
        call    palette_black       ; build it behind a black palette, the
        xor     a                   ; same trick game_start_level uses
        ld      (cam_x),a
        ld      (scroll_dir),a
        ld      (flip_dir),a
        ld      (title_t),a
        call    crtc_set_offset

        ld      hl,SCREEN_BASE
        ld      de,SCREEN_BASE+1
        ld      bc,#3FFF
        ld      a,(mode0_pen_bytes+PEN_BLACK)
        ld      (hl),a
        ldir

        ld      a,TB_SCALE_BIG
        ld      (tb_scale),a
        ld      a,PEN_YELLOW
        ld      (tb_pen2),a
        ld      a,PEN_RED
        ld      hl,str_fowland      ; 8 glyphs x 18 = 141 px, centred in 160
        ld      de,#090E            ; D = x 9, E = y 14
        call    title_text
        ld      a,PEN_RED
        ld      hl,str_furious      ; 7 glyphs = 123 px
        ld      de,#122A            ; D = x 18, E = y 42
        call    title_text

        ld      a,1
        ld      (tb_scale),a
        ld      a,PEN_WHITE
        ld      (tb_pen2),a
        ld      hl,str_start
        ld      de,#268C            ; D = x 38, E = y 140
        call    title_text
        ld      a,PEN_YELLOW        ; HI SCORE nnnnnn, centred
        ld      (tb_pen2),a
        ld      hl,str_hi
        ld      de,#2280            ; D = x 34, E = y 128
        call    title_text
        ld      hl,hi_score
        call    num6
        ld      hl,num6_buf
        ld      de,#5880            ; D = x 88, E = y 128
        call    title_text

        ld      a,PEN_CYAN
        ld      (tb_pen2),a
        ld      hl,str_credit
        ld      de,#02AC            ; D = x 2, E = y 172
        call    title_text

        ld      a,PEN_GREEN
        call    title_mode
        ld      a,PEN_CYAN
        call    title_diff
        call    title_creatures
        call    title_music
        ld      a,GS_TITLE
        ld      (game_state),a
        jp      palette_apply

; ----------------------------------------------------------------------------
;  title_text — HL = glyph string, D = x, E = y, A = pen, (tb_scale) set.
; ----------------------------------------------------------------------------
title_text:
        push    hl
        push    de
        call    tb_penbyte          ; A = the pen for the top of each glyph
        ld      (tb_top),a
        ld      a,(tb_pen2)
        call    tb_penbyte
        ld      (tb_bot),a
        pop     de
        pop     hl
        ld      a,d
        ld      (tb_x),a
        ld      a,e
        ld      (tb_y0),a
tt_char:
        ld      a,(hl)
        cp      GL_END
        ret     z
        inc     hl
        cp      GL_SPACE
        jr      z,tt_advance
        push    hl
        ld      l,a                 ; font5x7 + glyph*7
        ld      h,0
        ld      d,h
        ld      e,l
        add     hl,hl
        add     hl,hl
        add     hl,de
        add     hl,de
        add     hl,de
        ld      de,font5x7
        add     hl,de
        ld      a,(tb_y0)
        ld      (tb_y),a
        ld      b,FONT_H
tt_row:
        push    bc
        ld      a,b                 ; B counts FONT_H down to 1, so the top
        cp      4                   ; four rows are one pen and the rest the
        ld      a,(tb_bot)          ; other
        jr      c,tt_rowpen
        ld      a,(tb_top)
tt_rowpen:
        ld      (pp_pen),a
        ld      a,(hl)
        ld      (tb_bits),a
        push    hl
        ld      a,(tb_x)
        ld      (tb_cx),a
        ld      b,FONT_W
tt_col:
        push    bc
        ld      a,(tb_bits)         ; bit 4 is the leftmost pixel: step the
        add     a,a                 ; stream on by one, then look at what
        ld      (tb_bits),a         ; is now in bit 7
        add     a,a
        add     a,a
        add     a,a
        call    c,tt_block
        ld      a,(tb_scale)        ; on to the next font pixel
        ld      b,a
        ld      a,(tb_cx)
        add     a,b
        ld      (tb_cx),a
        pop     bc
        djnz    tt_col
        pop     hl
        inc     hl
        ld      a,(tb_scale)
        ld      b,a
        ld      a,(tb_y)
        add     a,b
        ld      (tb_y),a
        pop     bc
        djnz    tt_row
        pop     hl
tt_advance:
        ld      a,(tb_scale)        ; one glyph plus one pixel of gap
        ld      b,a
        add     a,a
        add     a,a
        add     a,b
        add     a,b                 ; scale * 6
        ld      b,a
        ld      a,(tb_x)
        add     a,b
        ld      (tb_x),a
        jr      tt_char

; ---- tb_penbyte — A = pen index -> A = its both-pixel Mode 0 byte ---------
tb_penbyte:
        ld      hl,mode0_pen_bytes
        add     a,l
        ld      l,a
        adc     a,h
        sub     l
        ld      h,a
        ld      a,(hl)
        ret

; ---- tt_block — one font pixel, as a (tb_scale) square ---------------------
tt_block:
        ld      a,(tb_y)
        ld      (tb_by),a
        ld      a,(tb_scale)
        ld      (tb_rows),a
tt_brow:
        ld      a,(tb_cx)
        ld      l,a
        ld      h,0
        ld      a,(tb_scale)
        ld      b,a
tt_bcol:
        push    bc
        push    hl
        ld      a,(tb_by)
        call    plot_px
        pop     hl
        inc     hl
        pop     bc
        djnz    tt_bcol
        ld      hl,tb_by
        inc     (hl)
        ld      hl,tb_rows
        dec     (hl)
        jr      nz,tt_brow
        ret

; ---- title_music — melody on A, bass on B, from the top --------------------
title_music:
        ld      a,(music_ok)        ; the bytes may be block art by now
        or      a
        ret     z
        ld      hl,music_base
        ld      c,0
        call    snd_play_hl
        ld      hl,music_base+MUSIC_BASS_OFS
        ld      c,1
        jp      snd_play_hl

; ----------------------------------------------------------------------------
;  title_mode — A = pen. Draws whichever side is currently doing the
;  throwing. Rubbing the old line out is the same call in PEN_BLACK: it
;  unpaints exactly the pixels it painted, which is cheaper and a great
;  deal safer than working out which ring cells a band of text covers.
; ----------------------------------------------------------------------------
title_mode:
        ld      (tb_pen2),a
        push    af
        ld      a,1
        ld      (tb_scale),a
        ld      a,(swap_mode)
        or      a
        ld      hl,str_thfowl
        jr      z,tm_go
        ld      hl,str_thpig
tm_go:
        pop     af
        ld      de,#2098            ; D = x 32, E = y 152
        jp      title_text

; ----------------------------------------------------------------------------
;  title_diff — A = pen. The line that says how many goes a fort allows.
;  Rubbed out the same way title_mode is: repaint it in PEN_BLACK, which
;  unpaints exactly the pixels it painted. The three names are different
;  lengths, so anything that erased a fixed box would be wrong for two of
;  them.
; ----------------------------------------------------------------------------
title_diff:
        ld      (tb_pen2),a
        push    af
        ld      a,1
        ld      (tb_scale),a
        ld      a,(difficulty)
        ld      hl,str_easy
        or      a
        jr      z,td_go
        ld      hl,str_med
        dec     a
        jr      z,td_go
        ld      hl,str_hard
td_go:
        pop     af
        ld      de,#20A2            ; D = x 32, E = y 162
        jp      title_text

; ----------------------------------------------------------------------------
;  over_show — GAME OVER, big and two-tone, over the middle of the window.
;
;  title_text keeps its x in a single byte, so this can only be drawn with
;  the camera at the left of the world — which is where the game puts it
;  when the last bird is gone, so that the player sees the fort that beat
;  them from the place they were throwing at it.
; ----------------------------------------------------------------------------
over_show:
        ld      a,TB_SCALE_BIG
        ld      (tb_scale),a
        ld      a,PEN_YELLOW
        ld      (tb_pen2),a
        ld      a,PEN_RED
        ld      hl,str_game         ; 4 glyphs x 18 = 69 px, centred in 160
        ld      de,#2D46            ; D = x 45, E = y 70
        call    title_text
        ld      a,PEN_RED
        ld      hl,str_overb
        ld      de,#2D5E            ; D = x 45, E = y 94
        call    title_text
        ld      a,1
        ld      (tb_scale),a
        ret

; ----------------------------------------------------------------------------
;  title_creatures — the six birds, then the three pigs, in the pose the
;  blink timer is currently on.
; ----------------------------------------------------------------------------
title_creatures:
        ld      a,(title_t)
        and     BLINK_MASK
        cp      BLINK_SHUT
        ld      a,FR_IDLE
        jr      nc,tc_pose
        ld      a,FR_BLINK
tc_pose:
        ld      (tc_frame),a
        ld      a,CR_BYTES_PER_ROW
        ld      (sp_w),a
        ld      a,CR_HEIGHT
        ld      (sp_h),a

        ld      hl,TITLE_BIRD_Y     ; six birds, centred
        ld      (sp_y),hl
        ld      hl,(160-BIRD_TYPES*CR_WIDTH)/2
        ld      (sp_x),hl
        ld      bc,BIRD_TYPES*256   ; B = how many, C = the first type
        call    tc_run
        ld      hl,TITLE_PIG_Y      ; three pigs under them
        ld      (sp_y),hl
        ld      hl,(160-PIG_TYPES*CR_WIDTH)/2 & #FE
        ld      (sp_x),hl
        ld      bc,PIG_TYPES*256+PIG_PIG
        ; fall through
tc_run:
        push    bc
        ld      a,(tc_frame)
        ld      b,a
        ld      a,c
        ld      c,b
        call    art_for_creature
        ld      (sp_art),hl
        call    spr_blit
        ld      hl,(sp_x)
        ld      de,CR_WIDTH
        add     hl,de
        ld      (sp_x),hl
        pop     bc
        inc     c
        djnz    tc_run
        ret

; ----------------------------------------------------------------------------
;  gu_title — one frame of waiting. SPACE starts the game.
; ----------------------------------------------------------------------------
gu_title:
        ld      hl,(snd_state)      ; the theme has played itself out: round
        ld      a,h                 ; again, for as long as they sit here
        or      l
        call    z,title_music
        ld      hl,title_t
        
        inc     (hl)
        ld      a,(hl)
        and     BLINK_MASK          ; only redraw on the two frames the pose
        cp      BLINK_SHUT+1        ; actually changes
        jr      z,tu_redraw
        or      a
        jr      z,tu_redraw
        ld      a,(kbd_edge+KEY_UP_ROW)
        and     KEY_UP_MASK
        jr      z,tu_key
        ld      a,PEN_BLACK         ; out with the old...
        call    title_mode
        ld      hl,swap_mode
        ld      a,(hl)
        xor     1
        ld      (hl),a
        ld      a,PEN_GREEN         ; ...and in with the new
        call    title_mode
tu_key:
        ld      a,(kbd_edge+KEY_DOWN_ROW)
        and     KEY_DOWN_MASK
        jr      z,tu_start
        ld      a,PEN_BLACK         ; same out-and-in as the mode line
        call    title_diff
        ld      a,(difficulty)
        inc     a
        cp      DIFF_COUNT
        jr      c,tu_diff
        xor     a
tu_diff:
        ld      (difficulty),a
        ld      a,1                 ; it rides to the disc with the score
        ld      (hi_dirty),a
        ld      a,PEN_CYAN
        call    title_diff
tu_start:
        ld      a,(kbd_edge+KEY_SPACE_ROW)
        and     KEY_SPACE_MASK
        ret     z
        jp      game_start_level
tu_redraw:
        call    title_creatures
        jr      tu_key

tb_x:           db      0
tb_y0:          db      0
tb_y:           db      0
tb_cx:          db      0
tb_by:          db      0
tb_rows:        db      0
tb_bits:        db      0
tb_scale:       db      1
tb_top:         db      0
tb_bot:         db      0
tb_pen2:        db      0
tc_frame:       db      0
title_t:        db      0
