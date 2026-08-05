; ============================================================================
;  FURIOUS FOWLS — video.asm
;  CRTC hardware scrolling, the row-address LUT, and the palette.
;
;  THEORY OF OPERATION (the same ring trick CreepersCPC uses)
;  ---------------------------------------------------------
;  The CRTC screen-start offset (R12/R13, "MA9..0") makes the 16K of video
;  RAM behave as a RING of 1024 characters per scanline block. A frame
;  shows 40x25 = 1000 consecutive ring chars starting at offset S:
;
;      display char (row r, col c)  =  ring[(S + 40*r + c) AND 1023]
;
;  The world is 80 chars wide and the camera S slides 0..40. Because the
;  visible window covers world column x at ring index
;  (S + 40r + (x-S)) = 40r + x, the world->ring mapping does NOT depend on
;  S. So one primitive maintains the entire engine:
;
;      draw_world_column(x): for r in 0..24: ring[(40r+x) AND 1023] <- world(r,x)
;
;      initial fill : draw columns S .. S+39
;      scroll right : S++ ; draw_world_column(S+39)
;      scroll left  : S-- ; draw_world_column(S)
;
;  Ring cell (r, x) aliases (r-1, x+40), which is harmless: the window is
;  exactly 40 chars, so x and x+40 can never both be on screen.
;
;  Scroll granularity is 1 CRTC char = 4 Mode 0 pixels, programmed straight
;  after VSYNC so the CRTC latches it cleanly at the top of the frame on
;  every CRTC type.
; ============================================================================

; ----------------------------------------------------------------------------
;  crtc_init — program R0-R13 for the standard 320x200 frame at #C000
; ----------------------------------------------------------------------------
crtc_init:
        ld      hl,crtc_table
        xor     a
crtc_next:
        ld      b,#BC
        out     (c),a
        ld      b,#BD
        ld      e,(hl)
        out     (c),e
        inc     hl
        inc     a
        cp      crtc_table_end-crtc_table
        jr      nz,crtc_next
        ret

crtc_table:
        db      63                  ; R0  horizontal total (chars-1)
        db      40                  ; R1  horizontal displayed. NOTE: the
                                    ;     6845 advances each char row's
                                    ;     start by R1, so R1 IS the ring
                                    ;     row stride — changing it skews
                                    ;     the whole screen into stairs
        db      46                  ; R2  hsync position
        db      #8E                 ; R3  vsync height / hsync width
        db      38                  ; R4  vertical total (char rows-1)
        db      0                   ; R5  vertical total adjust
        db      25                  ; R6  vertical displayed
        db      30                  ; R7  vsync position
        db      0                   ; R8  no interlace
        db      7                   ; R9  scanlines per char row - 1
        db      0                   ; R10 cursor (unused)
        db      0                   ; R11 cursor (unused)
        db      CRTC_R12_BASE       ; R12 display start high -> page #C000
        db      #00                 ; R13 display start low
crtc_table_end:

; ----------------------------------------------------------------------------
;  crtc_set_offset — program R12/R13 from cam_x (0..CAM_MAX).
;  Call right after wait_vsync.
; ----------------------------------------------------------------------------
crtc_set_offset:
        ld      bc,CRTC_SEL
        ld      a,13
        out     (c),a
        inc     b
        ld      a,(cam_x)
        out     (c),a
        dec     b
        ld      a,12
        out     (c),a
        inc     b
        ld      a,CRTC_R12_BASE     ; cam_x <= 40 never carries into R12
        out     (c),a
        ret

; ----------------------------------------------------------------------------
;  wait_vsync — block until the START of the next VSYNC pulse
;  (edge-detected, so exactly one call per frame)
; ----------------------------------------------------------------------------
wait_vsync:
        ld      bc,PPI_PORT_B
wv_end:
        in      a,(c)
        rra
        jr      c,wv_end
wv_start:
        in      a,(c)
        rra
        jr      nc,wv_start
        ret

; ----------------------------------------------------------------------------
;  palette_load — HL = 17 bytes (16 pens then the border)
; ----------------------------------------------------------------------------
palette_load:
        ld      bc,GA_PORT
        xor     a
pal_next:
        out     (c),a               ; select pen
        ld      e,(hl)
        out     (c),e               ; set its colour
        inc     hl
        inc     a
        cp      16
        jr      nz,pal_next
        ld      a,GA_SEL_BORDER
        out     (c),a
        ld      e,(hl)
        out     (c),e
        ret

palette_black:
        ld      hl,palette_dark
        jr      palette_load

palette_apply:
        ld      hl,palette_game
        jr      palette_load

