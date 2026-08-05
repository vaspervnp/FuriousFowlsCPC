; ============================================================================
;  FURIOUS FOWLS — shot.asm
;  The slingshot, the flight, and what happens when a bird meets a fort.
;
;  Position is 24-bit signed — an 8-bit fraction under a 16-bit pixel — so
;  a hard shot can sail off the top of the world and come back down without
;  wrapping. Velocity is 8.8 signed.
;
;  The bird is integrated SHOT_SUBSTEPS times a frame and probed as a single
;  point at its centre. That is deliberate, not lazy: at two substeps the
;  fastest shot moves about four pixels between probes, a quarter of a
;  16-pixel cell, so it cannot tunnel through a wall — and a point probe
;  against a grid is one lookup instead of an overlap test.
; ============================================================================

; ----------------------------------------------------------------------------
;  shot_reset — nothing in the air, aim back to a sensible default
; ----------------------------------------------------------------------------
shot_reset:
        xor     a
        ld      (sh_state),a
        ld      (sh_drawn),a
        ld      (sh_hits),a
        ld      (sh_rest),a
        ld      (charging),a
        ld      (aim_power),a
        ld      a,30                ; about 42 degrees: a decent opening lob
        ld      (aim_angle),a
        ret

; ============================================================================
;  Aiming. The bird waits in the pouch, hauled back along the reverse of
;  the launch direction by however much power is wound up, so the pull IS
;  the aim readout — no gauge needed.
; ============================================================================
shot_aim_pos:
        ld      a,(aim_power)       ; pull = power * PULL_MAX / POWER_MAX,
        srl     a                   ; near enough at /4 for POWER_MAX 60
        srl     a
        and     #FE                 ; ...in even steps, because every change
        ld      (sa_pull),a         ; costs a full erase-and-redraw and the
                                    ; blitter quantises x to even anyway

        ld      a,(aim_angle)       ; x = sling_x - 8 - cos(angle)*pull/128
        call    cos256
        ld      b,a
        ld      a,(sa_pull)
        call    mul_s8              ; HL = signed product
        call    div128
        ld      b,a
        ld      a,(sling_x)
        sub     8
        sub     b
        ld      l,a
        ld      h,0
        ld      (sa_x),hl

        ld      a,(aim_angle)       ; y = pouch - 16 + sin(angle)*pull/128
        call    sin256
        ld      b,a
        ld      a,(sa_pull)
        call    mul_s8
        call    div128
        ld      b,a
        ld      a,SLING_POUCH_Y-16
        add     a,b
        ld      l,a
        ld      h,0
        ld      (sa_y),hl
        ret

; ----------------------------------------------------------------------------
;  shot_draw_ready — put the waiting bird in the pouch, having first put the
;  background back where it used to be.
;
;  Winding the sling up takes twenty frames but only moves the bird about
;  fifteen pixels, so most of those frames would erase and redraw it in
;  exactly the same place — a third of a frame's work for no change at all.
;  Work out where it goes FIRST, and if that is where it already is, leave
;  the screen alone.
; ----------------------------------------------------------------------------
shot_draw_ready:
        ld      c,FR_READY
        ld      a,(aim_power)
        or      a
        jr      nz,sdr_frame
        ld      c,FR_IDLE           ; slack sling: it is only waiting
sdr_frame:
        ld      a,c
        ld      (sa_frame),a
        call    shot_aim_pos

        ld      a,(sh_drawn)
        or      a
        jr      z,sdr_redraw        ; nothing on screen yet
        ld      hl,(sa_x)
        ld      de,(sh_px)
        or      a
        sbc     hl,de
        jr      nz,sdr_redraw
        ld      hl,(sa_y)
        ld      de,(sh_py)
        or      a
        sbc     hl,de
        jr      nz,sdr_redraw
        ld      a,(sa_frame)
        ld      hl,sh_frame
        cp      (hl)
        ret     z                   ; same place, same pose: nothing to do
sdr_redraw:
        call    shot_erase
        ld      hl,(sa_x)
        ld      (sh_px),hl
        ld      hl,(sa_y)
        ld      (sh_py),hl
        ld      a,(sa_frame)
        ld      (sh_frame),a
        call    sling_band          ; the elastic, then the bird over its ends
        jp      shot_draw

