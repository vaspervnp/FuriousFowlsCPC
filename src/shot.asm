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
        ld      c,FR_IDLE           ; slack sling: it is only waiting...
        ld      a,(frame_counter)   ; ...and a bird that is waiting blinks,
        and     127                 ; the same as the ones on the title
        cp      5
        jr      nc,sdr_frame
        ld      c,FR_BLINK
sdr_frame:
        ld      a,c
        ld      (sa_frame),a
        call    shot_aim_pos

        xor     a
        ld      (se_narrow),a
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
;  The aim dots depend on the ANGLE, which at zero pull moves neither the
;  bird nor its pose. Leaving that out of this test is what made up and
;  down look dead in the first place.
;  ONLY THE AIM MOVED. Five pixels changed, and five pixels is five byte
;  writes — not a rebuild of the scenery under the whole aim rectangle,
;  which is what made changing the angle flicker.
        ld      a,(aim_angle)
        ld      hl,ad_angle
        cp      (hl)
        jr      nz,sdr_aim_only
;  Only the POSE left. A blink moves nothing — not the bird, not the
;  elastic, not the dots — so erasing the whole aim rectangle for it costs
;  seven times what it needs to and leaves the bird off the screen for most
;  of the blink. Narrow the erase to the bird's own box.
        ld      a,(sa_frame)
        ld      hl,sh_frame
        cp      (hl)
        ret     z                   ; same place, same pose, same aim
        ld      a,1
        ld      (se_narrow),a
        jr      sdr_redraw

sdr_aim_only:
        ld      a,(aim_angle)
        ld      (ad_angle),a
        call    aim_undot           ; put back exactly what the old dots
        jp      aim_dots            ; covered, then draw the new five

sdr_redraw:
        ld      a,(aim_angle)
        ld      (ad_angle),a
;  Lift the dots BEFORE the erase, so what aim_dots files away afterwards
;  is background and not a dot it drew itself.
        call    aim_undot
        ld      a,(aim_power)       ; a creak per notch of the pull, and only
        or      a                   ; while it IS a pull: this same path also
        jr      z,sdr_go            ; runs for a change of aim and for putting
        ld      a,SND_STRETCH       ; the next bird in the pouch
        ld      b,0
        call    snd_fx
sdr_go:
        call    shot_erase
        ld      hl,(sa_x)
        ld      (sh_px),hl
        ld      hl,(sa_y)
        ld      (sh_py),hl
        ld      a,(sa_frame)
        ld      (sh_frame),a
;  A BLINK changes the bird and nothing else. The elastic and the aim dots
;  are exactly where they were, and redrawing them means erasing seventy-odd
;  pixels and putting them straight back — which is the flicker you see on
;  the rope while the eyes close.
        ld      a,(se_narrow)
        or      a
        jp      nz,shot_draw
        call    sling_band          ; the elastic, then the bird over its ends
        call    shot_draw
        jp      aim_dots

; ----------------------------------------------------------------------------
;  shot_draw_rect — the bird is furniture too, as far as an erase is
;  concerned. Anything that repaints the background where it is standing
;  has to put it back: the scroll seam rebuilds a whole column every time
;  the camera moves, so without this, panning away from the sling and back
;  leaves an empty fork.
;
;  (sdr_skip) is raised while the bird is erasing ITSELF, or the erase
;  would helpfully paint it straight back.
; ----------------------------------------------------------------------------
shot_draw_rect:
        ld      a,(sh_drawn)
        or      a
        ret     z
        ld      a,(sdr_skip)
        or      a
        ret     nz
        call    shot_in_rect
        ret     c
        call    sling_band          ; and its elastic, if it is on the sling
        call    shot_draw
        jp      aim_dots

; ----------------------------------------------------------------------------
;  aim_dots — five dots, four pixels apart, along the line the bird will
;  leave on: twenty pixels of it, broken, so it reads as an aim and not as
;  another piece of the slingshot.
;
;  Without this, UP and DOWN move a number with no consequence on screen.
;  The bird's resting place is pull * cos(angle), so at zero pull every
;  angle puts it in exactly the same pixel and the aim looks broken even
;  though it is working.
; ----------------------------------------------------------------------------
AIM_DOT_N       equ 5
AIM_DOT_STEP    equ 6
;  Far enough out that every dot MOVES. AIM_RATE is one 256th of a turn,
;  about 1.4 degrees, and a dot sixteen pixels from the pivot shifts four
;  tenths of a pixel for that — so the innermost one sat still through four
;  presses in a row and read as something left behind rather than as an
;  aim. At twenty-six pixels and out, they all travel.
AIM_DOT_START   equ 26