; ----------------------------------------------------------------------------
;  The palette. Index = pen = the art palette index in tools/artlib.py, so
;  a pixel drawn 'orange' in the spritesheet is orange on the CPC.
; ----------------------------------------------------------------------------
palette_game:
        db      HW_SKY_BLUE         ; 0  sky / sprite transparency
        db      HW_BLACK            ; 1  outline
        db      HW_BRIGHT_WHITE     ; 2  white
        db      HW_BRIGHT_RED       ; 3  red
        db      HW_ORANGE           ; 4  orange / wood
        db      HW_BRIGHT_YELLOW    ; 5  yellow / beak
        db      HW_BRIGHT_GREEN     ; 6  bright green / pig / grass
        db      HW_GREEN            ; 7  dark green / foliage
        db      HW_BRIGHT_CYAN      ; 8  cyan / ice
        db      HW_BLUE             ; 9  blue
        db      HW_WHITE            ; 10 grey / stone
        db      HW_RED              ; 11 brown / trunk
        db      HW_PINK             ; 12 pink
        db      HW_PASTEL_YELLOW    ; 13 sand
        db      HW_PASTEL_BLUE      ; 14 pale blue
        db      HW_MAGENTA          ; 15 purple
        db      HW_SKY_BLUE         ; border = sky

palette_dark:
        repeat  17
        db      HW_BLACK
        rend

; ----------------------------------------------------------------------------
;  set_border — E = hardware colour
; ----------------------------------------------------------------------------
set_border:
        ld      bc,GA_PORT
        ld      a,GA_SEL_BORDER
        out     (c),a
        out     (c),e
        ret

; ============================================================================
;  ROW-ADDRESS LOOKUP TABLE
;      line_lut[y] = #C000 + (y AND 7)*#800 + (y >> 3)*80
;  This is the VRAM address of scanline y at world char x = 0. Because the
;  world->ring mapping ignores the scroll offset, the table is STABLE while
;  scrolling — one table, no double buffering.
; ============================================================================
gen_line_lut:
        ld      hl,line_lut
        ld      de,SCREEN_BASE
        ld      b,SCREEN_CHAR_ROWS
gll_row:
        push    bc
        push    de
        ld      b,8
gll_scan:
        ld      (hl),e
        inc     hl
        ld      (hl),d
        inc     hl
        ld      a,d
        add     a,#08               ; +#800: next scanline of this char row
        ld      d,a
        djnz    gll_scan
        pop     de
        ld      a,e                 ; next char row: +80 bytes
        add     a,SCREEN_BYTES_PER_LINE
        ld      e,a
        jr      nc,gll_nc
        inc     d
gll_nc:
        pop     bc
        djnz    gll_row
        ret

; ----------------------------------------------------------------------------
;  world_to_screen — D = world char x (0..79), E = line y (0..199)
;                 -> HL = VRAM address of that char's LEFT byte
;
;  HL = #C000 | ((y AND 7)<<11) | ((80*(y>>3) + 2*x) AND #7FF)
;  The AND #7FF folds the 1024-char ring wrap.
; ----------------------------------------------------------------------------
world_to_screen:
        ld      a,e
        rrca
        rrca
        rrca
        and     #1F                 ; char row 0..24
        ld      l,a
        ld      h,0
        add     hl,hl
        add     hl,hl
        add     hl,hl
        add     hl,hl               ; x16
        ld      b,h
        ld      c,l
        add     hl,hl
        add     hl,hl               ; x64
        add     hl,bc               ; x80 = row offset
        ld      a,d
        add     a,a                 ; 2*x
        ld      c,a
        ld      b,0
        add     hl,bc
        ld      a,h
        cp      #08                 ; fold the ring wrap
        jr      c,wts_nofold
        sub     #08
        ld      h,a
wts_nofold:
        ld      a,e
        and     7
        add     a,a
        add     a,a
        add     a,a                 ; (y AND 7)<<3 -> A13..11
        or      #C0
        or      h
        ld      h,a
        ret

; ----------------------------------------------------------------------------
;  vram_next_byte — DE = VRAM address -> next byte, ring fold applied:
;  when the low 11 bits wrap to zero, step back one #800 block.
; ----------------------------------------------------------------------------
vram_next_byte:
        inc     de
        ld      a,e
        or      a
        ret     nz
        ld      a,d
        and     7
        ret     nz
        ld      a,d
        sub     8
        ld      d,a
        ret