; ----------------------------------------------------------------------------
;  sling_band — two lines from the fork tips to the pouch.
;
;  There is no sprite for this: the elastic changes shape every time the
;  pull changes, so it is drawn as lines and wiped by the aim erase, which
;  is why that rectangle covers the whole fork and not just the bird.
; ----------------------------------------------------------------------------
SLING_TIP_Y     equ SLING_CELL_Y+11 ; the grips, in world lines
SLING_TIP_DL    equ 11              ; ...and either side of the fork centre
SLING_TIP_DR    equ 10

sling_band:
        ld      a,(game_state)
        cp      GS_AIM
        ret     nz
        ld      a,(mode0_pen_bytes+PEN_BROWN)
        ld      (pp_pen),a

        ld      hl,(sh_px)          ; the pouch end, shared by both lines
        ld      de,CR_WIDTH/2
        add     hl,de
        ld      (ln_x1),hl
        ld      a,(sh_py)
        add     a,18
        ld      (ln_y1),a
        ld      a,SLING_TIP_Y
        ld      (ln_y0),a

        ld      a,(sling_x)
        sub     SLING_TIP_DL
        ld      l,a
        ld      h,0
        ld      (ln_x0),hl
        call    draw_line

        ld      a,(sling_x)
        add     a,SLING_TIP_DR
        ld      l,a
        ld      h,0
        ld      (ln_x0),hl
        jp      draw_line

; ============================================================================
;  shot_launch — turn the aim into a velocity and let go.
;    v = trig(angle) * power / 4, which tops out near 7.4 px/frame
; ============================================================================
shot_launch:
        ld      a,(aim_angle)
        call    cos256
        ld      b,a
        ld      a,(aim_power)
        call    mul_s8
        call    asr2
        ld      (sh_vx),hl

        ld      a,(aim_angle)
        call    sin256
        ld      b,a
        ld      a,(aim_power)
        call    mul_s8
        call    asr2
        call    neg16               ; screen y grows downward
        ld      (sh_vy),hl

        call    shot_erase          ; it leaves the pouch behind
        ld      hl,(sh_px)          ; seed the 24-bit position from where
        ld      a,l                 ; the bird actually was
        ld      (sh_x+1),a
        ld      a,h
        ld      (sh_x+2),a
        xor     a
        ld      (sh_x),a
        ld      hl,(sh_py)
        ld      a,l
        ld      (sh_y+1),a
        ld      a,h
        ld      (sh_y+2),a
        xor     a
        ld      (sh_y),a
        ld      (sh_hits),a
        ld      (sh_rest),a
        ld      (aim_power),a
        ld      (charging),a
        ld      (cam_free),a        ; the shot re-arms the camera follow
        ld      a,FR_FLY
        ld      (sh_frame),a
        ld      a,1
        ld      (sh_state),a
        ret

; ============================================================================
;  shot_update — one frame of flight. Returns Z when the shot is over.
; ============================================================================
shot_update:
        ld      a,(sh_state)
        or      a
        ret     z

        ld      hl,(sh_vy)          ; gravity, once per frame
        ld      de,GRAVITY
        add     hl,de
        bit     7,h                 ; terminal velocity is a FALLING limit:
        jr      nz,su_vy_ok         ; a rising bird is already negative and
        ld      a,h                 ; must not be clamped to it
        cp      VY_TERMINAL
        jr      c,su_vy_ok
        ld      hl,VY_TERMINAL*256
su_vy_ok:
        ld      (sh_vy),hl

        call    shot_erase
        ld      a,SHOT_SUBSTEPS
        ld      (su_steps),a
su_step:
        call    shot_integrate
        call    shot_collide
        ld      a,(sh_state)
        or      a
        jr      z,su_done
        ld      a,(su_steps)
        dec     a
        ld      (su_steps),a
        jr      nz,su_step

        call    shot_settle_check
        ld      a,(sh_state)
        or      a
        jr      z,su_done
        call    shot_draw
        ld      a,1
        or      a
        ret
su_done:
        xor     a
        ret

; ---- shot_integrate — advance the position by half a frame's velocity ------
shot_integrate:
        ld      hl,(sh_vx)
        sra     h
        rr      l
        ex      de,hl
        ld      hl,sh_x
        call    pos_add
        ld      hl,(sh_vy)
        sra     h
        rr      l
        ex      de,hl
        ld      hl,sh_y
        jp      pos_add