aim_dots:
        ld      a,(game_state)
        cp      GS_AIM
        ret     nz
        call    aim_undot           ; TAKE THE OLD FIVE OFF FIRST. This is
                                    ; also reached from the restack, where
                                    ; nothing has undotted for us — and
                                    ; recording a dot as its own background
                                    ; means the next erase paints it back.
        call    px_use_dots
        ld      a,(mode0_pen_bytes+PEN_WHITE)
        ld      (pp_pen),a
        ld      a,AIM_DOT_START
        ld      (ad_d),a
ad_loop:
        ld      a,(aim_angle)
        call    cos256
        ld      b,a
        ld      a,(ad_d)
        call    mul_s8
        call    div128              ; A = the x offset, signed
        ld      e,a
        ld      d,0
        bit     7,a
        jr      z,ad_dx
        dec     d
ad_dx:
        ld      hl,(sh_px)
        add     hl,de
        ld      de,CR_WIDTH/2       ; from the middle of the bird
        add     hl,de
        push    hl
        ld      a,(aim_angle)
        call    sin256
        ld      b,a
        ld      a,(ad_d)
        call    mul_s8
        call    div128
        ld      b,a
        ld      a,(sh_py)
        add     a,CR_HEIGHT/2
        sub     b                   ; screen y grows downward
        pop     hl
        call    plot_px
        call    px_keep
        ld      a,(ad_d)
        add     a,AIM_DOT_STEP
        ld      (ad_d),a
        cp      AIM_DOT_START+AIM_DOT_STEP*AIM_DOT_N
        jr      c,ad_loop
        ret

; ---- px_keep / px_undo — a scatter of single pixels, kept and put back ----
;  The aim dots and the elastic are the same problem: a handful of pixels
;  spread over a box far bigger than they are, which the erase-by-rebuild
;  path has to reconstruct in full. Keeping the byte each one covered turns
;  the erase into one write per pixel. (px_base) says which table is being
;  filled, so the two share every line of this.
;
;  plot_px writes nothing when a pixel is clipped, and then pp_addr still
;  holds the last one it DID write — hence the compare, rather than trusting
;  that a call means a pixel.
px_keep:
        ld      hl,(pp_addr)
        ld      a,h
        or      l
        ret     z                   ; plot_px clipped it: nothing to keep
        ld      hl,0
        ld      (pp_addr),hl
        ld      hl,(px_n)
        ld      a,(px_max)
        cp      (hl)
        ret     z                   ; the table is full: better to leave a
        ld      b,(hl)              ; pixel than to run off the end of it
        inc     (hl)
        ld      l,b
        ld      h,0
        ld      d,h
        ld      e,l
        add     hl,hl
        add     hl,de               ; index * 3
        ld      de,(px_base)
        add     hl,de
        ld      de,(pp_addr)
        ld      (hl),e
        inc     hl
        ld      (hl),d
        inc     hl
        ld      a,(pp_prev)
        ld      (hl),a
        ret

;  BACKWARDS. Two pixels of a line can share a byte, and then the second
;  slot kept that byte with the first pixel already in it. Unwinding in the
;  order they were drawn would leave that pixel behind; unwinding in
;  reverse ends on the slot that holds the true background.
px_undo:
        ld      hl,(px_n)
        ld      a,(hl)
        or      a
        jr      z,px_forget
        ld      b,a
        ld      l,a
        ld      h,0
        ld      d,h
        ld      e,l
        add     hl,hl
        add     hl,de               ; count * 3, one past the last slot
        ld      de,(px_base)
        add     hl,de
pu_next:
        dec     hl
        ld      a,(hl)
        dec     hl
        ld      d,(hl)
        dec     hl
        ld      e,(hl)
        ld      (de),a
        djnz    pu_next
px_forget:
        ld      hl,(px_n)
        ld      (hl),0
        ret

