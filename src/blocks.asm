; ============================================================================
;  FURIOUS FOWLS — blocks.asm
;  The forts: a 20x10 grid of 16x16 pieces, and the collapse that brings
;  them down on the pigs.
;
;  WHY A GRID
;  ----------
;  Real rigid-body physics is not happening on a 4 MHz Z80, and it is not
;  what makes Angry Birds feel good anyway. What makes it feel good is that
;  structures LOSE THEIR FOOTING: knock out a leg and everything above it
;  comes down, and whatever is underneath gets flattened. That is a
;  cellular-automaton problem, not a physics problem, and it costs about
;  four thousand T-states a frame.
;
;  So: every piece owns one cell. An occupancy grid says who is where. Once
;  a frame we sweep the grid from the BOTTOM ROW UPWARD — the order matters,
;  because a block can only fall into a cell the one below has already
;  vacated, so sweeping upward lets a whole column start moving in a single
;  frame instead of one row per frame. A piece with nothing under it
;  accelerates downward, slides through its cell a few pixels at a time, and
;  when it has travelled a whole cell it either claims the one below or
;  lands on whatever is there, dealing damage in proportion to its speed.
;  Pigs live in the same grid, which is the whole point: a falling wall
;  crushes them without a single line of special-case code.
; ============================================================================

; ----------------------------------------------------------------------------
;  grid_at — B = column, C = row -> HL = that cell's address in the grid.
;  Clobbers A, DE.
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
        assert  BLK_SIZE == 8
block_ptr:
        ld      d,0
        ld      hl,0
        add     hl,de
        add     hl,hl
        add     hl,hl
        add     hl,hl
        ld      de,blocks
        add     hl,de
        push    hl
        pop     ix
        ret

; ----------------------------------------------------------------------------
;  blocks_reset — empty grid, empty block table
; ----------------------------------------------------------------------------
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
;  block_add — A = piece, B = column, C = row. Claims the next free slot
;  and registers it in the grid.
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
        call    block_hp_init
        ld      b,(ix+BLK_COL)      ; block_hp_init needed BC for itself
        ld      c,(ix+BLK_ROW)
        call    grid_at
        ld      a,(block_count)
        ld      (hl),a
        inc     a
        ld      (block_count),a
        ret

; ----------------------------------------------------------------------------
;  block_hp_init — IX = block. Strength is the piece's base scaled by the
;  level's material set. blk_hp_table is generated from tools/sheetdefs.py,
;  so the numbers a level designer reasons about and the numbers the engine
;  uses cannot drift apart.
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
        ld      (ix+BLK_HP),a
        ret

; ============================================================================
;  Drawing
; ============================================================================
        assert  BLK_BYTES == 128
        assert  CELL_PX == 16

; ---- block_draw — IX = block ------------------------------------------------
block_draw:
        ld      a,(ix+BLK_STATE)
        or      a
        ret     z
        ld      hl,0                ; art = BLOCK_ART + (set*10 + piece)*128
        ld      a,(block_set)
        or      a
        jr      z,bd_piece
        ld      b,a
        ld      de,BLK_PIECES
bd_set:
        add     hl,de
        djnz    bd_set
bd_piece:
        ld      e,(ix+BLK_PIECE)
        ld      d,0
        add     hl,de
        ld      b,7
bd_shift:
        add     hl,hl
        djnz    bd_shift
        ld      de,BLOCK_ART
        add     hl,de
        ld      (sp_art),hl

        ld      l,(ix+BLK_COL)      ; x = col * CELL_PX
        ld      h,0
        add     hl,hl
        add     hl,hl
        add     hl,hl
        add     hl,hl
        ld      (sp_x),hl
        call    block_y
        ld      (sp_y),hl
        ld      a,BLK_BYTES_PER_ROW
        ld      (sp_w),a
        ld      a,BLK_H
        ld      (sp_h),a
        jp      spr_blit

; ---- block_y — IX = block -> HL = its top scanline --------------------------
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

; ---- blocks_draw_all — after a full repaint ---------------------------------
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

; ---- blocks_draw_rect — re-lay every block that touches the redraw window ---
;  Called by redraw_rect after it has put the background back. A block that
;  only partly overlaps is drawn in full, which is harmless: it repaints
;  pixels that were already its own.
;
;  (bdr_skip) names one block index to leave alone — that is how a piece
;  erases ITSELF without immediately painting itself back in.
; ----------------------------------------------------------------------------
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
        ld      a,(ix+BLK_COL)      ; it spans char columns col*4 .. col*4+3
        add     a,a
        add     a,a
        ld      c,a
        ld      a,(rr_col0)
        ld      b,a
        ld      a,(rr_ncol)
        add     a,b
        dec     a
        cp      c
        ret     c                   ; the block starts right of the window
        ld      a,c
        add     a,3
        cp      b
        ret     c                   ; ...or ends left of it
        call    block_y
        ld      c,l
        ld      a,(rr_y0)
        ld      b,a
        ld      a,(rr_n)
        add     a,b
        dec     a
        cp      c
        ret     c
        ld      a,c
        add     a,BLK_H-1
        cp      b
        ret     c
        jp      block_draw