; ---- pos_add — HL = 3-byte position, DE = signed 8.8 delta -----------------
pos_add:
        ld      a,d                 ; sign-extend the delta's integer part
        add     a,a
        sbc     a,a
        ld      b,a
        ld      a,(hl)
        add     a,e
        ld      (hl),a
        inc     hl
        ld      a,(hl)
        adc     a,d
        ld      (hl),a
        inc     hl
        ld      a,(hl)
        adc     a,b
        ld      (hl),a
        ret

; ============================================================================
;  shot_collide — probe the bird's centre against the ground and the grid.
; ============================================================================
SHOT_CX         equ 8               ; the bird's middle, within its 16x32 cell
SHOT_CY         equ 19

shot_collide:
        ld      hl,(sh_x+1)         ; centre, in world pixels
        ld      de,SHOT_CX
        add     hl,de
        ld      (sc_cx),hl
        ld      hl,(sh_y+1)
        ld      de,SHOT_CY
        add     hl,de
        ld      (sc_cy),hl

; ---- did it leave the world? -----------------------------------------------
        ld      hl,(sc_cx)
        bit     7,h
        jp      nz,sc_gone
        ld      de,WORLD_PX
        or      a
        sbc     hl,de
        jp      nc,sc_gone

; ---- the ground ------------------------------------------------------------
        ld      hl,(sc_cy)
        ld      de,GROUND_Y-BIRD_R
        or      a
        sbc     hl,de
        jr      c,sc_grid
        jp      sc_ground

; ---- and the fort ----------------------------------------------------------
sc_grid:
        ld      hl,(sc_cy)
        ld      de,GRID_TOP_Y
        or      a
        sbc     hl,de
        ret     c                   ; still above the grid: nothing to hit
        ld      a,h
        or      a
        ret     nz
        ld      a,l
        srl     a
        srl     a
        srl     a
        srl     a
        cp      GRID_H
        ret     nc
        ld      c,a                 ; C = row
        ld      hl,(sc_cx)
        ld      a,l
        srl     h
        rr      a
        srl     h
        rr      a
        srl     h
        rr      a
        srl     h
        rr      a
        cp      GRID_W
        ret     nc
        ld      b,a                 ; B = column
        call    grid_at
        ld      a,(hl)
        cp      GRID_EMPTY
        ret     z                   ; clear air
        ld      (sc_cell),a
        call    shot_speed          ; A = |vx| + |vy| in whole pixels
        ld      (sc_speed),a
        ld      b,DMG_PER_SPEED
        call    mul8
        ld      (sc_dmg),a

        ld      a,(sc_cell)
        bit     7,a
        jr      nz,sc_hit_pig
        ld      e,a
        call    block_ptr
        ld      a,(sc_dmg)
        call    block_hit
        ld      hl,(sh_vx)          ; a bird that hits and keeps going drags
        ld      a,h                 ; the fort the way it is travelling
        or      l
        jr      z,sc_bounce
        ld      a,h
        rla
        ld      a,1
        jr      nc,sc_shove_go
        ld      a,#FF
sc_shove_go:
        call    block_shove
        jr      sc_bounce
sc_hit_pig:
        and     #7F
        ld      e,a
        call    pig_ptr
        ld      a,(sc_dmg)
        call    pig_hit
        ; fall through

; ---- bounce: back out of the cell, flip the dominant axis, lose energy -----
sc_bounce:
        ld      a,(sh_hits)
        inc     a
        ld      (sh_hits),a

        ld      hl,(sh_vx)          ; step back out of what we just hit
        sra     h
        rr      l
        call    neg16
        ex      de,hl
        ld      hl,sh_x
        call    pos_add
        ld      hl,(sh_vy)
        sra     h
        rr      l
        call    neg16
        ex      de,hl
        ld      hl,sh_y
        call    pos_add

        ld      hl,(sh_vy)          ; whichever axis was carrying the shot
        call    abs16               ; is the one that reverses
        ld      (sc_ay),hl
        ld      hl,(sh_vx)
        call    abs16
        ld      de,(sc_ay)
        or      a
        sbc     hl,de
        jr      nc,sc_flip_x
        ld      hl,(sh_vy)
        call    neg16
        ld      (sh_vy),hl
        jr      sc_damp
sc_flip_x:
        ld      hl,(sh_vx)
        call    neg16
        ld      (sh_vx),hl
