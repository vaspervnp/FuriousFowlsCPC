; ============================================================================
;  FURIOUS FOWLS — level.asm
;  Unpacking one of the fifty records into the live tables.
;
;  The record format is documented in tools/levels.py, which writes it; the
;  two have to be read together. Nothing here allocates or validates —
;  levels.py has already refused to compile a fort with a pig in a wall or
;  a piece off the grid, so this is pure unpacking.
; ============================================================================

; ----------------------------------------------------------------------------
;  level_load — A = level index (0 .. LEVEL_COUNT-1)
; ----------------------------------------------------------------------------
level_load:
        ld      (level_no),a
        call    settle_ping         ; a new fort settles once
        call    blocks_reset        ; both of these are LDIRs, so they go
        call    pigs_reset          ; FIRST — HL is the record pointer from
        xor     a                   ; here to the end of the routine
        ld      (scen_count),a
        ld      a,(level_no)
        ld      l,a
        ld      h,0
        add     hl,hl
        ld      de,level_ofs
        add     hl,de
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        ld      hl,level_data
        add     hl,de               ; HL walks the record from here on

        ld      a,(hl)
        ld      (block_set),a
        inc     hl
        ld      a,(hl)              ; the sky and the ground under it
        ld      (level_theme),a
        push    hl
        call    rot_build           ; the tilted tiles for THIS material set
        call    scene_init          ; ...and this fort's sky and strata
        pop     hl
        inc     hl
        ld      a,(hl)              ; the fork's x, stored halved
        add     a,a
        ld      (sling_x),a
        inc     hl
        ld      a,(hl)
        ld      (bird_count),a
        inc     hl
        push    hl                  ; the six bird slots, however many are
        ld      de,bird_queue       ; actually used
        ld      bc,MAX_BIRDS
        ldir
        pop     hl
        ld      de,MAX_BIRDS
        add     hl,de
        ld      a,(hl)
        ld      (ll_nscen),a
        inc     hl
        ld      a,(hl)
        ld      (ll_nblk),a
        inc     hl
        ld      a,(hl)
        ld      (ll_npig),a
        inc     hl

; ---- scenery: three bytes each, straight into the table --------------------
        ld      a,(ll_nscen)
        or      a
        jr      z,ll_sling
        ld      b,a
        ld      de,scen_tab
ll_scen:
        push    bc
        ld      bc,SCEN_ENT
        ldir                        ; cell, char column, top line
        pop     bc
        djnz    ll_scen
        ld      a,(ll_nscen)
        ld      (scen_count),a

; ---- and the slingshot, which every level has and no level stores ----------
ll_sling:
        push    hl
        ld      a,(scen_count)
        ld      l,a
        ld      h,0
        ld      e,a
        ld      d,0
        add     hl,hl               ; count * 2
        add     hl,de               ; count * 3
        ld      de,scen_tab
        add     hl,de
        ld      a,(sling_x)         ; the cell sits half its width to the
        sub     16                  ; left of the fork
        srl     a
        srl     a                   ; ...as a char column
        ld      c,a
        ld      (hl),SC_SLING_BACK
        inc     hl
        ld      (hl),c
        inc     hl
        ld      (hl),SLING_CELL_Y
        inc     hl
        ld      (hl),SC_SLING_FRONT
        inc     hl
        ld      (hl),c
        inc     hl
        ld      (hl),SLING_CELL_Y
        ld      a,(scen_count)
        add     a,2
        ld      (scen_count),a
        pop     hl

; ---- blocks ----------------------------------------------------------------
        ld      a,(ll_nblk)
        or      a
        jr      z,ll_pigs
        ld      b,a
ll_blk:
        push    bc
        ld      a,(hl)              ; piece in the low nibble, column's low
        inc     hl                  ; four bits in the high one
        ld      c,a
        ld      b,(hl)
        inc     hl
        push    hl
        call    unpack_cell         ; -> A = piece, B = column, C = row
        call    block_add
        pop     hl
        pop     bc
        djnz    ll_blk

; ---- pigs ------------------------------------------------------------------
ll_pigs:
        ld      a,(ll_npig)
        or      a
        jr      z,ll_done
        ld      b,a
ll_pig:
        push    bc
        ld      a,(hl)
        inc     hl
        ld      c,a
        ld      b,(hl)
        inc     hl
        push    hl
        call    unpack_cell
        call    pig_add
        pop     hl
        pop     bc
        djnz    ll_pig
ll_done:
        ret

; ----------------------------------------------------------------------------
;  unpack_cell — C = kind | (col AND 15) << 4, B = row | (col AND 16)
;             -> A = kind, B = column, C = row
;  The grid is twenty wide, so the column needs a fifth bit; it rides in the
;  row byte, where rows only ever use four.
; ----------------------------------------------------------------------------
unpack_cell:
        ld      a,b                 ; the beam length rides in the top three
        rlca                        ; bits of the row byte
        rlca
        rlca
        and     #07
        inc     a
        ld      (ba_len),a
        ld      a,c
        and     #0F
        ld      d,a                 ; D = the piece or pig kind
        ld      a,c
        and     #F0
        rrca
        rrca
        rrca
        rrca
        ld      e,a                 ; E = the column's low nibble
        ld      a,b
        and     #10
        or      e
        ld      e,a                 ; E = the whole column
        ld      a,b
        and     #0F
        ld      c,a                 ; C = row
        ld      b,e                 ; B = column
        ld      a,d
        ret

ll_nscen:       db      0
ll_nblk:        db      0
ll_npig:        db      0
