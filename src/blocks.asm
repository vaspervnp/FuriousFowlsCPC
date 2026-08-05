; ============================================================================
;  FURIOUS FOWLS — blocks.asm
;  The forts: pieces on a 20x10 grid, and the collapse that brings them down.
;
;  WHY A GRID, AND WHY BEAMS
;  -------------------------
;  Rigid-body physics is not happening on a 4 MHz Z80, and it is not what
;  makes the genre work anyway. What makes it work is that structures LOSE
;  THEIR FOOTING: knock out a leg and everything above comes down on the
;  pigs. That is a cellular problem, not a physics one.
;
;  But a plank is not a row of cubes. A lintel over a doorway whose left
;  pillar is knocked out does not shed its left half — it TIPS over the
;  pillar it still has. So a run of plank cells is merged by the level
;  compiler into ONE beam, BLK_LEN cells wide, occupying that many grid
;  cells and falling as a single rigid object. Support is then judged at
;  its two ENDS: both held is stable, one held tips over that end, neither
;  is a free fall.
;
;  Tipping is drawn by stepping the beam's own cells down a constant number
;  of scanlines each and drawing them with a tilted copy of the tile (see
;  tools/gen_rot.py). The angles are chosen so that step is a whole number
;  of lines, which is what lets a multi-cell plank rotate convincingly
;  without a single line of trigonometry at runtime.
;
;  The sweep runs bottom row first: a piece can only fall into a cell the
;  one below has already vacated, so upward order lets a whole column start
;  moving in one frame. Pigs live in the same grid, so a falling wall
;  crushes them with no special-case code.
; ============================================================================

; ----------------------------------------------------------------------------
;  grid_at — B = column, C = row -> HL = that cell's address. Clobbers A, DE.
; ----------------------------------------------------------------------------
        assert  GRID_W == 20
grid_at:
        ld      l,c
        ld      h,0
        add     hl,hl
        add     hl,hl               ; row * 4
        ld      e,l
        ld      d,h
        add     hl,hl
        add     hl,hl               ; row * 16
        add     hl,de               ; row * 20
        ld      e,b
        ld      d,0
        add     hl,de
        ld      de,grid
        add     hl,de
        ret

; ----------------------------------------------------------------------------
;  block_ptr — E = index -> IX = its record. Clobbers A, DE, HL.
; ----------------------------------------------------------------------------
        assert  BLK_SIZE == 16
block_ptr:
        ld      d,0
        ld      hl,0
        add     hl,de
        add     hl,hl
        add     hl,hl
        add     hl,hl
        add     hl,hl
        ld      de,blocks
        add     hl,de
        push    hl
        pop     ix
        ret

; ----------------------------------------------------------------------------
;  block_index — IX = block -> A = its index
; ----------------------------------------------------------------------------
block_index:
        push    ix
        pop     hl
        ld      de,blocks
        or      a
        sbc     hl,de
        ld      b,4
bi_shift:
        srl     h
        rr      l
        djnz    bi_shift
        ld      a,l
        ret

blocks_reset:
        ld      hl,grid
        ld      de,grid+1
        ld      bc,GRID_SIZE-1
        ld      (hl),GRID_EMPTY
        ldir
        ld      hl,blocks
        ld      de,blocks+1
        ld      bc,MAX_BLOCKS*BLK_SIZE-1
        ld      (hl),BS_FREE
        ldir
        xor     a
        ld      (block_count),a
        ret

; ----------------------------------------------------------------------------
;  block_add — A = piece, B = column, C = row, (ba_len) = cells wide
; ----------------------------------------------------------------------------
block_add:
        ld      (ba_piece),a
        ld      a,(block_count)
        cp      MAX_BLOCKS
        ret     nc
        ld      e,a
        call    block_ptr
        ld      a,(ba_piece)
        ld      (ix+BLK_PIECE),a
        ld      (ix+BLK_STATE),BS_REST
        ld      (ix+BLK_COL),b
        ld      (ix+BLK_ROW),c
        ld      (ix+BLK_YOFF),0
        ld      (ix+BLK_VY),0
        ld      (ix+BLK_VY_I),0
        ld      (ix+BLK_TILT),TILT_NONE
        ld      (ix+BLK_TIPT),0
        ld      (ix+BLK_SHOVE),0
        ld      a,(ba_len)
        or      a
        jr      nz,ba_len_ok
        inc     a