sc_damp:
        ld      hl,(sh_vx)
        call    damp16
        ld      (sh_vx),hl
        ld      hl,(sh_vy)
        call    damp16
        ld      (sh_vy),hl
        ret

; ---- the turf: a squashy bounce, then a roll to a halt ---------------------
sc_ground:
        ld      hl,GROUND_Y-BIRD_R-SHOT_CY  ; sit the bird ON the grass
        ld      a,l
        ld      (sh_y+1),a
        ld      a,h
        ld      (sh_y+2),a
        xor     a
        ld      (sh_y),a

        call    shot_speed
        cp      3
        jr      c,sc_stop           ; too slow to bounce: it just lands
        ld      hl,(sh_vy)
        call    neg16
        call    damp16
        call    damp16              ; the turf keeps most of it
        ld      (sh_vy),hl
        ld      hl,(sh_vx)          ; and it rolls off what is left
        call    damp16
        ld      (sh_vx),hl
        ret
sc_stop:
        ld      hl,0
        ld      (sh_vx),hl
        ld      (sh_vy),hl
        xor     a
        ld      (sh_state),a
        ret

sc_gone:
        xor     a                   ; over the horizon: that one is spent
        ld      (sh_state),a
        ret

; ---- shot_settle_check — a bird that has stopped mattering ends the shot ---
shot_settle_check:
        ld      hl,(sh_y+1)         ; a slow bird in mid-air has not stopped,
        ld      de,GROUND_Y-BIRD_R-SHOT_CY-2    ; it is at the top of its arc
        or      a
        sbc     hl,de
        jr      c,ssc_moving
        call    shot_speed
        cp      REST_SPEED+1
        jr      nc,ssc_moving
        ld      a,(sh_rest)
        inc     a
        ld      (sh_rest),a
        cp      12
        ret     c
        xor     a
        ld      (sh_state),a
        ret
ssc_moving:
        xor     a
        ld      (sh_rest),a
        ret

; ---- shot_speed — A = |vx| + |vy|, in whole pixels per frame ---------------
shot_speed:
        ld      hl,(sh_vx)
        call    abs16
        ld      a,h
        ld      c,a
        ld      hl,(sh_vy)
        call    abs16
        ld      a,h
        add     a,c
        ret     nc
        ld      a,#FF
        ret

; ============================================================================
;  Drawing the bird
; ============================================================================
shot_draw:
        ld      a,(sh_state)
        or      a
        jr      z,sd_pos            ; on the sling: sh_px/py are already set
        ld      hl,(sh_x+1)
        ld      (sh_px),hl
        ld      hl,(sh_y+1)
        ld      (sh_py),hl
sd_pos:
        ld      a,(sh_frame)
        ld      c,a
        ld      a,(sh_type)
        call    art_for_creature
        ld      (sp_art),hl
        ld      hl,(sh_px)
        ld      (sp_x),hl
        ld      hl,(sh_py)
        ld      (sp_y),hl
        ld      a,CR_BYTES_PER_ROW
        ld      (sp_w),a
        ld      a,CR_HEIGHT
        ld      (sp_h),a
        ld      a,1
        ld      (sh_drawn),a
        jp      spr_blit

; ----------------------------------------------------------------------------
;  shot_erase — put the world back where the bird was last drawn.
;  A 16x32 sprite at an arbitrary x touches five char columns, so that is
;  what we rebuild.
; ----------------------------------------------------------------------------
shot_erase:
        ld      a,(sh_drawn)
        or      a
        ret     z
        xor     a
        ld      (sh_drawn),a
        ld      a,(game_state)
        cp      GS_AIM
        jr      z,se_aim            ; on the sling: the elastic has to go too
        ld      hl,(sh_px)
        bit     7,h
        jr      z,se_xok
        ld      hl,0
se_xok:
        srl     h                   ; char column = x / 4
        rr      l
        srl     h
        rr      l
        ld      a,l
        ld      (rr_col0),a
        ld      a,5
        ld      (rr_ncol),a
        ld      hl,(sh_py)
        bit     7,h
        jr      z,se_yok
        ld      hl,0
se_yok:
        ld      a,l
        ld      (rr_y0),a
        ld      a,CR_HEIGHT
        ld      (rr_n),a
        jp      redraw_rect

