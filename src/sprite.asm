; ============================================================================
;  FURIOUS FOWLS — sprite.asm
;  The masked Mode 0 blitter, and the three lookup tables it runs on.
;
;  Art is nibble packed: one byte, two pens, high nibble is the left pixel.
;  Pen 0 is transparent. np2data turns a byte into the Mode 0 pixel pair;
;  np2mask turns it into the AND-mask that leaves the background alone
;  wherever the pen was 0. So a row of sprite is
;
;      screen = (screen AND mask) OR data
;
;  SPRITES LAND ON EVEN PIXELS. A Mode 0 byte interleaves its two pixels
;  plane by plane — bits 7,3,5,1 are the left pixel, 6,2,4,0 the right — so
;  moving an image one pixel sideways is NOT a bit shift. It is
;
;      out[i] = ((in[i] AND #AA) >> 1) OR ((in[i-1] AND #55) << 1)
;
;  which is two masks, two rotates and a carried byte for every byte of
;  every row, on top of the two table lookups already there. On a 16x32
;  sprite that is most of a video frame, every frame, for a half-pixel of
;  precision in a mode whose pixels are already four screen pixels wide and
;  whose camera pans in steps of four.
;
;  So x is rounded down to even and the blitter has one path. Blocks and
;  pigs are grid-aligned and even anyway; the bird gives up a pixel of
;  horizontal precision and nobody can see it, because it is travelling
;  five or six pixels a frame when it matters.
; ============================================================================

; ----------------------------------------------------------------------------
;  spr_init — build np2data / np2mask / np2nib for all 256 art bytes.
;  Generated rather than shipped: 768 bytes of table for ~40 bytes of code.
; ----------------------------------------------------------------------------
spr_init:
        ld      b,0                 ; B = the art byte, all 256 of them
si_byte:
        ld      a,b
        rrca
        rrca
        rrca
        rrca
        and     #0F
        ld      c,a                 ; C = left pen
        ld      a,b
        and     #0F
        ld      e,a                 ; E = right pen

        ld      a,c                 ; ---- data: the Mode 0 pixel pair
        call    pen_byte
        and     #AA                 ; left-pixel bits
        ld      d,a
        ld      a,e
        call    pen_byte
        and     #55                 ; right-pixel bits
        or      d
        ld      hl,NP2DATA
        ld      l,b
        ld      (hl),a

        ld      a,c                 ; ---- mask: 1 wherever the pen is 0
        or      a
        ld      a,0
        jr      nz,si_m1
        ld      a,#AA
si_m1:
        ld      d,a
        ld      a,e
        or      a
        ld      a,d
        jr      nz,si_m2
        or      #55
si_m2:
        ld      hl,NP2MASK
        ld      l,b
        ld      (hl),a

        ld      a,c                 ; ---- nib: the same, one nibble per pen
        or      a
        ld      a,0
        jr      nz,si_n1
        ld      a,#F0
si_n1:
        ld      d,a
        ld      a,e
        or      a
        ld      a,d
        jr      nz,si_n2
        or      #0F
si_n2:
        ld      hl,NP2NIB
        ld      l,b
        ld      (hl),a

        inc     b
        jr      nz,si_byte
        ret

pen_byte:                           ; A = pen -> A = both-pixel Mode 0 byte
        push    hl
        ld      hl,mode0_pen_bytes
        add     a,l
        ld      l,a
        adc     a,h
        sub     l
        ld      h,a
        ld      a,(hl)
        pop     hl
        ret

; ============================================================================
;  spr_blit — draw a sprite, clipped to the camera window and the play area.
;
;  In: (sp_art) nibble-packed art, top-left first, (sp_w) bytes per row
;      (sp_x) world x, signed        (sp_y) world y, signed
;      (sp_h) rows
;  The art pointer and row count are consumed locally; the caller's copies
;  are untouched.
; ============================================================================
spr_blit:
        ld      hl,(sp_art)
        ld      (sb_src),hl
        ld      a,(sp_h)
        ld      (sb_rows),a

; ---- vertical clip ---------------------------------------------------------
        ld      hl,(sp_y)
        bit     7,h
        jr      nz,sb_above
        ld      a,h
        or      a
        ret     nz                  ; y >= 256: below the world
        ld      a,l
        cp      SCREEN_LINES
        ret     nc
        cp      PLAY_TOP
        jr      nc,sb_ytop_ok
sb_above:
        ; skip (PLAY_TOP - y) rows of art
        ld      de,PLAY_TOP
        ex      de,hl
        or      a
        sbc     hl,de               ; HL = PLAY_TOP - y
        ld      a,h
        or      a
        ret     nz                  ; more than 255 rows above: forget it
        ld      a,l
        ld      b,a
        ld      c,a
        ld      a,(sb_rows)
        sub     c
        ret     c
        ret     z
        ld      (sb_rows),a
        ld      a,(sp_w)            ; art += skipped * bytes-per-row
        ld      e,a
        ld      d,0
        ld      hl,(sb_src)
sb_skip:
        add     hl,de
        djnz    sb_skip
        ld      (sb_src),hl
        ld      a,PLAY_TOP
        jr      sb_ystore
sb_ytop_ok:
        ld      a,l
sb_ystore:
        ld      (sb_y),a
        ld      c,a                 ; clip the bottom: y + rows <= 200
        ld      a,(sb_rows)
        add     a,c
        jr      c,sb_ybot
        cp      SCREEN_LINES+1
        jr      c,sb_yok
sb_ybot:
        ld      a,SCREEN_LINES
        sub     c
        ret     z
        ret     c
        ld      (sb_rows),a
sb_yok:

; ---- horizontal clip, in world BYTES (two pixels each) ---------------------
;  Working in bytes rather than pixels keeps every comparison 16-bit-clean
;  and lands directly on the units the ring walker steps in.
        ld      hl,(sp_x)
        sra     h                   ; bx = floor(x / 2): the world byte the
        rr      l                   ; sprite starts in. The odd pixel is
        ld      (sb_bx),hl          ; simply dropped — see the header.

        ld      a,(sp_w)
        ld      (sb_nb),a           ; bytes the row occupies

        ld      a,(cam_x)           ; the window, in world bytes
        ld      l,a
        ld      h,0
        add     hl,hl               ; wlb = cam_x * 2
        ld      (sb_wlb),hl

        ld      de,(sb_bx)          ; i0 = wlb - bx, floored at zero
        or      a
        sbc     hl,de
        bit     7,h
        jr      z,sb_i0_pos
        ld      hl,0
sb_i0_pos:
        ld      a,h
        or      a
        ret     nz                  ; more than 255 bytes off to the left
        ld      a,l
        ld      c,a
        ld      a,(sb_nb)
        cp      c
        ret     c                   ; nothing of it reaches the window
        ret     z
        ld      a,c
        ld      (sb_i0),a

        ld      hl,(sb_wlb)         ; i1 = min(nb - 1, wlb + 79 - bx)
        ld      de,SCREEN_BYTES_PER_LINE-1
        add     hl,de
        ld      de,(sb_bx)
        or      a
        sbc     hl,de
        ret     m                   ; it starts right of the window
        ld      a,h
        or      a
        ld      a,l
        jr      z,sb_i1_small
        ld      a,#FF               ; way off: the sprite's own width wins
sb_i1_small:
        ld      c,a
        ld      a,(sb_nb)
        dec     a
        cp      c
        jr      c,sb_i1_ok
        ld      a,c
sb_i1_ok:
        ld      hl,sb_i0            ; nblit = i1 - i0 + 1
        sub     (hl)
        ret     c
        inc     a
        ld      (sb_nblit),a

        ld      hl,(sb_bx)          ; the first world byte we write
        ld      a,(sb_i0)
        ld      e,a
        ld      d,0
        add     hl,de
        ld      a,l
        ld      (sb_byte0),a

; ---- and now the rows ------------------------------------------------------
sb_rows_go:
        ld      a,(sb_y)
        ld      c,a
        call    sb_addr             ; HL = VRAM of (sb_byte0, y)
        ld      (sb_addr_v),hl
;  The row loop keeps the ROW BUFFER in HL and video RAM in DE, so both the
;  mask and the data are plain (hl) reads at 7 T-states instead of indexed
;  ones at 19. On a 16-pixel sprite thirty-two rows deep that difference is
;  most of a video frame, which is why the buffer holds interleaved
;  (mask, data) pairs rather than two separate runs.
sb_row:
        call    spr_rowbuild        ; art row -> interleaved mask/data pairs
        ld      hl,sp_rowbuf
        ld      a,(sb_i0)
        add     a,a                 ; two bytes per pixel-pair
        ld      e,a
        ld      d,0
        add     hl,de
        ld      de,(sb_addr_v)
        ld      a,(sb_nblit)
        ld      b,a
sb_pix:
        ld      a,(de)
        and     (hl)                ; mask: keep the background
        inc     hl
        or      (hl)                ; data: the sprite's pens
        inc     hl
        ld      (de),a
        inc     de                  ; next byte, with the ring fold
        ld      a,e
        or      a
        jr      nz,sb_pixnext
        ld      a,d
        and     7
        jr      nz,sb_pixnext
        ld      a,d
        sub     8
        ld      d,a
sb_pixnext:
        djnz    sb_pix

        ld      a,(sb_rows)
        dec     a
        ld      (sb_rows),a
        ret     z
        ld      a,(sb_y)
        inc     a
        ld      (sb_y),a
        ld      c,a
        and     7
        jr      z,sb_newrow
        ld      hl,(sb_addr_v)      ; same char row: exactly +#800
        ld      a,h
        add     a,8
        ld      h,a
        ld      (sb_addr_v),hl
        jr      sb_row
sb_newrow:
        call    sb_addr
        ld      (sb_addr_v),hl
        jr      sb_row

; ---- sb_addr — C = line -> HL = VRAM address of world byte (sb_byte0) ------
sb_addr:
        ld      a,(sb_byte0)
        srl     a
        ld      d,a                 ; char column
        ld      e,c
        push    bc
        call    world_to_screen
        pop     bc
        ld      a,(sb_byte0)
        bit     0,a
        ret     z
        inc     l                   ; odd byte of the char; a char base is
        ret                         ; always even, so this cannot carry

; ============================================================================
;  spr_rowbuild — one art row -> sp_rowbuf: data at +0, mask at +10.
;  For an odd x the whole run is rotated right one bit, which moves the
;  picture one Mode 0 pixel; the mask chain shifts a 1 in at the left so
;  the pixel that falls off the front keeps its background.
; ============================================================================
;  Both sprite kinds are sixteen pixels wide — eight art bytes — so the row
;  build is unrolled rather than counted. That frees BC to hold the output
;  pointer (LD (BC),A is 7 T-states; the indexed form is 19) and removes the
;  loop overhead entirely, which on a thirty-two row sprite is worth having.
        assert  CR_BYTES_PER_ROW == 8 && BLK_BYTES_PER_ROW == 8
SPR_W           equ 8

; ============================================================================
;  spr_rowbuild — one art row -> sp_rowbuf as interleaved (mask, data) pairs.
;  Unrolled rather than counted: both sprite kinds are eight art bytes wide,
;  so the count is a constant and BC is free to hold the output pointer
;  (LD (BC),A is 7 T-states; the indexed form is 19). np2mask and np2data sit
;  on consecutive pages on purpose — once L holds the art byte, moving from
;  one table to the other is a single INC D.
; ============================================================================
spr_rowbuild:
        ld      hl,(sb_src)
        ld      bc,sp_rowbuf
        repeat  SPR_W
        ld      e,(hl)
        ld      d,NP2MASK/256
        ld      a,(de)
        ld      (bc),a
        inc     bc
        inc     d
        ld      a,(de)
        ld      (bc),a
        inc     bc
        inc     hl
        rend
        ld      (sb_src),hl
        ret

; ----------------------------------------------------------------------------
;  blitter state
; ----------------------------------------------------------------------------
sb_src:         dw      0
sb_bx:          dw      0
sb_wlb:         dw      0
sb_addr_v:      dw      0
sb_rows:        db      0
sb_y:           db      0
sb_nb:          db      0
sb_i0:          db      0
sb_nblit:       db      0
sb_byte0:       db      0
