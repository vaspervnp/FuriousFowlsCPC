; ============================================================================
;  FURIOUS FOWLS — game.asm
;  The turn machine, and the camera that follows the shot.
;
;    AIM     a bird waits in the pouch. Up and down set the angle, holding
;            SPACE winds up the power — and the bird is hauled physically
;            back down the launch line, so the pull IS the readout.
;    FLY     it is in the air; blocks and pigs are live.
;    SETTLE  the bird has stopped. Nothing ends until the fort stops
;            moving, because the collapse it started may still be killing
;            pigs — that is where half the satisfaction lives.
;    CLEAR   every pig popped.
;    FAIL    out of birds.
; ============================================================================

game_init:
        ld      hl,0
        ld      (score),hl
        xor     a
        ld      (level_no),a
        ; fall through

; ----------------------------------------------------------------------------
;  game_start_level — build the world for (level_no) and show it
; ----------------------------------------------------------------------------
game_start_level:
        call    palette_black       ; hide the build
        xor     a
        ld      (cam_x),a
        ld      (scroll_dir),a
        ld      (flip_dir),a
        ld      (cam_free),a
        ld      (bird_idx),a
        ld      (banner_t),a
        call    crtc_set_offset
        ld      a,(level_no)
        call    level_load
        call    shot_reset
        call    repaint_window
        call    blocks_draw_all
        call    pigs_draw_all
        call    game_next_bird
        call    ui_compose
        call    ui_blit
        jp      palette_apply

; ----------------------------------------------------------------------------
;  game_next_bird — put the next one in the queue on the sling, or give up
; ----------------------------------------------------------------------------
game_next_bird:
        ld      a,(bird_idx)
        ld      c,a
        ld      a,(bird_count)
        cp      c
        jr      z,gnb_none
        jr      c,gnb_none
        ld      hl,bird_queue
        ld      e,c
        ld      d,0
        add     hl,de
        ld      a,(hl)
        ld      (sh_type),a
        xor     a
        ld      (sh_state),a
        ld      (aim_power),a
        ld      (charging),a
        ld      a,GS_AIM
        ld      (game_state),a
        call    shot_draw_ready
        jp      ui_compose
gnb_none:
        ld      a,GS_FAIL
        ld      (game_state),a
        ld      a,BANNER_FRAMES
        ld      (banner_t),a
        jp      ui_compose

; ============================================================================
;  game_update — one frame
; ============================================================================
game_update:
        ld      a,(game_state)
        cp      GS_AIM
        jp      z,gu_aim
        cp      GS_FLY
        jp      z,gu_fly
        cp      GS_SETTLE
        jp      z,gu_settle
        jp      gu_banner

; ----------------------------------------------------------------------------
;  AIM
; ----------------------------------------------------------------------------
gu_aim:
        xor     a
        ld      (ga_moved),a

        ld      a,(kbd_state+KEY_UP_ROW)
        and     KEY_UP_MASK
        jr      z,ga_down
        ld      a,(aim_angle)
        add     a,AIM_RATE
        cp      AIM_MAX
        jr      c,ga_ang
        ld      a,AIM_MAX
        jr      ga_ang
ga_down:
        ld      a,(kbd_state+KEY_DOWN_ROW)
        and     KEY_DOWN_MASK
        jr      z,ga_charge
        ld      a,(aim_angle)
        sub     AIM_RATE
        cp      AIM_MIN+4
        jr      nc,ga_ang
        ld      a,AIM_MIN+4
ga_ang:
        ld      c,a
        ld      a,(aim_angle)
        cp      c
        jr      z,ga_charge
        ld      a,c
        ld      (aim_angle),a
        ld      a,1
        ld      (ga_moved),a

ga_charge:
        ld      a,(kbd_state+KEY_SPACE_ROW)
        and     KEY_SPACE_MASK
        jr      z,ga_release
        ld      a,1
        ld      (charging),a
        ld      a,(aim_power)
        add     a,POWER_RATE
        cp      POWER_MAX
        jr      c,ga_pow
        ld      a,POWER_MAX
ga_pow:
        ld      c,a
        ld      a,(aim_power)
        cp      c
        jr      z,ga_redraw
        ld      a,c
        ld      (aim_power),a
        ld      a,1
        ld      (ga_moved),a
        jr      ga_redraw