; ---- block_erase — put the background back over IX's cell -------------------
;  The block is hidden from blocks_draw_rect for the duration, otherwise
;  redraw_rect would helpfully paint it straight back where it was.
; ----------------------------------------------------------------------------
;  redraw_rect repaints whatever else stands here, and that walks the block
;  and pig tables with IX — so the caller's IX has to be put out of harm's
;  way. Every erase in the game has this shape.
block_erase:
        push    ix
        push    ix
        pop     hl
        ld      de,blocks
        or      a
        sbc     hl,de
        ld      b,3                 ; index = offset / BLK_SIZE
be_idx:
        srl     h
        rr      l
        djnz    be_idx
        ld      a,l
        ld      (bdr_skip),a

        ld      a,(ix+BLK_COL)
        add     a,a
        add     a,a
        ld      (rr_col0),a
        ld      a,4
        ld      (rr_ncol),a
        call    block_y
        ld      a,l
        ld      (rr_y0),a
        ld      a,BLK_H
        ld      (rr_n),a
        call    redraw_rect
        ld      a,#FF
        ld      (bdr_skip),a
        pop     ix
        ret

; ============================================================================
;  Damage
; ============================================================================

; ---- block_hit — IX = block, A = damage -------------------------------------
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

; ---- block_destroy — IX = block ---------------------------------------------
block_destroy:
        ld      a,(ix+BLK_STATE)
        or      a
        ret     z
        ld      b,(ix+BLK_COL)
        ld      c,(ix+BLK_ROW)
        push    bc
        call    grid_at
        ld      (hl),GRID_EMPTY
        pop     bc
        call    block_erase         ; ...only now, so the hole shows
        ld      (ix+BLK_STATE),BS_FREE
        ld      hl,(score)
        ld      de,50
        add     hl,de
        ld      (score),hl
        jp      settle_ping

; ============================================================================
;  blocks_update — the collapse sweep, bottom row first.
;  Returns NZ if anything moved, which is how the turn machine knows the
;  dust has not settled yet.
;
;  The sweep reads all two hundred grid cells and costs the better part of
;  half a frame, so it does NOT run unconditionally: settle_req is raised
;  whenever something could have changed the standing order (a piece taking
;  damage, a piece breaking, a pig dying) and lowered again by the first
;  sweep that finds nothing moving. A bird in mid-air over an untouched
;  fort therefore costs nothing at all.
; ============================================================================
settle_ping:                        ; "something changed down there"
        ld      a,1
        ld      (settle_req),a
        ret

blocks_update:
        ld      a,(settle_req)
        or      a
        ret     z                   ; quiescent: Z, and nothing moved
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
        ld      a,(bu_row)          ; act only at the piece's own cell
        cp      (ix+BLK_ROW)
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
        ret     nz                  ; still moving: sweep again next frame
        ld      (settle_req),a      ; A is zero: the fort has stopped
        ret

; ---- block_step — IX = block: one frame of falling, or of standing still ----
block_step:
        ld      a,(ix+BLK_STATE)
        cp      BS_FALL
        jr      z,bs_falling

        call    block_supported     ; resting: is anything still holding it?
        ret     z
        ld      (ix+BLK_STATE),BS_FALL
        ld      (ix+BLK_VY),0
        ld      (ix+BLK_VY_I),1
        ld      a,1
        ld      (bu_moved),a
        ret

bs_falling:
        ld      a,1
        ld      (bu_moved),a
        call    block_erase         ; lift it off the screen before it moves

        ld      a,(ix+BLK_VY)       ; one more pixel per frame every third
        inc     a                   ; frame, up to terminal speed
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
        jp      c,block_draw        ; still inside its own cell
        call    cell_below_clear
        jr      z,bs_descend
        ld      (ix+BLK_YOFF),0     ; it has arrived on something
        ld      (ix+BLK_STATE),BS_REST
        call    block_land
        ld      a,(ix+BLK_STATE)
        or      a
        ret     z                   ; the landing finished it off
        jp      block_draw