ba_len_ok:
        ld      (ix+BLK_LEN),a
        call    block_hp_init
        ld      a,(block_count)
        call    block_claim
        ld      a,(block_count)
        inc     a
        ld      (block_count),a
        ret

; ----------------------------------------------------------------------------
;  block_claim / block_release — IX = block, A = the value to write.
;  A beam owns every cell it spans; that is what makes anything resting on
;  any part of it stay up, and what makes it crush the whole width below.
; ----------------------------------------------------------------------------
block_release:
        ld      a,GRID_EMPTY
block_claim:
        ld      (bc_val),a
        ld      b,(ix+BLK_COL)
        ld      c,(ix+BLK_ROW)
        ld      a,(ix+BLK_LEN)
        ld      (bc_n),a
bc_loop:
        push    bc
        call    grid_at
        ld      a,(bc_val)
        ld      (hl),a
        pop     bc
        inc     b
        ld      a,(bc_n)
        dec     a
        ld      (bc_n),a
        jr      nz,bc_loop
        ret

; ----------------------------------------------------------------------------
;  block_hp_init — IX = block. The piece's base strength scaled by the
;  level's material set; a long beam is proportionally tougher.
; ----------------------------------------------------------------------------
block_hp_init:
        ld      hl,blk_hp_table
        ld      a,(block_set)
        or      a
        jr      z,bhi_row
        ld      b,a
        ld      de,BLK_PIECES
bhi_add:
        add     hl,de
        djnz    bhi_add
bhi_row:
        ld      e,(ix+BLK_PIECE)
        ld      d,0
        add     hl,de
        ld      a,(hl)
        ld      c,a
        ld      b,(ix+BLK_LEN)      ; +25% of the base per extra cell
        dec     b
        jr      z,bhi_store
bhi_len:
        srl     c
        srl     c                   ; c/4
        add     a,c
        jr      c,bhi_max
        djnz    bhi_len
        jr      bhi_store
bhi_max:
        ld      a,#FF
bhi_store:
        ld      (ix+BLK_HP),a
        ret

; ============================================================================
;  The tilted art, built once per level
; ============================================================================
        assert  BLK_BYTES == 128
        assert  CELL_PX == 16

; ---- rot_build — apply the four rot_map tables to this level's ten pieces --
rot_build:
        xor     a
        ld      (rb_piece),a
rb_ploop:
        ld      a,(rb_piece)        ; IX = the upright source tile
        call    block_art_base
        push    hl
        pop     ix
        xor     a
        ld      (rb_tilt),a
rb_tloop:
        ld      a,(rb_tilt)         ; HL = rot_map + tilt*256
        ld      h,a
        ld      l,0
        ld      de,rot_map
        add     hl,de
        ld      a,(rb_piece)        ; DE = rot_art + (piece*4 + tilt)*128
        add     a,a
        add     a,a
        ld      c,a
        ld      a,(rb_tilt)
        add     a,c
        ld      e,a
        ld      d,0
        ld      b,7
rb_shift:
        ex      de,hl
        add     hl,hl
        ex      de,hl
        djnz    rb_shift
        push    hl
        ld      hl,rot_art
        add     hl,de
        ex      de,hl
        pop     hl
        ld      a,BLK_BYTES
        ld      (rb_cnt),a
rb_byte:
        ld      a,(hl)              ; two destination pixels per byte
        inc     hl
        call    rb_pen
        rlca
        rlca
        rlca
        rlca
        ld      c,a
        ld      a,(hl)
        inc     hl
        call    rb_pen
        or      c
        ld      (de),a
        inc     de
        ld      a,(rb_cnt)
        dec     a
        ld      (rb_cnt),a
        jr      nz,rb_byte
        ld      a,(rb_tilt)
        inc     a
        ld      (rb_tilt),a
        cp      ROT_TILTS
        jr      c,rb_tloop
        ld      a,(rb_piece)
        inc     a
        ld      (rb_piece),a
        cp      BLK_PIECES
        jr      c,rb_ploop
        ret

