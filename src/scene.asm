; ============================================================================
;  FURIOUS FOWLS — scene.asm
;  The background: sky, the flat turf, and the big scenery.
;
;  Everything the camera shows is produced one WORLD CHAR COLUMN at a time
;  (4 Mode 0 pixels wide, 200 lines tall) into colbuf, and colbuf is then
;  pushed into the ring by video.asm. That single primitive serves three
;  jobs: the initial fill, the scroll seam, and erasing a sprite (which is
;  just "rebuild these few columns over these few lines").
;
;  colbuf holds ART bytes — two 4-bit pens per byte — not Mode 0 bytes.
;  Compositing scenery over sky is then a nibble operation, and the single
;  conversion to Mode 0 happens once per byte on the way into video RAM.
;
;  Scenery is read straight out of its run-length stream. A 32x64 cell is
;  stored as eight independent 4-pixel-wide strips, so the column renderer
;  reads exactly the strip it needs; and because a run of forty identical
;  rows of sky is ONE iteration, the compression makes this faster than
;  reading a flat bitmap would be, not slower.
; ============================================================================

; ----------------------------------------------------------------------------
;  scene_init — build bg_template, the sky-and-turf column that every
;  world column starts from. The ground is flat, so this is the same for
;  all 80 columns and is worth building once.
; ----------------------------------------------------------------------------
scene_init:
        ld      hl,bg_template      ; sky above the turf line
        ld      de,bg_template+1
        ld      bc,GROUND_Y*2-1
        ld      (hl),0
        ldir
        ld      hl,bg_template+GROUND_Y*2
        ld      de,turf_strata
si_band:
        ld      a,(de)              ; band height in scanlines
        or      a
        ret     z
        inc     de
        ld      b,a
        ld      a,(de)              ; the band's art byte (both pens equal)
        inc     de
si_row:
        ld      (hl),a
        inc     hl
        ld      (hl),a
        inc     hl
        djnz    si_row
        jr      si_band

;  Four strata down from the grass. The two brown seams break up what is
;  otherwise a big flat slab of orange.
turf_strata:
        db      4,  #66             ; bright grass
        db      4,  #77             ; roots
        db      10, #44             ; dirt
        db      2,  #BB             ; a seam of clay
        db      6,  #44
        db      2,  #BB
        db      4,  #44
        db      0
        assert  SCREEN_LINES-GROUND_Y == 4+4+10+2+6+2+4

; ============================================================================
;  scene_build — compose one world char column into colbuf, for the lines
;  (sb_y0) .. (sb_y0)+(sb_n)-1.  In: A = world char column (0..79).
; ============================================================================
scene_build:
        ld      (sb_col),a
        ld      a,(sb_n)
        or      a
        ret     z
        ld      l,a                 ; two bytes of art per scanline
        ld      h,0
        add     hl,hl
        ld      (sb_cnt),hl
        ld      a,(sb_y0)
        ld      l,a
        ld      h,0
        add     hl,hl               ; the window's byte offset
        push    hl
        ld      de,colbuf
        add     hl,de
        ex      de,hl               ; DE = colbuf + offset
        pop     hl
        ld      bc,bg_template
        add     hl,bc               ; HL = bg_template + offset
        ld      bc,(sb_cnt)
        ldir
        ; fall through: whatever the scenery puts on top

; ----------------------------------------------------------------------------
;  scene_overlay — composite every scenery cell that covers (sb_col).
; ----------------------------------------------------------------------------
scene_overlay:
        ld      a,(scen_count)
        or      a
        ret     z
        ld      b,a
        ld      ix,scen_tab
so_loop:
        push    bc
        call    scene_cell
        pop     bc
        ld      de,SCEN_ENT
        add     ix,de
        djnz    so_loop
        ret

; ----------------------------------------------------------------------------
;  scene_cell — IX = (cell id, char column, top line). Composites the one
;  strip of this cell that lands on (sb_col), if any.
; ----------------------------------------------------------------------------
scene_cell:
        ld      a,(sb_col)
        sub     (ix+1)
        ret     c                   ; column is left of the cell
        cp      SC_STRIPS
        ret     nc                  ; ...or right of it
        ld      e,a                 ; E = strip index 0..7

        ld      a,(sb_y0)           ; and does it reach the line window?
        ld      c,a                 ; Erases ask for thirty-odd lines at a
        ld      a,(sb_n)            ; time, so most cells miss entirely and
        add     a,c                 ; are not worth walking a run stream for.
        ld      b,a                 ; B = window end
        ld      a,(ix+2)
        cp      b
        ret     nc                  ; the cell starts below the window
        add     a,SC_H
        jr      c,sc_ytest_ok       ; (wrapped past 255: it certainly reaches)
        cp      c
        ret     c                   ; the cell ends above the window
sc_ytest_ok:
        ld      a,(ix+0)
        add     a,a
        add     a,a
        add     a,a                 ; cell * SC_STRIPS
        add     a,e
        ld      l,a
        ld      h,0
        add     hl,hl               ; a word per entry
        ld      de,scenery_ofs
        add     hl,de
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        ld      hl,scenery_rle
        add     hl,de               ; HL = the strip's run stream

        ld      a,(ix+2)
        ld      (so_row),a          ; where its first row lands
        ld      a,SC_H
        ld      (so_left),a