px_use_dots:
        ld      hl,ad_slot
        ld      (px_base),hl
        ld      hl,ad_n
        ld      (px_n),hl
        ld      a,AIM_DOT_N
        ld      (px_max),a
        ret

px_use_band:
        ld      hl,band_slot
        ld      (px_base),hl
        ld      hl,band_n
        ld      (px_n),hl
        ld      a,BAND_SLOTS
        ld      (px_max),a
        ret

px_base:        dw      0
px_n:           dw      0
px_max:         db      0

; ---- the two users -------------------------------------------------------
aim_undot:
        call    px_use_dots
        jp      px_undo

band_undo:
        call    px_use_band
        jp      px_undo

ad_d:           db      0
ad_n:           db      0
ad_last:        dw      0
ad_slot:        ds      AIM_DOT_N*3
ad_angle:       db      #FF     ; the aim the dots on screen were drawn for

; ---- shot_in_rect — CF set if the bird's box misses the redraw window ------
shot_in_rect:
        ld      hl,(sh_px)
        bit     7,h
        jr      nz,sir_no
        ld      a,h
        or      a
        jr      nz,sir_no
        srl     h                   ; its leftmost char column
        rr      l
        srl     h
        rr      l
        ld      c,l
        ld      a,(rr_col0)
        ld      b,a
        ld      a,(rr_ncol)
        add     a,b
        dec     a
        cp      c
        jr      c,sir_no            ; the bird starts right of the window
        ld      a,c
        add     a,4
        cp      b
        jr      c,sir_no            ; ...or ends left of it
        ld      a,(sh_py)
        ld      c,a
        ld      a,(rr_y0)
        ld      b,a
        ld      a,(rr_n)
        add     a,b
        dec     a
        cp      c
        jr      c,sir_no
        ld      a,c
        add     a,CR_HEIGHT-1
        cp      b
        jr      c,sir_no
        or      a                   ; CF = 0: it overlaps
        ret
sir_no:
        scf
        ret

; ============================================================================
;  The bird's backing store.
;
;  Every other sprite is erased by REBUILDING the scene underneath it: five
;  columns of background, scenery run-streams, camera clipping, and a
;  restack of everything else standing there. That is a lot of moving parts
;  to get exactly right sixty times a second, and when one of them misses,
;  the sprite stays on screen for good — a bird in flight leaves a trail of
;  itself all the way across the level.
;
;  So the bird rebuilds nothing. Before it is drawn it KEEPS the pixels it
;  is about to cover, and erasing is putting them back. Whatever it covered
;  is exactly what it restores; there is nothing left to get wrong. It also
;  fits in a frame, which the rebuild did not — so the flicker goes too.
;
;  Only while it is FLYING. On the sling the elastic has to be erased as
;  well, and that reaches well outside the bird's own box.
; ============================================================================
shot_save:
        call    spr_clip            ; the SAME rectangle the blit will touch
        jr      c,sv_none
        ld      a,(sb_byte0)
        ld      (bk_byte0),a
        ld      a,(sb_nblit)
        ld      (bk_nblit),a
        ld      a,(sb_y)
        ld      (bk_y),a
        ld      a,(sb_rows)
        ld      (bk_rows),a
        ld      (bk_left),a
        ld      hl,shot_back
        ld      (bk_ptr),hl
        ld      a,(sb_y)
        ld      c,a
        call    sb_addr
sv_row:
        ld      de,(bk_ptr)
        ld      a,(bk_nblit)
        ld      b,a
        push    hl
sv_pix:
        ld      a,(hl)
        ld      (de),a
        inc     de
        inc     hl                  ; next byte, with the ring fold
        ld      a,l
        or      a
        jr      nz,sv_next
        ld      a,h
        and     7
        jr      nz,sv_next
        ld      a,h
        sub     8
        ld      h,a
sv_next:
        djnz    sv_pix
        ld      (bk_ptr),de
        pop     hl
        ld      a,(bk_left)
        dec     a
        ld      (bk_left),a
        ret     z
        inc     c
        ld      a,c
        and     7
        jr      z,sv_newrow
        ld      a,h                 ; same char row: exactly +#800
        add     a,8
        ld      h,a
        jr      sv_row
sv_newrow:
        call    sb_addr
        jr      sv_row