; ============================================================================
;  draw_col_range — push part of a rendered column into its ring position.
;  In: (dcr_col) world char column, (dcr_y) first line, (dcr_n) line count.
;  Source is colbuf, which scene_build has already filled for those lines.
;
;  Within a char row consecutive scanlines are exactly +#800 apart, so the
;  address is only recomputed when the row changes — eight lines of work
;  per world_to_screen call.
; ============================================================================
draw_col_range:
        ld      a,(dcr_n)
        or      a
        ret     z
        ld      a,(dcr_y)
        ld      e,a
        ld      a,(dcr_col)
        ld      d,a
        call    world_to_screen     ; HL = VRAM. This CLOBBERS BC, so the
                                    ; line counter and the line number are
                                    ; set up afterwards, not before.
        ld      a,(dcr_y)
        ld      c,a                 ; C = the scanline we are on
        add     a,a
        ld      e,a
        ld      d,0
        ld      iy,colbuf
        add     iy,de               ; IY = colbuf + y*2
        ld      a,(dcr_n)
        ld      b,a                 ; B = lines to go
dcr_loop:
        ld      d,NP2DATA/256       ; colbuf is ART; video RAM is Mode 0
        ld      e,(iy+0)
        ld      a,(de)
        ld      (hl),a
        inc     l                   ; the char's right byte: a char base is
        ld      e,(iy+1)            ; always even, so this cannot carry
        ld      a,(de)
        ld      (hl),a
        dec     l
        inc     iy
        inc     iy
        inc     c                   ; next scanline
        ld      a,c
        and     7
        jr      z,dcr_wrap
        ld      a,h                 ; same char row: +#800
        add     a,8
        ld      h,a
        djnz    dcr_loop
        ret
dcr_wrap:
        djnz    dcr_recalc
        ret
dcr_recalc:
        push    bc
        ld      e,c
        ld      a,(dcr_col)
        ld      d,a
        call    world_to_screen
        pop     bc
        jr      dcr_loop

; ----------------------------------------------------------------------------
;  draw_world_column — A = world char column. Renders it and pushes the
;  whole 200 lines out. Used by the initial fill and by both scroll seams.
; ----------------------------------------------------------------------------
draw_world_column:
        ld      (dcr_col),a
        xor     a
        ld      (dcr_y),a
        ld      (sb_y0),a
        ld      a,SCREEN_LINES
        ld      (dcr_n),a
        ld      (sb_n),a
        ld      a,(dcr_col)
        call    scene_build         ; sky, turf and scenery -> colbuf
        jp      draw_col_range

; ----------------------------------------------------------------------------
;  repaint_window — redraw all 40 visible columns
; ----------------------------------------------------------------------------
repaint_window:
        ld      a,(cam_x)
        ld      b,VIEW_CHARS
rp_loop:
        push    af
        push    bc
        call    draw_world_column
        pop     bc
        pop     af
        inc     a
        djnz    rp_loop
        ret

; ============================================================================
;  Single pixels and lines, in world space.
;
;  Everything else in the engine draws in rectangles, because rectangles are
;  what a blitter and an eraser can be fast about. The slingshot's elastic
;  is the exception: it is two lines that move every time the pull changes,
;  and there is no sensible sprite for it.
;
;  plot_px — HL = world x, A = line, (pp_pen) = the both-pixel Mode 0 byte.
;  Silently drops anything outside the camera window or the play area, so
;  callers need no clipping of their own.
; ============================================================================
plot_px:
        cp      SCREEN_LINES
        ret     nc
        cp      PLAY_TOP
        ret     c
        ld      (pp_y),a
        bit     7,h
        ret     nz                  ; negative x
        ld      (pp_x),hl
        srl     h
        rr      l
        srl     h
        rr      l                   ; world char column
        ld      a,h
        or      a
        ret     nz
        ld      c,l
        ld      a,(cam_x)
        ld      b,a
        ld      a,c
        sub     b
        ret     c                   ; left of the window
        cp      VIEW_CHARS
        ret     nc                  ; right of it
        ld      d,c
        ld      a,(pp_y)
        ld      e,a
        call    world_to_screen
        ld      a,(pp_x)
        bit     1,a
        jr      z,pp_even
        inc     l                   ; odd byte of the char; the base is even
pp_even:
        ld      a,(pp_x)
        rra                         ; bit 0 -> carry: which pixel of the byte
        ld      a,(pp_pen)
        jr      c,pp_right
        and     #AA
        ld      c,a
        ld      a,(hl)
        and     #55
        or      c
        ld      (hl),a
        ret
pp_right:
        and     #55
        ld      c,a
        ld      a,(hl)
        and     #AA
        or      c
        ld      (hl),a
        ret