; ---- rb_pen — A = source pixel index (#FF = transparent) -> A = pen --------
rb_pen:
        cp      #FF
        jr      z,rb_transp
        push    hl
        push    de
        push    bc
        ld      c,a
        ld      l,a
        ld      h,0
        srl     l                   ; two pixels per art byte
        push    ix
        pop     de
        add     hl,de
        ld      a,(hl)
        bit     0,c
        jr      nz,rb_lo
        rrca
        rrca
        rrca
        rrca
rb_lo:
        and     #0F
        pop     bc
        pop     de
        pop     hl
        ret
rb_transp:
        xor     a
        ret

; ---- block_art_base — A = piece -> HL = its upright tile in this set -------
block_art_base:
        ld      c,a
        ld      hl,0
        ld      a,(block_set)
        or      a
        jr      z,bab_piece
        ld      b,a
        ld      de,BLK_PIECES
bab_set:
        add     hl,de
        djnz    bab_set
bab_piece:
        ld      e,c
        ld      d,0
        add     hl,de
        ld      b,7
bab_shift:
        add     hl,hl
        djnz    bab_shift
        ld      de,BLOCK_ART
        add     hl,de
        ret

; ---- block_tile — IX = block -> HL = the tile to draw, (bd_slope) set ------
block_tile:
        ld      a,(ix+BLK_TILT)
        ld      e,a
        ld      d,0
        ld      hl,rot_slope
        add     hl,de
        ld      a,(hl)
        ld      (bd_slope),a
        ld      a,(ix+BLK_TILT)
        or      a
        jr      nz,bt_tilted
        ld      a,(ix+BLK_PIECE)
        jp      block_art_base
bt_tilted:
        dec     a                   ; rot_art + (piece*4 + tilt-1)*128
        ld      c,a
        ld      a,(ix+BLK_PIECE)
        add     a,a
        add     a,a
        add     a,c
        ld      l,a
        ld      h,0
        ld      b,7
bt_shift:
        add     hl,hl
        djnz    bt_shift
        ld      de,rot_art
        add     hl,de
        ret

; ============================================================================
;  Drawing
; ============================================================================

; ---- block_y — IX = block -> HL = the PIVOT cell's top scanline ------------
block_y:
        ld      l,(ix+BLK_ROW)
        ld      h,0
        add     hl,hl
        add     hl,hl
        add     hl,hl
        add     hl,hl               ; row * 16
        ld      e,(ix+BLK_YOFF)
        ld      d,0
        add     hl,de
        ld      de,GRID_TOP_Y
        add     hl,de
        ret

; ---- block_span — IX = block -> (bd_drop) = extra lines the tilt adds ------
block_span:
        ld      a,(bd_slope)
        or      a
        jr      nz,bs_signed
        xor     a
        ld      (bd_drop),a
        ret
bs_signed:
        bit     7,a
        jr      z,bs_pos
        neg
bs_pos:
        ld      c,a                 ; |slope|
        ld      b,(ix+BLK_LEN)
        dec     b
        xor     a
        jr      z,bs_store
bs_mul:
        add     a,c
        djnz    bs_mul
bs_store:
        ld      (bd_drop),a
        ret

; ---- block_draw — IX = block -----------------------------------------------
;  A beam draws its own cells, each stepped by the tilt's slope, so the
;  pivot end stays put and the free end swings down.
; ----------------------------------------------------------------------------
block_draw:
        ld      a,(ix+BLK_STATE)
        or      a
        ret     z
        call    block_tile
        ld      (sp_art),hl
        call    block_span
        ld      a,BLK_BYTES_PER_ROW
        ld      (sp_w),a
        ld      a,BLK_H
        ld      (sp_h),a

        call    block_y
        ld      a,(bd_slope)        ; a rising slope means the LEFT end is
        bit     7,a                 ; the one going down, so cell 0 starts
        jr      z,bd_ystart         ; at the bottom of the swing
        ld      a,(bd_drop)
        ld      e,a
        ld      d,0
        add     hl,de
bd_ystart:
        ld      (bd_y),hl
        ld      l,(ix+BLK_COL)
        ld      h,0
        add     hl,hl
        add     hl,hl
        add     hl,hl
        add     hl,hl
        ld      (bd_x),hl
        ld      a,(ix+BLK_LEN)
        ld      (bd_n),a
bd_cell:
        ld      hl,(bd_x)
        ld      (sp_x),hl
        ld      hl,(bd_y)
        ld      (sp_y),hl
        push    ix
        call    spr_blit
        pop     ix
        ld      hl,(bd_x)           ; next cell to the right
        ld      de,CELL_PX
        add     hl,de
        ld      (bd_x),hl
        ld      a,(bd_slope)        ; ...stepped by the slope, whichever way
        or      a
        jr      z,bd_next
        ld      e,a
        add     a,a
        sbc     a,a
        ld      d,a
        ld      hl,(bd_y)
        add     hl,de
        ld      (bd_y),hl
bd_next:
        ld      a,(bd_n)
        dec     a
        ld      (bd_n),a
        jr      nz,bd_cell
        ret

blocks_draw_all:
        ld      a,(block_count)
        or      a
        ret     z
        ld      b,a
        ld      e,0
bda_loop:
        push    bc
        push    de
        call    block_ptr
        call    block_draw
        pop     de
        pop     bc
        inc     e
        djnz    bda_loop
        ret

; ---- blocks_draw_rect — re-lay every piece touching the redraw window ------
blocks_draw_rect:
        ld      a,(block_count)
        or      a
        ret     z
        ld      b,a
        ld      e,0
bdr_loop:
        push    bc
        push    de
        ld      a,(bdr_skip)
        cp      e
        jr      z,bdr_skipped
        call    block_ptr
        call    bdr_test
bdr_skipped:
        pop     de
        pop     bc
        inc     e
        djnz    bdr_loop
        ret

bdr_test:
        ld      a,(ix+BLK_STATE)
        or      a
        ret     z
        call    block_bbox          ; -> (bb_col) (bb_ncol) (bb_y) (bb_n)
        ld      a,(rr_col0)
        ld      b,a
        ld      a,(rr_ncol)
        add     a,b
        dec     a
        ld      hl,bb_col
        cp      (hl)
        ret     c                   ; the piece starts right of the window
        ld      a,(bb_col)
        ld      hl,bb_ncol
        add     a,(hl)
        dec     a
        cp      b
        ret     c                   ; ...or ends left of it
        ld      a,(rr_y0)
        ld      b,a
        ld      a,(rr_n)
        add     a,b
        dec     a
        ld      hl,bb_y
        cp      (hl)
        ret     c
        ld      a,(bb_y)
        ld      hl,bb_n
        add     a,(hl)
        dec     a
        cp      b
        ret     c
        jp      block_draw

; ---- block_bbox — IX = block -> the rectangle it occupies on screen --------
block_bbox:
        call    block_tile          ; sets bd_slope
        call    block_span
        ld      a,(ix+BLK_COL)
        add     a,a
        add     a,a
        ld      (bb_col),a
        ld      a,(ix+BLK_LEN)
        add     a,a
        add     a,a
        ld      (bb_ncol),a
        call    block_y
        ld      a,l
        ld      (bb_y),a
        ld      a,(bd_drop)
        add     a,BLK_H
        ld      (bb_n),a
        ret

; ---- block_erase — put the background back over the whole span -------------
;  redraw_rect walks the block and pig tables with IX, so the caller's IX
;  has to be put out of harm's way; and the piece hides itself for the
;  duration, or it would be painted straight back where it was.
; ----------------------------------------------------------------------------
block_erase:
        push    ix
        call    block_index
        ld      (bdr_skip),a
        call    block_bbox
        ld      a,(bb_col)
        ld      (rr_col0),a
        ld      a,(bb_ncol)
        ld      (rr_ncol),a
        ld      a,(bb_y)
        ld      (rr_y0),a
        ld      a,(bb_n)
        ld      (rr_n),a
        call    redraw_rect
        ld      a,#FF
        ld      (bdr_skip),a
        pop     ix
        ret

; ============================================================================
;  Damage
; ============================================================================
block_hit:
        ld      b,a
        ld      a,(ix+BLK_STATE)
        or      a
        ret     z
        ld      a,(ix+BLK_HP)
        sub     b
        jr      c,block_destroy
        jr      z,block_destroy
        ld      (ix+BLK_HP),a
        jp      settle_ping

block_destroy:
        ld      a,(ix+BLK_STATE)
        or      a
        ret     z
        call    block_release
        call    block_erase         ; ...only now, so the hole shows
        ld      (ix+BLK_STATE),BS_FREE
        ld      hl,(score)
        ld      de,50
        add     hl,de
        ld      (score),hl
        jp      settle_ping

; ----------------------------------------------------------------------------
;  block_shove — A = #FF left / 1 right. A bird that lands on a fort and
;  keeps sliding drags it that way: the shove is remembered and decides
;  which way a piece goes over when it does lose its footing.
; ----------------------------------------------------------------------------
block_shove:
        ld      (ix+BLK_SHOVE),a
        jp      settle_ping

; ============================================================================
;  blocks_update — the collapse sweep, bottom row first.
;  NZ if anything moved. Armed by damage, disarmed by the first quiet sweep.
; ============================================================================
settle_ping:
        ld      a,1
        ld      (settle_req),a
        ret

blocks_update:
        ld      a,(settle_req)
        or      a
        ret     z
        xor     a
        ld      (bu_moved),a
        ld      a,GRID_H-1
        ld      (bu_row),a
bu_row_loop:
        xor     a
        ld      (bu_col),a
bu_col_loop:
        ld      a,(bu_col)
        ld      b,a
        ld      a,(bu_row)
        ld      c,a
        call    grid_at
        ld      a,(hl)
        cp      GRID_EMPTY
        jr      z,bu_next
        bit     7,a
        jr      nz,bu_next          ; a pig — entity.asm moves those
        ld      (bu_self),a
        ld      e,a
        call    block_ptr
        ld      a,(bu_row)          ; act once, at the piece's own cell
        cp      (ix+BLK_ROW)
        jr      nz,bu_next
        ld      a,(bu_col)
        cp      (ix+BLK_COL)
        jr      nz,bu_next
        call    block_step
bu_next:
        ld      a,(bu_col)
        inc     a
        ld      (bu_col),a
        cp      GRID_W
        jr      c,bu_col_loop
        ld      a,(bu_row)
        or      a
        jr      z,bu_done
        dec     a
        ld      (bu_row),a
        jr      bu_row_loop
bu_done:
        ld      a,(bu_moved)
        or      a
        ret     nz
        ld      (settle_req),a
        ret

; ---- block_step — IX = block: one frame of standing, tipping or falling ----
block_step:
        ld      a,(ix+BLK_STATE)
        cp      BS_FALL
        jp      z,bs_falling
        cp      BS_TIP
        jp      z,bs_tipping

        call    block_support
        or      a
        jr      z,bs_onslope        ; standing — but on the level?
        cp      SUP_FALL
        jr      z,bs_start_fall
        ld      c,a                 ; SUP_TIPR / SUP_TIPL
        ld      a,(ix+BLK_TILT)
        or      a
        ret     nz                  ; already leaning: it has had its go
        ld      a,c
        cp      SUP_TIPR
        ld      a,TILT_D4
        jr      z,bs_tip_go
        ld      a,TILT_U4
bs_tip_go:
        ld      (ix+BLK_SHOVE),0    ; the push has been spent
        ld      (ix+BLK_TILT),a     ; the tilt goes in BEFORE the erase:
        call    block_erase         ; block_erase clobbers A, and a tilted
                                    ; box contains the upright one anyway
        ld      (ix+BLK_STATE),BS_TIP
        ld      (ix+BLK_TIPT),TIP_FRAMES
        ld      a,1
        ld      (bu_moved),a
        jp      block_draw

bs_start_fall:
        ld      (ix+BLK_STATE),BS_FALL
        ld      (ix+BLK_VY),0
        ld      (ix+BLK_VY_I),1
        ld      a,1
        ld      (bu_moved),a
        ret

; ============================================================================
;  Standing on a slope
;
;  A roof does not sit politely on a lintel that has gone over — it follows
;  it down and slides off the low side. This is the one piece of "things on
;  a slope move" a grid can express, and without it the pieces on top of a
;  tipping beam hang in the air while it rotates away beneath them, which
;  is the single most obviously wrong thing you can watch happen.
;
;  Only single cells slide. A beam does not slide, it tips.
; ============================================================================
bs_onslope:
        ld      a,(ix+BLK_LEN)
        cp      2
        ret     nc
        call    support_tilt        ; -> A = 0 / 1 downhill right / #FF left
        or      a
        ret     z
        ld      c,a
        ld      a,(ix+BLK_TIPT)     ; a cell at a time, not a cell a frame
        or      a
        jr      z,bsl_go
        dec     (ix+BLK_TIPT)
        ld      a,1
        ld      (bu_moved),a
        ret
bsl_go:
        ld      a,(ix+BLK_COL)
        add     a,c
        cp      GRID_W
        ret     nc                  ; off the edge of the world: leave it
        ld      b,a
        ld      c,(ix+BLK_ROW)
        push    bc
        call    cell_free
        pop     bc
        ret     nz                  ; something in the way: it stays put
        ld      a,b                 ; block_erase clobbers B, so the column
        ld      (bsl_col),a         ; it is moving to goes somewhere safe
        call    block_erase
        call    block_release
        ld      a,(bsl_col)
        ld      (ix+BLK_COL),a
        ld      a,(bu_self)
        call    block_claim
        ld      (ix+BLK_TIPT),SLIDE_FRAMES
        ld      a,1
        ld      (bu_moved),a
        jp      block_draw

; ---- support_tilt — IX = block -> A = 0 none, 1 downhill right, #FF left ---
support_tilt:
        ld      b,(ix+BLK_COL)
        ld      a,(ix+BLK_ROW)
        inc     a
        cp      GRID_H
        jr      nc,st_none          ; the world floor is not a slope
        ld      c,a
        call    grid_at
        ld      a,(hl)
        cp      GRID_EMPTY
        jr      z,st_none
        bit     7,a
        jr      nz,st_none          ; standing on a pig is not a slope either
        push    ix
        ld      e,a
        call    block_ptr
        ld      a,(ix+BLK_TILT)
        pop     ix
        or      a
        ret     z
        cp      TILT_U4             ; the D tilts drop to the right
        jr      nc,st_left
        ld      a,1
        ret
st_left:
        ld      a,#FF
        ret
st_none:
        xor     a
        ret

; ---- tipping: one more step of lean, then let go ---------------------------
bs_tipping:
        ld      a,1
        ld      (bu_moved),a
        ld      a,(ix+BLK_TIPT)
        dec     a
        ld      (ix+BLK_TIPT),a
        ret     nz
        ld      a,(ix+BLK_TILT)
        cp      TILT_D8             ; already at full lean?
        jr      z,bs_tip_done
        cp      TILT_U8
        jr      z,bs_tip_done
        call    block_erase
        inc     (ix+BLK_TILT)       ; D4 -> D8, U4 -> U8
        ld      (ix+BLK_TIPT),TIP_FRAMES
        jp      block_draw
bs_tip_done:
;  Once it is all the way over it ALWAYS lets go. A beam left parked at an
;  angle hangs in mid-air the moment its pivot is taken out from under it,
;  and no amount of re-checking makes that look like anything but a bug.
;  Letting go means the fall code decides what happens next: if something
;  is under it, it settles onto that flat — which is a roof coming down
;  across the two pillars it has left — and if nothing is, it drops.
        ld      (ix+BLK_STATE),BS_FALL
        ld      (ix+BLK_VY),0
        ld      (ix+BLK_VY_I),1
        ret

; ---- falling ---------------------------------------------------------------
bs_falling:
        ld      a,1
        ld      (bu_moved),a
        call    block_erase

        ld      a,(ix+BLK_VY)       ; one more pixel per frame every third
        inc     a
        cp      3
        jr      c,bs_vy_store
        ld      a,(ix+BLK_VY_I)
        cp      VY_TERMINAL
        jr      nc,bs_vy_reset
        inc     a
        ld      (ix+BLK_VY_I),a
bs_vy_reset:
        xor     a
bs_vy_store:
        ld      (ix+BLK_VY),a
        ld      a,(ix+BLK_YOFF)
        add     a,(ix+BLK_VY_I)
        ld      (ix+BLK_YOFF),a
bs_carry:
        ld      a,(ix+BLK_YOFF)
        cp      CELL_PX
        jp      c,block_draw        ; still inside its own row
        call    span_below_clear
        jr      z,bs_descend
        ld      (ix+BLK_YOFF),0     ; it has arrived on something
        ld      (ix+BLK_STATE),BS_REST
        ld      (ix+BLK_TILT),TILT_NONE
        call    block_land
        ld      a,(ix+BLK_STATE)
        or      a
        ret     z
        jp      block_draw
bs_descend:
        call    block_release
        inc     (ix+BLK_ROW)
        ld      a,(ix+BLK_YOFF)
        sub     CELL_PX
        ld      (ix+BLK_YOFF),a
        ld      a,(bu_self)
        call    block_claim
        jr      bs_carry

; ============================================================================
;  Support
; ============================================================================

; ---- cell_free — B = column, C = row. Z if that cell is clear --------------
;  Cells belonging to the piece being asked about are treated as clear, or a
;  beam would find itself standing on itself while it slides.
cell_free:
        ld      a,c
        cp      GRID_H
        jr      nc,cf_solid         ; the world floor
        call    grid_at
        ld      a,(hl)
        cp      GRID_EMPTY
        ret     z
        ld      c,a
        call    block_index
        cp      c
        ret     nz                  ; someone else: solid
        xor     a                   ; itself: not a support
        ret
cf_solid:
        or      #FF
        ret

; ---- span_below_clear — IX = block. Z if EVERY cell under it is clear ------
span_below_clear:
        ld      b,(ix+BLK_COL)
        ld      a,(ix+BLK_ROW)
        inc     a
        ld      c,a
        ld      a,(ix+BLK_LEN)
        ld      (sbc_n),a
sbc_loop:
        push    bc
        call    cell_free
        pop     bc
        ret     nz                  ; something under this cell
        inc     b
        ld      a,(sbc_n)
        dec     a
        ld      (sbc_n),a
        jr      nz,sbc_loop
        xor     a                   ; all clear
        ret

; ---- block_support — IX = block -> A = SUP_* -------------------------------
;  A single cell is held by the ground, by what is under it, or by being
;  WEDGED between two neighbours — that last rule is what lets a stack stand
;  when its own footing is gone. A BEAM is judged at its ends: both held is
;  stable, one held tips over that end, neither is a free fall. A shove from
;  a bird sliding across the fort decides the direction when both ends are
;  equally loose.
; ----------------------------------------------------------------------------
block_support:
        ld      a,(ix+BLK_LEN)
        cp      2
        jr      nc,bsup_beam

        call    span_below_clear    ; --- a single cell
        jr      nz,bsup_stable
        ld      a,(ix+BLK_COL)
        or      a
        jr      z,bsup_fall
        dec     a
        ld      b,a
        ld      c,(ix+BLK_ROW)
        call    cell_free
        jr      z,bsup_fall
        ld      a,(ix+BLK_COL)
        inc     a
        cp      GRID_W
        jr      nc,bsup_fall
        ld      b,a
        ld      c,(ix+BLK_ROW)
        call    cell_free
        jr      z,bsup_fall
        ld      a,(ix+BLK_SHOVE)    ; wedged, but something shoved it: a
        or      a                   ; piece held only by its neighbours does
        jr      nz,bsup_fall        ; not survive being dragged sideways
bsup_stable:
        ld      a,SUP_STABLE
        ret
bsup_fall:
        ld      a,SUP_FALL
        ret

bsup_beam:                          ; --- a beam: judge it at the ends
        ld      b,(ix+BLK_COL)
        ld      a,(ix+BLK_ROW)
        inc     a
        ld      c,a
        call    cell_free
        ld      a,0
        jr      z,bsup_l_done
        inc     a                   ; the left end is held
bsup_l_done:
        ld      (bsup_l),a

        ld      a,(ix+BLK_COL)
        add     a,(ix+BLK_LEN)
        dec     a
        ld      b,a
        ld      a,(ix+BLK_ROW)
        inc     a
        ld      c,a
        call    cell_free
        ld      a,0
        jr      z,bsup_r_done
        inc     a                   ; the right end is held
bsup_r_done:
        ld      c,a
        ld      a,(bsup_l)
        or      a
        jr      z,bsup_noleft
        ld      a,c
        or      a
        jr      z,bsup_tipr         ; left only: the right end drops
        jr      bsup_stable         ; both ends: it stands
bsup_noleft:
        ld      a,c
        or      a
        jr      nz,bsup_tipl        ; right only: the left end drops
        call    span_below_clear    ; neither end, but is the middle held?
        jr      z,bsup_fall
        ld      a,(ix+BLK_SHOVE)    ; balanced on its middle — then which way
        or      a                   ; it goes is decided by whatever pushed
        jr      z,bsup_stable       ; it, which is exactly a bird sliding
        bit     7,a                 ; across the top of the fort
        jr      nz,bsup_tipl
        jr      bsup_tipr
bsup_tipr:
        ld      a,SUP_TIPR
        ret
bsup_tipl:
        ld      a,SUP_TIPL
        ret

; ---- block_land — IX = block that has just come to rest --------------------
;  Damage to whatever is under the WHOLE span, in proportion to the speed.
;  A piece that has merely fallen takes none itself: rubble stays where it
;  lands, or a fort you knock down tidies itself away.
; ----------------------------------------------------------------------------
block_land:
        ld      a,(ix+BLK_VY_I)
        ld      (bl_speed),a
        ld      (ix+BLK_VY_I),0
        ld      (ix+BLK_VY),0
        cp      2
        ret     c                   ; a gentle settle harms nobody
        ld      b,CRUSH_PER_SPEED
        call    mul8
        ld      b,(ix+BLK_LEN)      ; a four-cell beam comes down with four
        call    mul8                ; times the weight, which is the whole
        ld      (bl_dmg),a          ; point of a roof falling on a pig

        ld      a,(ix+BLK_ROW)
        inc     a
        cp      GRID_H
        ret     nc                  ; it landed on the world floor
        ld      (bl_row),a
        ld      a,(ix+BLK_COL)
        ld      (bl_col),a
        ld      a,(ix+BLK_LEN)
        ld      (bl_n),a
bl_loop:
        ld      a,(bl_col)
        ld      b,a
        ld      a,(bl_row)
        ld      c,a
        push    ix
        call    grid_at
        ld      a,(hl)
        cp      GRID_EMPTY
        jr      z,bl_next
        bit     7,a
        jr      nz,bl_pig
        ld      e,a
        call    block_ptr
        ld      a,(bl_dmg)
        call    block_hit
        jr      bl_next
bl_pig:
        and     #7F
        ld      e,a
        call    pig_ptr
        ld      a,(bl_dmg)
        call    pig_hit
bl_next:
        pop     ix
        ld      a,(bl_col)
        inc     a
        ld      (bl_col),a
        ld      a,(bl_n)
        dec     a
        ld      (bl_n),a
        jr      nz,bl_loop
        ret

; ----------------------------------------------------------------------------
;  mul8 — A = A * B, saturating at 255. Clobbers B, C.
; ----------------------------------------------------------------------------
mul8:
        ld      c,a
        xor     a
        or      b
        ret     z
        xor     a
m8_loop:
        add     a,c
        jr      c,m8_sat
        djnz    m8_loop
        ret
m8_sat:
        ld      a,#FF
        ret

; ----------------------------------------------------------------------------
;  block state
; ----------------------------------------------------------------------------
bu_row:         db      0
bu_col:         db      0
bu_self:        db      0
bu_moved:       db      0
bl_speed:       db      0
bl_dmg:         db      0
bl_row:         db      0
bl_col:         db      0
bl_n:           db      0
ba_piece:       db      0
ba_len:         db      1
bdr_skip:       db      #FF
bc_val:         db      0
bc_n:           db      0
sbc_n:          db      0
bsup_l:         db      0
bsl_col:        db      0
bd_slope:       db      0
bd_drop:        db      0
bd_x:           dw      0
bd_y:           dw      0
bd_n:           db      0
bb_col:         db      0
bb_ncol:        db      0
bb_y:           db      0
bb_n:           db      0
rb_piece:       db      0
rb_tilt:        db      0
rb_cnt:         db      0