sv_none:
        xor     a
        ld      (bk_rows),a
        ret

; ---- shot_restore — put the kept pixels back where they came from ---------
shot_restore:
        ld      a,(bk_rows)
        or      a
        ret     z
        ld      (bk_left),a
        ld      a,(bk_byte0)
        ld      (sb_byte0),a        ; sb_addr works from this
        ld      hl,shot_back
        ld      (bk_ptr),hl
        ld      a,(bk_y)
        ld      c,a
        call    sb_addr
rs_row:
        ld      de,(bk_ptr)
        ld      a,(bk_nblit)
        ld      b,a
        push    hl
rs_pix:
        ld      a,(de)
        ld      (hl),a
        inc     de
        inc     hl
        ld      a,l
        or      a
        jr      nz,rs_next
        ld      a,h
        and     7
        jr      nz,rs_next
        ld      a,h
        sub     8
        ld      h,a
rs_next:
        djnz    rs_pix
        ld      (bk_ptr),de
        pop     hl
        ld      a,(bk_left)
        dec     a
        ld      (bk_left),a
        ret     z
        inc     c
        ld      a,c
        and     7
        jr      z,rs_newrow
        ld      a,h
        add     a,8
        ld      h,a
        jr      rs_row
rs_newrow:
        call    sb_addr
        jr      rs_row

; ---- shot_lift / shot_drop — brackets for anything that rebuilds the
;      background where the bird happens to be standing.
; ----------------------------------------------------------------------------
shot_lift:
        xor     a
        ld      (bk_up),a
        ld      a,(sh_state)
        or      a
        ret     z                   ; not flying: the old restack rule
        ld      a,(sh_drawn)
        or      a
        ret     z
        call    shot_in_rect
        ret     c
        ld      a,1
        ld      (bk_up),a
        xor     a
        ld      (sh_drawn),a
        jp      shot_restore

shot_drop:
        ld      a,(bk_up)
        or      a
        jp      z,shot_draw_rect
        xor     a
        ld      (bk_up),a
        jp      shot_draw           ; re-keeps the new background first

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
        call    band_undo           ; the old elastic comes off before the
        call    px_use_band         ; new one is filed away
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
        ld      (cam_hit),a         ; ...and has not hit anything yet
        ld      a,FR_FLY
        ld      (sh_frame),a
        ld      a,SND_LAUNCH        ; the twang
        ld      b,0
        call    snd_fx
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

;  The erase used to happen HERE, before the physics — which left the bird
;  off the screen for the whole of the integration and the collision sweep.
;  At two or three display frames to a game frame that is a bird you can see
;  through. It is now done immediately before the redraw, so the gap the eye
;  gets is two blits wide instead of a whole update.
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
        call    shot_erase          ; ...and back again, in one breath
        call    shot_draw
        ld      a,1
        or      a
        ret
; ---- the shot is over. What is left of it stays on the screen --------------
;  A bird that vanishes the instant it stops reads as a bug: the wreck where
;  it landed is part of the picture, and the restack keeps putting it back
;  while the fort finishes coming down. The one case where there is nothing
;  to draw is a bird that left the world, and that is also the one case the
;  player most wants told about.
su_done:
        call    shot_erase
        ld      hl,(sh_x+1)         ; still inside the world?
        bit     7,h
        jr      nz,su_lost
        ld      de,WORLD_PX
        or      a
        sbc     hl,de
        jr      nc,su_lost
        call    shot_draw           ; leave it lying where it came to rest
        ld      a,(cam_hit)         ; ...and did it ever hit anything?
        or      a
        jr      nz,su_end
su_lost:
        ld      a,SND_MISS          ; only dirt, or over the horizon
        ld      b,0
        call    snd_fx
su_end:
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
;  ABOVE THE TOP OF THE WORLD IS NOT BELOW THE BOTTOM OF IT. The compare
;  below is unsigned, so a bird at y = -16 arrives here as #FFF0 and reads
;  as far underground — which snapped it onto the grass and ended the turn
;  the moment a high lob cleared the screen.
        ld      hl,(sc_cy)
        bit     7,h
        jr      nz,sc_grid
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

        ld      hl,(sh_vx)          ; which way the blow was travelling —
        ld      a,h                 ; the vector goes into the fort with the
        or      l                   ; force, not just the force
        ld      c,1
        jr      z,sc_dir_done
        bit     7,h
        jr      z,sc_dir_done
        ld      c,#FF