; ----------------------------------------------------------------------------
;  draw_line — from (ln_x0, ln_y0) to (ln_x1, ln_y1) in (pp_pen), two
;  scanlines thick so it reads as a band rather than a hair.
;
;  Plain DDA stepped along the major axis, with the loop count FIXED at
;  major+1 before the first pixel. The textbook Bresenham with its
;  compare-against-the-endpoint exit is a trap here: get one sign wrong and
;  it never reaches the endpoint, and a line routine that does not terminate
;  takes the whole frame with it.
; ----------------------------------------------------------------------------
draw_line:
        ld      hl,(ln_x1)          ; dx and its direction
        ld      de,(ln_x0)
        or      a
        sbc     hl,de
        ld      a,1
        bit     7,h
        jr      z,dl_dxpos
        call    neg16
        ld      a,#FF
dl_dxpos:
        ld      (dl_sx),a
        ld      a,h
        or      a
        ret     nz                  ; longer than 255 px: not our business
        ld      a,l
        ld      (dl_dx),a

        ld      a,(ln_y1)           ; dy and its direction
        ld      c,a
        ld      a,(ln_y0)
        ld      b,a
        ld      a,c
        sub     b
        ld      c,1
        jr      nc,dl_dypos
        neg
        ld      c,#FF
dl_dypos:
        ld      (dl_dy),a
        ld      a,c
        ld      (dl_sy),a

        ld      hl,(ln_x0)          ; the running point
        ld      (dl_x),hl
        ld      a,(ln_y0)
        ld      (dl_y),a
        xor     a
        ld      (dl_err),a

        ld      a,(dl_dx)
        ld      hl,dl_dy
        cp      (hl)
        jr      c,dl_ymajor

; ---- x is the major axis ---------------------------------------------------
        inc     a
        ld      (dl_cnt),a
dlx_loop:
        call    dl_plot
        ld      hl,(dl_x)           ; one step along x
        ld      a,(dl_sx)
        call    dl_addsigned
        ld      (dl_x),hl
        ld      a,(dl_err)          ; err += dy; carry a step of y when it
        ld      hl,dl_dy            ; passes dx
        add     a,(hl)
        ld      hl,dl_dx
        cp      (hl)
        jr      c,dlx_noy
        sub     (hl)
        call    dl_stepy
dlx_noy:
        ld      (dl_err),a
        ld      hl,dl_cnt
        dec     (hl)
        jr      nz,dlx_loop
        ret

; ---- y is the major axis ---------------------------------------------------
dl_ymajor:
        ld      a,(dl_dy)
        inc     a
        ld      (dl_cnt),a
dly_loop:
        call    dl_plot
        call    dl_stepy
        ld      a,(dl_err)
        ld      hl,dl_dx
        add     a,(hl)
        ld      hl,dl_dy
        cp      (hl)
        jr      c,dly_nox
        sub     (hl)
        push    af
        ld      hl,(dl_x)
        ld      a,(dl_sx)
        call    dl_addsigned
        ld      (dl_x),hl
        pop     af
dly_nox:
        ld      (dl_err),a
        ld      hl,dl_cnt
        dec     (hl)
        jr      nz,dly_loop
        ret

dl_plot:
        ld      hl,(dl_x)
        ld      a,(dl_y)
        push    hl
        call    plot_px
        pop     hl
        ld      a,(dl_y)
        inc     a
        jp      plot_px

dl_stepy:                           ; preserves A across the y step
        push    af
        ld      a,(dl_y)
        ld      hl,dl_sy
        add     a,(hl)
        ld      (dl_y),a
        pop     af
        ret

dl_addsigned:                       ; HL += sign-extended A
        ld      e,a
        add     a,a
        sbc     a,a
        ld      d,a
        add     hl,de
        ret

pp_x:           dw      0
pp_y:           db      0
pp_pen:         db      0
ln_x0:          dw      0
ln_y0:          db      0
ln_x1:          dw      0
ln_y1:          db      0
dl_x:           dw      0
dl_y:           db      0
dl_dx:          db      0
dl_dy:          db      0
dl_sx:          db      0
dl_sy:          db      0
dl_err:         db      0
dl_cnt:         db      0

; ----------------------------------------------------------------------------
;  Mode 0 pixel packing: both pixels of a byte in the same pen.
;    left  pixel: pen bit0->b7, bit1->b3, bit2->b5, bit3->b1
;    right pixel: the same, one bit right (b6/b2/b4/b0)
; ----------------------------------------------------------------------------
mode0_pen_bytes:
        db      #00,#C0,#0C,#CC,#30,#F0,#3C,#FC
        db      #03,#C3,#0F,#CF,#33,#F3,#3F,#FF

; ----------------------------------------------------------------------------
;  video state
; ----------------------------------------------------------------------------
dcr_col:        db      0
dcr_y:          db      0
dcr_n:          db      0
line_lut:       ds      SCREEN_LINES*2
