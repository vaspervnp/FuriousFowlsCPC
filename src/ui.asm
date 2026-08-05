; ============================================================================
;  FURIOUS FOWLS — ui.asm
;  The status strip along the top, and the between-level banners.
;
;  The strip is composed into hud_buf in ART form (the same two-pens-per-byte
;  format everything else uses) and then blitted into WORLD char row 0 at
;  the camera's column. It has to be re-blitted whenever the camera moves,
;  because row 0 scrolls with everything else — there is no hardware split
;  here, just a redraw in the bottom border where the beam has already gone.
; ============================================================================

; ----------------------------------------------------------------------------
;  ui_compose — repaint hud_buf from the current game state
; ----------------------------------------------------------------------------
ui_compose:
        ld      hl,hud_buf          ; a black bar to sit the text on
        ld      de,hud_buf+1
        ld      bc,HUD_SIZE-1
        ld      a,(mode0_pen_bytes+PEN_BLACK)
        ld      (hl),a
        ldir

        ld      a,(game_state)
        cp      GS_CLEAR
        jr      z,uc_clear
        cp      GS_FAIL
        jr      z,uc_fail

        ld      hl,str_level        ; LEVEL nn
        ld      c,2
        ld      b,PEN_WHITE
        call    ui_text
        ld      a,(level_no)
        inc     a
        ld      c,36
        ld      b,PEN_YELLOW
        call    ui_num2

        ld      hl,str_birds        ; BIRDS n
        ld      c,54
        ld      b,PEN_WHITE
        call    ui_text
        ld      a,(bird_count)
        ld      c,a
        ld      a,(bird_idx)
        ld      b,a
        ld      a,c
        sub     b
        jr      nc,uc_birds
        xor     a
uc_birds:
        ld      c,90
        ld      b,PEN_YELLOW
        call    ui_num1

        ld      hl,str_pigs         ; PIGS n
        ld      c,104
        ld      b,PEN_WHITE
        call    ui_text
        ld      a,(pigs_alive)
        ld      c,134
        ld      b,PEN_GREEN
        jp      ui_num1

uc_clear:
        ld      hl,str_clear
        ld      c,8
        ld      b,PEN_YELLOW
        call    ui_text
        ld      hl,str_next
        ld      c,72
        ld      b,PEN_WHITE
        jp      ui_text
uc_fail:
        ld      hl,str_fail
        ld      c,8
        ld      b,PEN_RED
        call    ui_text
        ld      hl,str_retry
        ld      c,80
        ld      b,PEN_WHITE
        jp      ui_text

