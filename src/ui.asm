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
        jp      z,uc_fail
        cp      GS_OVER
        jp      z,uc_over

        ld      hl,str_lv           ; LV nn
        ld      c,2
        ld      b,PEN_WHITE
        call    ui_text
        ld      a,(level_no)
        inc     a
        ld      c,14
        ld      b,PEN_YELLOW
        call    ui_num2

;  The two counters keep their positions and swap their LABELS: in the
;  reversed mode the thing in the pouch is a pig and the thing in the way
;  is a bird, and a strip that says otherwise is just wrong.
        ld      hl,str_bd           ; what is left to throw
        ld      a,(swap_mode)
        or      a
        jr      z,uc_lbl1
        ld      hl,str_pg
uc_lbl1:
        ld      c,32
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
        ld      c,44
        ld      b,PEN_YELLOW
        call    ui_num1

        ld      hl,str_pg           ; ...and what is still standing
        ld      a,(swap_mode)
        or      a
        jr      z,uc_lbl2
        ld      hl,str_bd
uc_lbl2:
        ld      c,56
        ld      b,PEN_WHITE
        call    ui_text
        ld      a,(pigs_alive)
        ld      c,68
        ld      b,PEN_GREEN
        call    ui_num1

        ld      hl,str_sc           ; ...and what it has all been worth
        ld      c,86
        ld      b,PEN_WHITE
        call    ui_text
        ld      hl,score
        ld      c,98
        ld      b,PEN_YELLOW
        jp      ui_num6

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
        ld      c,2
        ld      b,PEN_RED
        call    ui_text
        ld      hl,str_retry
        ld      c,76
        ld      b,PEN_WHITE
        call    ui_text
        ld      hl,str_go           ; ...and which go this was, of five
        ld      c,#8A
        ld      b,PEN_WHITE
        call    ui_text
        ld      a,(tries)
        ld      c,150
        ld      b,PEN_YELLOW
        jp      ui_num1
uc_over:
        ld      hl,str_over
        ld      c,8
        ld      b,PEN_RED
        call    ui_text
        ld      hl,str_menu
        ld      c,72
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
;  ui_num6 — HL = a 24-bit value, C = x, B = pen. Six digits, zero padded.
;
;  Binary to decimal without a division routine: subtract a power of ten
;  until it will not go, and the number of times IS the digit. Six digits
;  is six passes over five constants, which happens when the strip is
;  recomposed and not per frame, so the loop costs nothing worth saving.
; ----------------------------------------------------------------------------
ui_num6:
;  B IS THE PEN, and it stays the pen. Using it as the djnz counter as well
;  drew the six digits in pens six down to one — the last of them in pen 1,
;  which is BLACK on a black strip, so the score silently lost its units
;  column.
        push    bc
        call    num6
        pop     bc
        ld      hl,num6_buf
        ld      a,6
        ld      (un6_n),a
un6_out:
        push    bc
        push    hl
        ld      a,(hl)
        call    ui_glyph
        pop     hl
        pop     bc
        inc     hl
        ld      a,c
        add     a,FONT_W+1
        ld      c,a
        push    hl
        ld      hl,un6_n
        dec     (hl)
        pop     hl
        jr      nz,un6_out
        ret

; ----------------------------------------------------------------------------
;  num6 — HL = a 24-bit value -> (num6_buf), six digit glyphs and an end
;  marker, so it can go to ui_glyph or straight to title_text.
; ----------------------------------------------------------------------------
num6:
        ld      e,(hl)              ; a private copy: this destroys it
        inc     hl
        ld      d,(hl)
        inc     hl
        ld      a,(hl)
        ld      (un6_v),de
        ld      (un6_v+2),a
        ld      ix,pow10_tab
        ld      iy,num6_buf
        ld      a,6
        ld      (un6_n),a
un6_dig:
        xor     a
        ld      (un6_d),a
un6_sub:
        ld      hl,(un6_v)
        ld      e,(ix+0)
        ld      d,(ix+1)
        or      a
        sbc     hl,de
        ld      a,(un6_v+2)
        sbc     a,(ix+2)
        jr      c,un6_done          ; it will not go: the digit is done
        ld      (un6_v),hl
        ld      (un6_v+2),a
        ld      hl,un6_d
        inc     (hl)
        jr      un6_sub