;  The aim rectangle is the bird's box UNION the elastic's, worked out each
;  time rather than fixed. That matters more than it looks: a whole game
;  frame of aiming costs about one display frame, so a rectangle twice the
;  size it needs to be does not merely cost time, it puts the erase and the
;  redraw in DIFFERENT displayed frames and the bird visibly blinks.
se_aim:
        ld      a,(sling_x)         ; left edge: the far grip or the bird
        sub     SLING_TIP_DL
        ld      c,a
        ld      a,(sh_px)
        cp      c
        jr      c,se_x0
        ld      a,c
se_x0:
        srl     a
        srl     a
        ld      (rr_col0),a
        ld      c,a

        ld      a,(sling_x)         ; right edge: the near grip or the bird
        add     a,SLING_TIP_DR
        ld      b,a
        ld      a,(sh_px)
        add     a,CR_WIDTH-1
        cp      b
        jr      nc,se_x1
        ld      a,b
se_x1:
        srl     a
        srl     a
        sub     c
        inc     a
        ld      (rr_ncol),a

        ld      a,(sh_py)           ; top: the bird is always above the grips
        ld      c,a
        cp      SLING_TIP_Y
        jr      c,se_y0
        ld      c,SLING_TIP_Y
se_y0:
        ld      a,c
        ld      (rr_y0),a
        ld      b,a
        ld      a,(sh_py)           ; bottom: ...and always below them
        add     a,CR_HEIGHT
        ld      c,a
        ld      a,SLING_TIP_Y+2
        cp      c
        jr      c,se_y1
        ld      c,a
se_y1:
        ld      a,c
        sub     b
        ld      (rr_n),a
        jp      redraw_rect

; ============================================================================
;  Signed helpers
; ============================================================================

; ---- mul_s8 — A = unsigned 0..255, B = signed -128..127 -> HL = A*B --------
mul_s8:
        ld      c,a
        ld      a,b
        or      a
        jp      p,ms_pos
        neg
        ld      b,a
        ld      a,c
        call    mul_u8
        jp      neg16
ms_pos:
        ld      a,c
        ; fall through

; ---- mul_u8 — A * B -> HL, both unsigned -----------------------------------
mul_u8:
        ld      l,a
        ld      h,0
        ld      e,l
        ld      d,h
        ld      hl,0
        ld      a,b
        or      a
        ret     z
mu_loop:
        add     hl,de
        dec     a
        jr      nz,mu_loop
        ret

; ---- neg16 / abs16 / asr2 / div128 / damp16 -------------------------------
neg16:
        ld      a,h
        cpl
        ld      h,a
        ld      a,l
        cpl
        ld      l,a
        inc     hl
        ret

abs16:
        bit     7,h
        ret     z
        jr      neg16

asr2:
        sra     h
        rr      l
        sra     h
        rr      l
        ret

div128:                             ; HL signed / 128 -> A  (an 8.8 scale
        add     hl,hl               ; down by 128 is a shift of one and a
        ld      a,h                 ; byte grab)
        ret

;  damp16 — keep BOUNCE_NUM/BOUNCE_DEN of a signed velocity. Bounces are
;  what stop a shot ever settling into a perpetual jitter, so this is the
;  one place the numbers are worth tuning by feel.
damp16:
        push    hl
        call    abs16
        ld      d,h                 ; x3, then >>3: three eighths, with no
        ld      e,l                 ; multiply and no divide
        add     hl,hl
        add     hl,de
        ld      b,3
dm_div:
        srl     h
        rr      l
        djnz    dm_div
        pop     de
        bit     7,d
        ret     z
        jp      neg16
        assert  BOUNCE_NUM == 3 && BOUNCE_DEN == 8

; ---- sin256 / cos256 — A = angle -> A = signed sine, amplitude 127 --------
sin256:
        ld      l,a
        ld      h,sin_table/256
        ld      a,(hl)
        ret
cos256:
        add     a,64
        jr      sin256

; ----------------------------------------------------------------------------
;  shot state
; ----------------------------------------------------------------------------
su_steps:       db      0
sa_pull:        db      0
sa_frame:       db      0
sa_x:           dw      0
sa_y:           dw      0
sc_cx:          dw      0
sc_cy:          dw      0
sc_ay:          dw      0
sc_cell:        db      0
sc_speed:       db      0
sc_dmg:         db      0