sc_dir_done:
        call    cam_mark_hit        ; the camera wants to show this
        ld      a,SND_WOOD          ; ...and the ear wants to hear it
        ld      b,1
        call    snd_fx
        ld      a,(sc_cell)
        bit     7,a
        jr      nz,sc_hit_pig
        ld      (is_seed),a
        ld      a,(sc_dmg)
        call    impact_spread       ; C = direction, A = force at the hit
        jr      sc_bounce
sc_hit_pig:
        and     #7F
        ld      e,a
        call    pig_ptr
        ld      a,(sc_dmg)
        call    pig_hit
        ; fall through

; ---- cam_mark_hit — remember where the fort was struck ---------------------
;  The bird's middle at the moment of contact. Preserves C, which is
;  carrying the impact direction to impact_spread.
; ----------------------------------------------------------------------------
cam_mark_hit:
        ld      hl,(sh_px)
        ld      de,CR_WIDTH/2
        add     hl,de
        ld      (cam_hit_x),hl
        ld      a,1
        ld      (cam_hit),a
        ret

; ---- bounce: back out of the cell, flip the dominant axis, lose energy -----
sc_bounce:
        ld      a,(sh_hits)
        inc     a
        ld      (sh_hits),a
        cp      MAX_HITS            ; a bird rattling around inside a fort
        jr      c,sc_bounce_on      ; can bounce between two pieces without
        xor     a                   ; ever slowing enough to look settled,
        ld      (sh_state),a        ; and the turn would never end
        ret
sc_bounce_on:

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
        bit     7,h                 ; it is at the top of its arc — and the
        jr      nz,ssc_moving       ; slowest point of a lob is exactly where
                                    ; it is most likely to be off the screen,
                                    ; where this compare would call it landed
        ld      de,GROUND_Y-BIRD_R-SHOT_CY-2
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
;  Keep what it is about to cover, ALWAYS — not only in flight. On the
;  sling the pixels underneath include the elastic, so a blink can put the
;  bird back without rebuilding anything.
        call    shot_save
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
        ld      a,(sh_state)
        or      a
        jp      nz,shot_restore     ; flying: just put the kept pixels back
        inc     a
        ld      (sdr_skip),a        ; do not paint it back inside its own erase
;  A POSE CHANGE moves nothing: not the bird, not the elastic, not the aim
;  dots. Putting the kept pixels back and blitting the new pose is two
;  blits; rebuilding five columns of scenery for it is what made the blink
;  flicker.
        ld      a,(se_narrow)
        or      a
        jr      nz,se_pose
        ld      a,(game_state)
        cp      GS_AIM
        jr      z,se_aim
se_box:            ; on the sling: the elastic has to go too
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
        call    redraw_rect
        jr      se_done

;  The aim rectangle is the bird's box UNION the elastic's, worked out each
;  time rather than fixed. That matters more than it looks: a whole game
;  frame of aiming costs about one display frame, so a rectangle twice the
;  size it needs to be does not merely cost time, it puts the erase and the
;  redraw in DIFFERENT displayed frames and the bird visibly blinks.
se_pose:
        call    shot_restore
        ; fall through
se_done:
        xor     a
        ld      (sdr_skip),a
        ret

se_aim:
;  Dots, then the bird, then the elastic — the exact reverse of the order
;  they went on. Each one puts back the pixels it covered, so nothing is
;  rebuilt: the whole aim used to repaint fifteen columns of scenery every
;  time the sling moved a notch, and that was the flicker.
        call    aim_undot
        call    shot_restore
        call    band_undo
        jr      se_done

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
sdr_skip:       db      0
se_narrow:      db      0
bk_byte0:       db      0
bk_nblit:       db      0
bk_y:           db      0
bk_rows:        db      0
bk_left:        db      0
bk_up:          db      0
bk_ptr:         dw      0
sa_frame:       db      0
sa_x:           dw      0
sa_y:           dw      0
sc_cx:          dw      0
sc_cy:          dw      0
sc_ay:          dw      0
sc_cell:        db      0
sc_speed:       db      0
sc_dmg:         db      0