un6_done:
        ld      a,(un6_d)
        ld      (iy+0),a
        inc     iy
        ld      de,3
        add     ix,de
        ld      hl,un6_n
        dec     (hl)
        jr      nz,un6_dig
        ret

num6_buf:       ds      6
                db      GL_END

;  100000, 10000, 1000, 100, 10, 1 — three bytes each, low first
pow10_tab:
        db      #A0,#86,#01
        db      #10,#27,#00
        db      #E8,#03,#00
        db      #64,#00,#00
        db      #0A,#00,#00
        db      #01,#00,#00

un6_v:          db      0,0,0
un6_d:          db      0
un6_n:          db      0

; ----------------------------------------------------------------------------
;  ui_glyph — A = glyph index, C = x (always even), B = pen.
;
;  A glyph row is five pixels and every glyph starts on an even one, so in
;  Mode 0 it is exactly THREE WHOLE BYTES. That is the whole trick. The
;  strip used to be plotted a pixel at a time, and each pixel recomputed
;  y*80 + x/2 from scratch and then read-modify-wrote a nibble — about a
;  hundred and fifty T-states to set four bits, twenty-four characters of
;  it, three display frames for a status line that usually says exactly
;  what it said before.
;
;  Now the four possible pixel PAIRS are worked out once per glyph, already
;  in the right pen, and a row is three lookups and three stores with
;  nothing to compute. The bar is cleared to black first, so there is
;  nothing underneath to preserve: the byte IS the pen masked by the pixels
;  the glyph lights.
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
        push    hl
        pop     ix                  ; IX = this glyph's seven rows

        ld      a,c                 ; hud_buf + x/2, while C is still the x
        srl     a                   ; we were handed
        ld      e,a
        ld      d,0
        ld      hl,hud_buf
        add     hl,de
        ex      de,hl               ; DE = where the top row goes

;  The four possible pixel PAIRS. Writing whole bytes means writing the
;  glyph's BLANK pixels too, so a blank has to be the colour the bar was
;  cleared to — not zero. Zero is the sky pen, and it painted a rectangle
;  of it around every character.
        ld      a,b                 ; the pen, as a both-pixel Mode 0 byte
        ld      hl,mode0_pen_bytes
        add     a,l
        ld      l,a
        adc     a,h
        sub     l
        ld      h,a
        ld      c,(hl)              ; C = the pen
        ld      a,(mode0_pen_bytes+PEN_BLACK)
        ld      (ug_tab+0),a        ; neither pixel lit: leave the bar alone
        ld      b,a
        and     #AA                 ; left half of the background...
        ld      l,a
        ld      a,c
        and     #55                 ; ...and the pen in the right pixel
        or      l
        ld      (ug_tab+1),a
        ld      a,b
        and     #55
        ld      l,a
        ld      a,c
        and     #AA
        or      l
        ld      (ug_tab+2),a        ; left pixel only
        ld      a,c
        ld      (ug_tab+3),a        ; both
        ld      b,FONT_H
ug_row:
        ld      a,(ix+0)            ; five pixels, bit 4 leftmost
        inc     ix
        ld      c,a
        rrca
        rrca
        rrca
        and     3                   ; pixels 0 and 1
        ld      hl,ug_tab
        add     a,l
        ld      l,a
        ld      a,(hl)
        ld      (de),a
        inc     de
        ld      a,c
        rrca
        and     3                   ; pixels 2 and 3
        ld      hl,ug_tab
        add     a,l
        ld      l,a
        ld      a,(hl)
        ld      (de),a
        inc     de
        ld      a,c
        and     1
        add     a,a                 ; pixel 4, and the gap beside it
        ld      hl,ug_tab
        add     a,l
        ld      l,a
        ld      a,(hl)
        ld      (de),a
        ld      hl,HUD_STRIDE-2     ; ...and on to the next scanline
        add     hl,de
        ex      de,hl
        djnz    ug_row
        ret

        align   4                   ; so ug_tab+3 cannot cross a page and
ug_tab: ds      4                   ; the index can be a plain ADD to L

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