ga_release:
        ld      a,(charging)
        or      a
        jr      z,ga_redraw
        ld      a,(aim_power)
        cp      6
        jr      c,ga_cancel         ; barely pulled: not a shot, a fumble
        call    shot_launch
        ld      a,GS_FLY
        ld      (game_state),a
        jp      ui_compose
ga_cancel:
        xor     a
        ld      (charging),a
        ld      (aim_power),a
        ld      a,1
        ld      (ga_moved),a

ga_redraw:
        ld      a,(ga_moved)
        or      a
        call    nz,shot_draw_ready
        jp      camera_follow_sling

; ----------------------------------------------------------------------------
;  FLY
; ----------------------------------------------------------------------------
gu_fly:
        call    shot_update         ; Z once the bird has finished
        push    af
        call    blocks_update
        call    pigs_update
        call    camera_follow_shot
        pop     af
        ret     nz
        ld      a,GS_SETTLE
        ld      (game_state),a
        ld      a,SETTLE_FRAMES
        ld      (settle_t),a
        ret

; ----------------------------------------------------------------------------
;  SETTLE — the turn is not over until the rubble stops
; ----------------------------------------------------------------------------
gu_settle:
        call    blocks_update
        ld      c,a                 ; both have to be quiet, and both have
        call    pigs_update         ; to RUN: a pig may still be dying
        or      c
        jr      nz,gs_busy
        ld      a,(settle_t)
        dec     a
        ld      (settle_t),a
        ret     nz
        jr      gs_turn_over
gs_busy:
        ld      a,SETTLE_FRAMES
        ld      (settle_t),a
        ret

gs_turn_over:
        ld      a,(pigs_alive)
        or      a
        jr      z,gs_cleared
        call    pigs_taunt          ; the survivors enjoy that
        ld      a,(bird_idx)
        inc     a
        ld      (bird_idx),a
        jp      game_next_bird
gs_cleared:
        ld      a,GS_CLEAR
        ld      (game_state),a
        ld      a,BANNER_FRAMES
        ld      (banner_t),a
        ld      hl,(score)          ; a bird unspent is a bird earned
        ld      a,(bird_count)
        ld      c,a
        ld      a,(bird_idx)
        inc     a
        ld      b,a
        ld      a,c
        sub     b
        jr      c,gs_nobonus
        jr      z,gs_nobonus
        ld      b,a
gs_bonus:
        ld      de,1000
        add     hl,de
        djnz    gs_bonus
gs_nobonus:
        ld      (score),hl
        jp      ui_compose

; ----------------------------------------------------------------------------
;  CLEAR / FAIL — a banner, then SPACE
; ----------------------------------------------------------------------------
gu_banner:
        ld      a,(banner_t)
        or      a
        jr      z,gb_wait
        dec     a
        ld      (banner_t),a
        ret
gb_wait:
        ld      a,(kbd_edge+KEY_SPACE_ROW)
        and     KEY_SPACE_MASK
        ret     z
        ld      a,(game_state)
        cp      GS_CLEAR
        jr      nz,gb_retry
        ld      a,(level_no)
        inc     a
        cp      LEVEL_COUNT
        jr      c,gb_go
        xor     a                   ; round the forty and start again
gb_go:
        ld      (level_no),a
gb_retry:
        jp      game_start_level

; ============================================================================
;  Camera. One char per frame, and only when the thing worth watching has
;  drifted out of the middle band — a camera that tracks exactly is a
;  camera that jitters.
; ============================================================================
camera_follow_sling:
        ld      hl,(sh_px)
        jr      camera_to

camera_follow_shot:
        ld      hl,(sh_px)
        ; fall through

;  HL = the world x to keep in view
camera_to:
        xor     a
        ld      (scroll_dir),a
        ld      a,(cam_x)
        ld      e,a
        ld      d,0
        ex      de,hl
        add     hl,hl
        add     hl,hl               ; the window's left edge, in pixels
        ex      de,hl
        or      a
        sbc     hl,de               ; screen x
        bit     7,h
        jr      nz,ct_left
        ld      a,h
        or      a
        jr      nz,ct_right
        ld      a,l
        cp      48
        jr      c,ct_left
        cp      104
        ret     c                   ; comfortably inside: hold still
ct_right:
        ld      a,(cam_x)
        cp      CAM_MAX
        ret     nc
        ld      a,1
        ld      (scroll_dir),a
        ret
ct_left:
        ld      a,(cam_x)
        or      a
        ret     z
        ld      a,#FF
        ld      (scroll_dir),a
        ret

ga_moved:       db      0
