; ============================================================================
;  FURIOUS FOWLS — entity.asm
;  The pigs: two grid cells tall, in the same occupancy grid as the blocks,
;  so the collapse code crushes them for free.
;
;  A pig's ENT_ROW is the row its FEET are in; it also owns the cell above.
;  It falls exactly the way a block does — the level compiler guarantees the
;  headroom, so the two cells can always be moved together.
;
;  Poses come from the six creature states in the spritesheet. A pig blinks
;  on its own clock (out of phase with its neighbours, so a row of them
;  doesn't blink in lockstep), widens its eyes while a bird is in the air,
;  and laughs at you when a shot fails to reach it.
; ============================================================================

; ----------------------------------------------------------------------------
;  pig_ptr — E = index -> IX = its record. Clobbers A, DE, HL.
; ----------------------------------------------------------------------------
        assert  ENT_SIZE == 16
pig_ptr:
        ld      d,0
        ld      hl,0
        add     hl,de
        add     hl,hl
        add     hl,hl
        add     hl,hl
        add     hl,hl
        ld      de,pigs
        add     hl,de
        push    hl
        pop     ix
        ret

pigs_reset:
        ld      hl,pigs
        ld      de,pigs+1
        ld      bc,MAX_PIGS*ENT_SIZE-1
        ld      (hl),ES_FREE
        ldir
        xor     a
        ld      (pig_count),a
        ld      (pigs_alive),a
        ret

; ----------------------------------------------------------------------------
;  pig_add — A = kind (0 pig, 1 helmet, 2 king), B = column, C = feet row
; ----------------------------------------------------------------------------
pig_add:
        ld      (pa_kind),a
        ld      a,(pig_count)
        cp      MAX_PIGS
        ret     nc
        ld      e,a
        call    pig_ptr
        ld      a,(pa_kind)
        add     a,BIRD_TYPES        ; pigs follow the birds in the sheet
        ld      (ix+ENT_TYPE),a
        ld      (ix+ENT_STATE),ES_REST
        ld      (ix+ENT_COL),b
        ld      (ix+ENT_ROW),c
        ld      (ix+ENT_YOFF),0
        ld      (ix+ENT_VY),0
        ld      (ix+ENT_VY_I),0
        ld      (ix+ENT_FRAME),FR_IDLE
        ld      (ix+ENT_ANIM),0
        ld      a,(pa_kind)         ; a helmet is twice the pig, a crown
        inc     a                   ; three times
        ld      b,PIG_HP_BASE
        call    mul8
        ld      (ix+ENT_HP),a
        ld      a,(pig_count)
        add     a,a
        add     a,a
        add     a,29                ; a different blink phase each
        ld      (ix+ENT_PHASE),a

        ld      a,(pig_count)
        or      GRID_PIG
        ld      (pg_self),a
        call    pig_claim
        ld      a,(pig_count)
        inc     a
        ld      (pig_count),a
        ld      (pigs_alive),a
        ret

; ---- pig_claim / pig_release — IX = pig, both of its cells ------------------
pig_claim:
        ld      a,(pg_self)
        jr      pig_mark
pig_release:
        ld      a,GRID_EMPTY
pig_mark:
        ld      (pm_val),a
        ld      b,(ix+ENT_COL)
        ld      c,(ix+ENT_ROW)
        push    bc
        call    grid_at
        ld      a,(pm_val)
        ld      (hl),a
        pop     bc
        dec     c
        call    grid_at
        ld      a,(pm_val)
        ld      (hl),a
        ret

; ============================================================================
;  Drawing
; ============================================================================

; ---- pig_y — IX = pig -> HL = the sprite's top scanline ---------------------
;  The sprite is two cells tall and hangs from the cell ABOVE the feet.
; ----------------------------------------------------------------------------
pig_y:
        ld      a,(ix+ENT_ROW)
        dec     a
        call    cell_pix             ; (row-1) * CELL_PX
        ld      e,(ix+ENT_YOFF)
        ld      d,0
        add     hl,de
        ld      de,GRID_TOP_Y
        add     hl,de
        ret

; ---- art_for_creature — A = creature type, C = frame -> HL = art address --------
;  Frames are stored creature-major, which makes this one multiply.
; ----------------------------------------------------------------------------
art_for_creature:
        ld      l,a
        ld      h,0
        ld      de,FR_COUNT
        ld      b,l
        ld      hl,0
        inc     b
        jr      ca_test
ca_mul:
        add     hl,de
ca_test:
        djnz    ca_mul
        ld      e,c
        ld      d,0
        add     hl,de               ; HL = frame number within the bank
;  ...times CR_FRAME_BYTES. A ten by twenty frame is a hundred bytes, so
;  this is no longer the free byte-swap that 256 was: 100n = 64n+32n+4n.
        add     hl,hl
        add     hl,hl               ; 4n
        ld      b,h
        ld      c,l
        add     hl,hl
        add     hl,hl
        add     hl,hl               ; 32n
        ld      d,h
        ld      e,l
        add     hl,hl               ; 64n
        add     hl,de               ; 96n
        add     hl,bc               ; 100n
        ld      de,CREATURE_ART
        add     hl,de
        ret
        assert  CR_FRAME_BYTES == 100

; ---- pig_draw — IX = pig ----------------------------------------------------
pig_draw:
        ld      a,(ix+ENT_STATE)
        or      a
        ret     z
        cp      ES_DEAD
        ret     z
        ld      c,(ix+ENT_FRAME)
        ld      a,(ix+ENT_TYPE)
        call    art_for_creature
        ld      (sp_art),hl
        ld      a,(ix+ENT_COL)
        call    cell_pix
        ld      (sp_x),hl
        call    pig_y
        ld      (sp_y),hl
        ld      a,CR_BYTES_PER_ROW
        ld      (sp_w),a
        ld      a,CR_HEIGHT
        ld      (sp_h),a
        jp      spr_blit

pigs_draw_all:
        ld      a,(pig_count)
        or      a
        ret     z
        ld      b,a
        ld      e,0
pda_loop:
        push    bc
        push    de
        call    pig_ptr
        call    pig_draw
        pop     de
        pop     bc
        inc     e
        djnz    pda_loop
        ret

; ---- pigs_draw_rect — the pig half of redraw_rect's restacking --------------
pigs_draw_rect:
        ld      a,(pig_count)
        or      a
        ret     z
        ld      b,a
        ld      e,0
pdr_loop:
        push    bc
        push    de
        ld      a,(pdr_skip)
        cp      e
        jr      z,pdr_skipped
        call    pig_ptr
        call    pdr_test
pdr_skipped:
        pop     de
        pop     bc
        inc     e
        djnz    pdr_loop
        ret

pdr_test:
        ld      a,(ix+ENT_STATE)
        or      a
        ret     z
        cp      ES_DEAD
        ret     z
        ld      c,CR_WIDTH
        ld      a,(ix+ENT_COL)
        call    cell_cols
        ld      a,(cc_col)
        ld      c,a
        ld      a,(rr_col0)
        ld      b,a
        ld      a,(rr_ncol)
        add     a,b
        dec     a
        cp      c
        ret     c
        ld      a,(cc_n)
        add     a,c
        dec     a
        cp      b
        ret     c
        call    pig_y
        ld      c,l
        ld      a,(rr_y0)
        ld      b,a
        ld      a,(rr_n)
        add     a,b
        dec     a
        cp      c
        ret     c
        ld      a,c
        add     a,CR_HEIGHT-1
        cp      b
        ret     c
        jp      pig_draw

; ---- pig_erase — IX = pig ---------------------------------------------------
;  redraw_rect repaints whatever else stands here, and that walks the block
;  and pig tables with IX — so the caller's IX has to be put out of harm's
;  way. Every erase in the game has this shape.
pig_erase:
        push    ix
        push    ix
        pop     hl
        ld      de,pigs
        or      a
        sbc     hl,de
        ld      b,4                 ; index = offset / ENT_SIZE
pe_idx:
        srl     h
        rr      l
        djnz    pe_idx
        ld      a,l
        ld      (pdr_skip),a

        ld      c,CR_WIDTH
        ld      a,(ix+ENT_COL)
        call    cell_cols
        ld      a,(cc_col)
        ld      (rr_col0),a
        ld      a,(cc_n)
        ld      (rr_ncol),a
        call    pig_y
        ld      a,l
        ld      (rr_y0),a
        ld      a,CR_HEIGHT
        ld      (rr_n),a
        call    redraw_rect
        ld      a,#FF
        ld      (pdr_skip),a
        pop     ix
        ret

; ============================================================================
;  Damage
; ============================================================================

; ---- pig_hit — IX = pig, A = damage ----------------------------------------
pig_hit:
        ld      b,a
        ld      a,(ix+ENT_STATE)
        cp      ES_REST
        jr      z,ph_ok
        cp      ES_FALL
        ret     nz
ph_ok:
;  THE BLOW IS THE SCORE. Not the kill and not the wreckage: how hard the
;  pigs were hit, so a shot that catches three of them beats a shot that
;  flattens one, and a fort demolished around a pig that survived scores
;  nothing at all.
        push    bc
        ld      l,b
        ld      h,0
        call    score_add
        pop     bc
        ld      a,(ix+ENT_HP)
        sub     b
        jr      c,pig_kill
        jr      z,pig_kill
        ld      (ix+ENT_HP),a
        ld      (ix+ENT_FRAME),FR_HURT
        ld      (ix+ENT_ANIM),HURT_LEN
        ld      a,SND_OINK          ; hurt, and indignant about it
        ld      b,2
        call    snd_fx
        call    settle_ping
        jp      pig_repose

; ---- pig_kill — IX = pig ----------------------------------------------------
pig_kill:
        ld      a,(ix+ENT_STATE)
        cp      ES_DYING
        ret     z
        cp      ES_DEAD
        ret     z
        ld      a,SND_POP
        ld      b,2
        call    snd_fx
        call    pig_release         ; it stops holding anything up
        ld      (ix+ENT_STATE),ES_DYING
        ld      (ix+ENT_FRAME),FR_DEAD
        ld      (ix+ENT_ANIM),DIE_LEN
        ld      a,(pigs_alive)
        or      a
        jr      z,pk_draw
        dec     a
        ld      (pigs_alive),a
        ld      a,1
        ld      (ui_dirty),a        ; the strip is counting them
pk_draw:
        call    settle_ping         ; whatever it was holding up is loose now
        jp      pig_repose

; ---- pig_repose — erase and redraw after a pose change ----------------------
pig_repose:
        call    pig_erase
        jp      pig_draw

; ============================================================================
;  pigs_update — falling, dying and idle animation. NZ if anything moved.
; ============================================================================
pigs_update:
        xor     a
        ld      (pu_moved),a
        ld      a,(pig_count)
        or      a
        ret     z
        ld      b,a
        ld      e,0
pu_loop:
        push    bc
        push    de
        ld      a,e
        or      GRID_PIG
        ld      (pg_self),a
        call    pig_ptr
        call    pig_step
        pop     de
        pop     bc
        inc     e
        djnz    pu_loop
        ld      a,(pu_moved)
        or      a
        ret

pig_step:
        ld      a,(ix+ENT_STATE)
        cp      ES_DYING
        jr      z,ps_dying
        cp      ES_REST
        jr      z,ps_resting
        cp      ES_FALL
        ret     nz
        jr      ps_falling

; ---- the death pose plays out, then the pig is gone -------------------------
ps_dying:
        ld      a,1
        ld      (pu_moved),a
        ld      a,(ix+ENT_ANIM)
        dec     a
        ld      (ix+ENT_ANIM),a
        ret     nz
        call    pig_erase
        ld      (ix+ENT_STATE),ES_DEAD
        ret

; ---- standing: run the idle animation, and check the floor ------------------
ps_resting:
        call    pig_pose
        call    pig_below_clear
        ret     nz
        ld      (ix+ENT_STATE),ES_FALL
        ld      (ix+ENT_VY),0
        ld      (ix+ENT_VY_I),1
        ld      a,1
        ld      (pu_moved),a
        ret

ps_falling:
        ld      a,1
        ld      (pu_moved),a
        call    pig_erase
        ld      a,(ix+ENT_VY)
        inc     a
        cp      3
        jr      c,ps_vy_store
        ld      a,(ix+ENT_VY_I)
        cp      VY_TERMINAL
        jr      nc,ps_vy_reset
        inc     a
        ld      (ix+ENT_VY_I),a
ps_vy_reset:
        xor     a
ps_vy_store:
        ld      (ix+ENT_VY),a
        ld      a,(ix+ENT_YOFF)
        add     a,(ix+ENT_VY_I)
        ld      (ix+ENT_YOFF),a
ps_carry:
        ld      a,(ix+ENT_YOFF)
        cp      CELL_PX
        jp      c,pig_draw
        call    pig_below_clear
        jr      z,ps_descend
        ld      (ix+ENT_YOFF),0
        ld      (ix+ENT_STATE),ES_REST
        ld      a,(ix+ENT_VY_I)     ; landing hurts, but only from a height
        ld      (ix+ENT_VY_I),0
        ld      (ix+ENT_VY),0
        cp      4
        jp      c,pig_draw
        ld      b,CRUSH_PER_SPEED/2
        call    mul8
        call    pig_hit
        ld      a,(ix+ENT_STATE)
        cp      ES_DYING
        ret     z
        jp      pig_draw
ps_descend:
        call    pig_release
        ld      a,(ix+ENT_ROW)
        inc     a
        ld      (ix+ENT_ROW),a
        ld      a,(ix+ENT_YOFF)
        sub     CELL_PX
        ld      (ix+ENT_YOFF),a
        call    pig_claim
        jr      ps_carry

; ---- pig_below_clear — Z if the cell under its feet is clear, NZ if
;      something is holding it up (including the world floor).
; ----------------------------------------------------------------------------
pig_below_clear:
        ld      a,(ix+ENT_ROW)
        inc     a
        cp      GRID_H
        jr      nc,pbc_blocked
        ld      c,a
        ld      b,(ix+ENT_COL)
        call    grid_at
        ld      a,(hl)
        cp      GRID_EMPTY
        ret                         ; Z = clear
pbc_blocked:
        or      a                   ; A is GRID_H, so this is NZ
        ret

; ---- pig_pose — idle animation. Blinks on its own phase; goggles at a bird
;      in the air; laughs when a shot has come to nothing.
; ----------------------------------------------------------------------------
pig_pose:
        ld      a,(ix+ENT_ANIM)     ; a timed pose still running?
        or      a
        jr      z,pp_choose
        dec     a
        ld      (ix+ENT_ANIM),a
        ret     nz
pp_choose:
        ld      c,FR_IDLE
        ld      a,(game_state)
        cp      GS_FLY
        jr      nz,pp_blink
        ld      c,FR_READY          ; it has seen what is coming
        jr      pp_set
pp_blink:
        ld      a,(frame_counter)
        add     a,(ix+ENT_PHASE)
        and     #3F
        cp      BLINK_LEN
        jr      nc,pp_set
        ld      c,FR_BLINK
pp_set:
        ld      a,(ix+ENT_FRAME)
        cp      c
        ret     z                   ; nothing changed: no repaint
        ld      (ix+ENT_FRAME),c
        jp      pig_repose

; ---- pigs_taunt — every survivor laughs (called when a shot fizzles out) ----
pigs_taunt:
        ld      a,(pig_count)
        or      a
        ret     z
        ld      b,a
        ld      e,0
pt_loop:
        push    bc
        push    de
        call    pig_ptr
        ld      a,(ix+ENT_STATE)
        cp      ES_REST
        jr      nz,pt_next
        ld      (ix+ENT_FRAME),FR_FLY
        ld      (ix+ENT_ANIM),40
        call    pig_repose
pt_next:
        pop     de
        pop     bc
        inc     e
        djnz    pt_loop
        ret

; ----------------------------------------------------------------------------
;  pig state
; ----------------------------------------------------------------------------
pa_kind:        db      0
pg_self:        db      0
pm_val:         db      0
pu_moved:       db      0
pdr_skip:       db      #FF