bs_descend:
        ld      b,(ix+BLK_COL)      ; hand the cell over to the row below
        ld      c,(ix+BLK_ROW)
        push    bc
        call    grid_at
        ld      (hl),GRID_EMPTY
        pop     bc
        inc     c
        ld      (ix+BLK_ROW),c
        ld      a,(ix+BLK_YOFF)
        sub     CELL_PX
        ld      (ix+BLK_YOFF),a
        call    grid_at
        ld      a,(bu_self)
        ld      (hl),a
        jr      bs_carry

; ---- block_supported — IX = block. Z if it is held up, NZ if it is loose.
;
;  Three ways to be held up: the world floor, something in the cell below,
;  or — and this is the one that makes forts stand — being WEDGED, with
;  occupied cells to both left and right. Without that last rule a lintel
;  over a doorway has nothing under its middle and every hut in the game
;  falls down the instant it is built.
;
;  It is a local test, not a structural analysis, and it converges the right
;  way: knock out the pillar under one end of a run and that end block loses
;  its floor, falls, and takes its neighbour's support with it, so the run
;  unzips from the outside in — one block per sweep, which is exactly what a
;  collapse should look like.
;
;  Only RESTING blocks ask this. A block already falling only cares whether
;  the cell below is clear (cell_below_free), or it would snag on a
;  neighbour halfway down.
; ----------------------------------------------------------------------------
block_supported:
        call    cell_below_clear
        jr      nz,bsup_held        ; the floor, or something under it
        ld      a,(ix+BLK_COL)
        or      a
        jr      z,bsup_loose        ; hard against the left edge
        dec     a
        ld      b,a
        ld      c,(ix+BLK_ROW)
        call    grid_at
        ld      a,(hl)
        cp      GRID_EMPTY
        jr      z,bsup_loose
        ld      a,(ix+BLK_COL)
        inc     a
        cp      GRID_W
        jr      nc,bsup_loose       ; ...or the right
        ld      b,a
        ld      c,(ix+BLK_ROW)
        call    grid_at
        ld      a,(hl)
        cp      GRID_EMPTY
        jr      z,bsup_loose
bsup_held:
        xor     a                   ; Z = held up
        ret
bsup_loose:
        or      #FF                 ; NZ = nothing is holding it
        ret

; ---- cell_below_clear — IX = block. Z if the cell below is CLEAR and the
;      block could descend into it; NZ if something is there, or if the
;      block is standing on the world floor.
;
;  The name matches the flag on purpose: CP GRID_EMPTY sets Z when the cell
;  IS empty, and a routine whose sense is the opposite of its arithmetic is
;  a bug waiting to be written twice.
; ----------------------------------------------------------------------------
cell_below_clear:
        ld      a,(ix+BLK_ROW)
        inc     a
        cp      GRID_H
        jr      nc,cbc_blocked
        ld      c,a
        ld      b,(ix+BLK_COL)
        call    grid_at
        ld      a,(hl)
        cp      GRID_EMPTY
        ret                         ; Z = clear
cbc_blocked:
        or      a                   ; A is GRID_H, so this is NZ
        ret

; ---- block_land — IX = block that has just come to rest ---------------------
;  Damage flows both ways, in proportion to the speed: the thing underneath
;  takes the brunt, the block itself takes half.
; ----------------------------------------------------------------------------
block_land:
        ld      a,(ix+BLK_VY_I)
        ld      (bl_speed),a
        ld      (ix+BLK_VY_I),0
        ld      (ix+BLK_VY),0
        cp      2
        ret     c                   ; a gentle settle harms nobody

        ld      a,(ix+BLK_ROW)
        inc     a
        cp      GRID_H
        jr      nc,bl_self          ; it landed on the ground
        ld      c,a
        ld      b,(ix+BLK_COL)
        call    grid_at
        ld      a,(hl)
        cp      GRID_EMPTY
        jr      z,bl_self
        push    ix
        ld      c,a                 ; C = whoever is underneath
        ld      a,(bl_speed)
        ld      b,CRUSH_PER_SPEED
        call    mul8
        ld      b,a                 ; B = damage
        ld      a,c
        bit     7,a
        jr      nz,bl_pig
        ld      e,a
        push    bc
        call    block_ptr
        pop     bc
        ld      a,b
        call    block_hit
        jr      bl_done
bl_pig:
        and     #7F
        ld      e,a
        push    bc
        call    pig_ptr
        pop     bc
        ld      a,b
        call    pig_hit
bl_done:
        pop     ix
bl_self:
        ld      a,(bl_speed)
        ld      b,CRUSH_PER_SPEED/2
        call    mul8
        jp      block_hit

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
ba_piece:       db      0
bdr_skip:       db      #FF