; ----------------------------------------------------------------------------
;  ui_text — HL = glyph string (#FE space, #FF end), C = x, B = pen
; ----------------------------------------------------------------------------
ui_text:
        ld      a,(hl)
        cp      GL_END
        ret     z
        inc     hl
        cp      GL_SPACE
        jr      z,ut_gap
        push    hl
        push    bc
        call    ui_glyph
        pop     bc
        pop     hl
ut_gap:
        ld      a,c
        add     a,FONT_W+1
        ld      c,a
        jr      ui_text

; ----------------------------------------------------------------------------
;  ui_num1 / ui_num2 — A = value, C = x, B = pen
; ----------------------------------------------------------------------------
ui_num2:
        ld      e,a
        ld      d,0
un_tens:
        ld      a,e
        cp      10
        jr      c,un_tens_done
        sub     10
        ld      e,a
        inc     d
        jr      un_tens
un_tens_done:
        push    de
        push    bc
        ld      a,d
        call    ui_glyph
        pop     bc
        pop     de
        ld      a,c
        add     a,FONT_W+1
        ld      c,a
        ld      a,e
        ; fall through
ui_num1:
        call    ui_glyph
        ret

; ----------------------------------------------------------------------------
;  ui_glyph — A = glyph index, C = x, B = pen. Draws 5x7 into hud_buf.
; ----------------------------------------------------------------------------
ui_glyph:
        ld      l,a
        ld      h,0
        ld      d,h
        ld      e,l
        add     hl,hl
        add     hl,hl
        add     hl,de
        add     hl,de
        add     hl,de               ; index * 7
        ld      de,font5x7
        add     hl,de
        ld      a,FONT_H
        ld      (ug_rows),a
        xor     a
        ld      (ug_y),a
ug_row:
        ld      a,(hl)
        ld      (ug_bits),a
        push    hl
        ld      a,c
        ld      (ug_x),a
        ld      d,FONT_W
ug_col:
        ld      a,(ug_bits)
        add     a,a                 ; bit 4 is the leftmost pixel, so shift
        ld      (ug_bits),a         ; it up into bit 7 three times over
        add     a,a
        add     a,a
        add     a,a
        jr      nc,ug_skip
        push    de
        push    bc
        call    ui_px
        pop     bc
        pop     de
ug_skip:
        ld      a,(ug_x)
        inc     a
        ld      (ug_x),a
        dec     d
        jr      nz,ug_col
        pop     hl
        inc     hl
        ld      a,(ug_y)
        inc     a
        ld      (ug_y),a
        ld      a,(ug_rows)
        dec     a
        ld      (ug_rows),a
        jr      nz,ug_row
        ret

; ----------------------------------------------------------------------------
;  ui_px — plot (ug_x, ug_y) in pen B, straight into Mode 0.
;
;  The strip used to be composed in art form and converted afterwards,
;  which cost a second 640-byte buffer. Plotting a Mode 0 pixel is only a
;  mask and an OR, so the conversion — and the buffer — are gone.
; ----------------------------------------------------------------------------
ui_px:
        ld      a,(ug_x)
        cp      VIEW_CHARS*4
        ret     nc
        ld      a,(ug_y)            ; hud_buf + y * HUD_STRIDE + x / 2
        ld      l,a
        ld      h,0
        add     hl,hl
        add     hl,hl
        add     hl,hl
        add     hl,hl               ; y * 16
        ld      d,h
        ld      e,l
        add     hl,hl
        add     hl,hl               ; y * 64
        add     hl,de               ; y * 80
        ld      a,(ug_x)
        srl     a
        ld      e,a
        ld      d,0
        add     hl,de
        ld      de,hud_buf
        add     hl,de

        ld      a,b                 ; the pen as a both-pixel Mode 0 byte
        ld      de,mode0_pen_bytes
        add     a,e
        ld      e,a
        adc     a,d
        sub     e
        ld      d,a
        ld      a,(de)
        ld      c,a
        ld      a,(ug_x)
        bit     0,a
        jr      nz,up_right
        ld      a,c                 ; left pixel: bits 7,3,5,1
        and     #AA
        ld      c,a
        ld      a,(hl)
        and     #55
        or      c
        ld      (hl),a
        ret
up_right:
        ld      a,c
        and     #55
        ld      c,a
        ld      a,(hl)
        and     #AA
        or      c
        ld      (hl),a
        ret
        assert  HUD_STRIDE == 80

; ============================================================================
;  ui_blit — push hud_m0 into world char row 0 at the camera's column.
;
;  Row 0's ring cells are the forty consecutive chars starting at cam_x, so
;  each scanline is one contiguous 80-byte run — and because row 0's ring
;  offset never exceeds 160, it can never reach the 2048-byte fold. That
;  makes the whole strip eight straight LDIRs, which matters: this runs on
;  every frame the camera moves.
; ============================================================================
ui_blit:
        ld      hl,hud_buf
        ld      (ub_src),hl
        xor     a
        ld      (ub_y),a
ub_line:
        ld      a,(cam_x)
        ld      d,a
        ld      a,(ub_y)
        ld      e,a
        call    world_to_screen
        ex      de,hl               ; DE = video RAM
        ld      hl,(ub_src)
        ld      bc,HUD_STRIDE
        ldir
        ld      (ub_src),hl
        ld      a,(ub_y)
        inc     a
        ld      (ub_y),a
        cp      HUD_LINES
        jr      c,ub_line
        ret
        assert  (CAM_MAX+VIEW_CHARS)*2 < #800

; ----------------------------------------------------------------------------
;  ui state
; ----------------------------------------------------------------------------
ug_x:           db      0
ug_y:           db      0
ug_bits:        db      0
ug_rows:        db      0
ub_src:         dw      0
ub_y:           db      0
ub_yv:          db      0