so_run:
        ld      a,(hl)              ; run length in scanlines
        inc     hl
        ld      (so_cnt),a
        ld      a,(hl)              ; the run's two art bytes
        inc     hl
        ld      (so_or0+1),a
        ld      c,a
        ld      a,(hl)
        inc     hl
        ld      (so_or1+1),a
        or      c
        jr      z,so_advance        ; a run of pure transparency: skip it
        push    hl
        call    so_paint
        pop     hl
so_advance:
        ld      a,(so_cnt)
        ld      c,a
        ld      a,(so_row)
        add     a,c
        ld      (so_row),a
        ld      a,(so_left)
        sub     c
        ld      (so_left),a
        ret     z                   ; the whole cell has been placed
        ret     c                   ; (a malformed stream cannot run away)
        jr      so_run

; ----------------------------------------------------------------------------
;  so_paint — lay (so_cnt) rows of the current run into colbuf, clipped to
;  the window scene_build was asked for. The two art bytes and their
;  keep-masks are folded into the loop as immediates: the run is constant,
;  so this costs four stores instead of four lookups per row.
; ----------------------------------------------------------------------------
so_paint:
        ld      a,(so_or0+1)        ; keep-mask for byte 0
        ld      l,a
        ld      h,NP2NIB/256
        ld      a,(hl)
        ld      (so_and0+1),a
        ld      a,(so_or1+1)
        ld      l,a
        ld      a,(hl)
        ld      (so_and1+1),a

        ld      a,(sb_y0)           ; lo = max(row, sb_y0)
        ld      c,a                 ; C = window first line
        ld      b,a
        ld      a,(sb_n)
        add     a,b
        ld      b,a                 ; B = window end (exclusive)
        ld      a,(so_row)
        cp      c
        jr      nc,sp_lo_ok
        ld      a,c
sp_lo_ok:
        ld      e,a                 ; E = first line to paint
        ld      a,(so_row)
        ld      d,a
        ld      a,(so_cnt)
        add     a,d
        jr      c,sp_hi_clamp       ; run ends past line 255: clamp
        cp      b
        jr      c,sp_hi_ok
sp_hi_clamp:
        ld      a,b
sp_hi_ok:
        sub     e                   ; count = hi - lo
        ret     z
        ret     c
        ld      b,a                 ; B = rows to paint
        ld      l,e
        ld      h,0
        add     hl,hl
        ld      de,colbuf
        add     hl,de               ; HL = colbuf + lo*2
sp_row:
        ld      a,(hl)
so_and0: and    #00
so_or0:  or     #00
        ld      (hl),a
        inc     hl
        ld      a,(hl)
so_and1: and    #00
so_or1:  or     #00
        ld      (hl),a
        inc     hl
        djnz    sp_row
        ret

so_row:         db      0
so_cnt:         db      0
so_left:        db      0
sb_cnt:         dw      0

; ============================================================================
;  redraw_rect — put the background back over a rectangle of the screen and
;  then re-lay everything that stands in it. This is the ONLY erase in the
;  game: sprites do not keep a backing store, they just ask for the world
;  to be rebuilt where they used to be.
;
;  In: (rr_col0) first world char column, (rr_ncol) columns,
;      (rr_y0) first line, (rr_n) lines.
; ============================================================================
redraw_rect:
        ld      a,(rr_n)
        or      a
        ret     z
;  CLAMP TO THE PLAY AREA. A piece part way through a cell can sit at line
;  182, and a tilted beam's box is forty lines tall — which asks for lines
;  past the bottom of the world. That is not merely wasted work: colbuf is
;  exactly two hundred lines long and bg_template is the very next thing in
;  memory, so an over-long window runs the copy straight off the end of one
;  into the other, and then pushes the sky it finds there out to the ring.
        ld      c,a
        ld      a,(rr_y0)
        cp      SCREEN_LINES
        ret     nc                  ; starts below the world entirely
        add     a,c
        jr      c,rr_clamp
        cp      SCREEN_LINES+1
        jr      c,rr_span_ok
rr_clamp:
        ld      a,SCREEN_LINES
        ld      hl,rr_y0
        sub     (hl)
        ld      (rr_n),a
rr_span_ok:
        ld      a,(rr_ncol)
        or      a
        ret     z
        ld      b,a
        ld      a,(rr_col0)
rr_loop:
        push    af
        push    bc
        call    rr_column
        pop     bc
        pop     af
        inc     a
        djnz    rr_loop
        jp      rr_restack

; ---- one column, if the camera can actually see it --------------------------
rr_column:
        ld      c,a
        ld      a,(cam_x)
        ld      b,a
        ld      a,c
        sub     b
        ret     c                   ; left of the window
        cp      VIEW_CHARS
        ret     nc                  ; right of it
        ld      a,c
        cp      WORLD_CHARS
        ret     nc                  ; outside the world entirely
        ld      hl,(rr_y0)          ; rr_y0 and rr_n are adjacent bytes
        ld      (sb_y0),hl
        ld      a,c
        push    bc
        call    scene_build
        pop     bc
        ld      a,c
        ld      (dcr_col),a
        ld      hl,(rr_y0)
        ld      (dcr_y),hl
        jp      draw_col_range

; ---- and everything standing in the rectangle -------------------------------
;  Blocks and pigs are cheap to test and idempotent to draw, so the rule is
;  simply "if your bounding box touches the rectangle, draw yourself again".
;  Drawing slightly outside the rectangle is harmless — it paints the same
;  pixels that were already there.
; ----------------------------------------------------------------------------
rr_restack:
        call    blocks_draw_rect
        call    pigs_draw_rect
        jp      shot_draw_rect
