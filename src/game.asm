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
        call    score_reset
        xor     a
        ld      (hi_score),a        ; nothing on the disc yet, and hi_load
        ld      (hi_score+1),a      ; leaves these alone if it cannot read
        ld      (hi_score+2),a      ; the sector
        ld      (difficulty),a      ; ...and it opens on EASY
        ld      (hi_dirty),a
        call    hi_load
        xor     a
        ld      (level_no),a
        jp      title_show          ; the game opens on the title, not on
                                    ; level one

; ----------------------------------------------------------------------------
;  game_start_level — build the world for (level_no) and show it
; ----------------------------------------------------------------------------
game_start_level:
        call    snd_init            ; the theme lives in rot_art, which
        xor     a                   ; level_load is about to build over
        ld      (music_ok),a
        call    palette_black       ; hide the build
        xor     a
        ld      (cam_x),a
        ld      (scroll_dir),a
        ld      (flip_dir),a
        ld      (cam_free),a
        ld      (cam_hit),a
        ld      (bird_idx),a
        ld      (banner_t),a
        call    crtc_set_offset
        ld      a,(level_no)
        call    level_load
        call    swap_sides
        call    shot_reset
        call    repaint_window
        call    blocks_draw_all
        call    pigs_draw_all
        call    game_next_bird
        call    ui_compose
        call    ui_blit
        call    palette_apply
;  LEVEL n START, held for two seconds. It goes on AFTER the palette comes
;  up, because the point of it is to be read — building it behind a black
;  screen like the rest of the level would waste the first of the two
;  seconds on a fade the player cannot see through.
        ld      a,(game_state)
        cp      GS_AIM
        ret     nz                  ; out of birds already: no fanfare
        call    intro_show
        ld      a,INTRO_FRAMES
        ld      (banner_t),a
        ld      a,GS_INTRO
        ld      (game_state),a
        ret

; ----------------------------------------------------------------------------
;  world_repaint — rebuild the whole visible window from the model.
;
;  Every sprite in this engine is erased by rebuilding the background under
;  it, and any erase that misses leaves its sprite behind for good. Doing
;  one clean sweep at each turn boundary means nothing can accumulate
;  across a whole level: whatever the screen shows at the start of a turn
;  is what the block and pig tables actually say. It costs about a second,
;  in a pause that already exists.
;
;  It is also the experiment that tells the two failure modes apart. If an
;  artefact survives this, the MODEL is wrong; if it vanishes, the DRAWING
;  was.
; ----------------------------------------------------------------------------
world_repaint:
        call    repaint_window
        call    blocks_draw_all
        call    pigs_draw_all
        call    ui_compose
        jp      ui_blit

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
;  OUT OF BIRDS. That is one go used; MAX_TRIES of them and the game is
;  over rather than merely restarted, which is the difference between a
;  fort being a puzzle and a fort being a wall you lean on until it gives.
gnb_none:
        ld      a,SND_SAD
        ld      b,0
        call    snd_fx
        ld      hl,tries
        inc     (hl)
        ld      a,(hl)
        ld      c,a
        call    tries_max
        ld      b,a
        ld      a,c                 ; goes taken >= goes allowed?
        cp      b
        ld      a,GS_FAIL
        jr      nc,gnb_over
        ld      (game_state),a      ; ...one of the four consolations
        ld      a,1
        call    end_banner
        ld      a,GS_FAIL
        jr      gnb_state
gnb_over:
        call    hi_check            ; the last score there will ever be
        call    banner_home
        call    over_show
        ld      a,GS_OVER
gnb_state:
        ld      (game_state),a
        ld      a,BANNER_FRAMES
        ld      (banner_t),a
;  RAISE THE FLAG, do not just compose. ui_compose fills hud_buf and
;  nothing more; the strip only reaches the screen through ui_refresh or
;  the scroll seam. Composing a banner and never blitting it is why OUT OF
;  BIRDS was invisible — the CLEAR banner got away with it only because a
;  dying pig raises the flag on its own.
        ld      a,1
        ld      (ui_dirty),a
        ret

; ============================================================================
;  game_update — one frame
; ============================================================================
game_update:
        ld      a,(game_state)
        cp      GS_TITLE
        jp      z,gu_title
        cp      GS_AIM
        jp      z,gu_aim
        cp      GS_FLY
        jp      z,gu_fly
        cp      GS_SETTLE
        jp      z,gu_settle
        cp      GS_INTRO
        jp      z,gu_intro
        jp      gu_banner

; ----------------------------------------------------------------------------
;  INTRO — two seconds of big lettering. The fort settles underneath it,
;  which is exactly where a fort that was built leaning wants to do it.
; ----------------------------------------------------------------------------
gu_intro:
        call    blocks_update
        call    pigs_update
        ld      hl,banner_t
        dec     (hl)
        ret     nz
;  The aim dots live in the band the lettering covered, so the box repaint
;  took them off the screen — but not out of their table, and putting that
;  table back would paint five stale pixels over fresh scenery. FORGET
;  them, then make the next call lay them down again.
        call    intro_hide
        xor     a
        ld      (dot_n),a
        ld      a,#FF
        ld      (ad_angle),a
        ld      a,GS_AIM
        ld      (game_state),a
        jp      shot_draw_ready

; ----------------------------------------------------------------------------
;  AIM
; ----------------------------------------------------------------------------
gu_aim:
        call    blocks_update       ; costs nothing unless something is
        call    pigs_update         ; actually still moving down there
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
;  Unconditionally: the blink and the aim dots both change without anything
;  setting ga_moved, and shot_draw_ready costs a sine and two compares when
;  there is nothing to do.
        call    shot_draw_ready
        ; fall through to the free look

; ----------------------------------------------------------------------------
;  Free look. Left and right pan the camera while you are aiming, so you can
;  go and see what you are shooting at; the view then STAYS where you left
;  it, because snapping back the moment you let go would defeat the point.
;  Launching a bird re-arms the follow.
; ----------------------------------------------------------------------------
camera_look:
        xor     a
        ld      (scroll_dir),a
        ld      a,(kbd_state+KEY_RIGHT_ROW)
        and     KEY_RIGHT_MASK
        jr      z,cl_left
        ld      a,1
        ld      (cam_free),a
        ld      a,(cam_x)
        cp      CAM_MAX
        ret     nc
        ld      a,1
        ld      (scroll_dir),a
        ret
cl_left:
        ld      a,(kbd_state+KEY_LEFT_ROW)
        and     KEY_LEFT_MASK
        jr      z,cl_idle
        ld      a,1
        ld      (cam_free),a
        ld      a,(cam_x)
        or      a
        ret     z
        ld      a,#FF
        ld      (scroll_dir),a
        ret
cl_idle:
        ld      a,(cam_free)
        or      a
        ret     nz                  ; parked by the player: hold it there
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
        ld      a,SETTLE_MAX        ; a hard stop on the whole settle, in
        ld      (settle_cap),a      ; case the rubble finds a way to jiggle
        ret

; ----------------------------------------------------------------------------
;  SETTLE — the turn is not over until the rubble stops
; ----------------------------------------------------------------------------
gu_settle:
        ld      a,(settle_cap)      ; the turn cannot last for ever, whatever
        or      a                   ; the physics thinks
        jr      z,gs_turn_over
        dec     a
        ld      (settle_cap),a
        call    blocks_update
        ld      c,a                 ; both have to be quiet, and both have
        call    pigs_update         ; to RUN: a pig may still be dying
        or      c
        jr      nz,gs_busy
        call    camera_follow_shot  ; keep watching where the shot landed
        ld      a,(settle_t)
        dec     a
        ld      (settle_t),a
        ret     nz
        jr      gs_turn_over
gs_busy:
        call    camera_follow_shot
        ld      a,SETTLE_FRAMES
        ld      (settle_t),a
        ret

gs_turn_over:
        xor     a                   ; the bird is spent: take it off the
        ld      (sh_drawn),a        ; screen before the repaint, or the
        call    world_repaint       ; repaint will not know to remove it
        ld      a,(pigs_alive)
        or      a
        jr      z,gs_cleared
        call    pigs_taunt          ; the survivors enjoy that
        ld      a,(bird_idx)
        inc     a
        ld      (bird_idx),a
        jp      game_next_bird
gs_cleared:
        ld      a,SND_FANFARE
        ld      b,0
        call    snd_fx
        ld      a,GS_CLEAR
        ld      (game_state),a
        ld      a,BANNER_FRAMES
        ld      (banner_t),a
        xor     a                   ; VICTORY, over the middle of the window
        call    end_banner
        ld      a,(bird_count)      ; a bird unspent is a bird earned
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
        push    bc
        ld      hl,BIRD_BONUS
        call    score_add
        pop     bc
        djnz    gs_bonus
gs_nobonus:
        call    hi_check
        ld      a,1
        ld      (ui_dirty),a
        ret

; ============================================================================
;  Score
;
;  The score is HOW HARD THE PIGS WERE HIT — every blow that lands on a pig
;  adds its own force, so a shot that grazes three of them beats a shot that
;  flattens one — plus a hundred for every bird still in the queue when the
;  level clears. Nothing is scored for damage to the fort: the fort is the
;  means, not the end, and paying for it rewarded knocking a wall down and
;  walking away from the pig behind it.
;
;  Twenty-four bits. Fifty forts at a few hundred a fort does not fit in
;  sixteen, and a score that wraps to nothing is worse than no score.
; ============================================================================
BIRD_BONUS      equ 100

; ----------------------------------------------------------------------------
;  banner_home — snap the camera to the sling and rebuild the window.
;
;  title_text keeps its x in a single BYTE, so the big lettering can only
;  be laid down with the camera at the left of the world. That is where it
;  wants to be anyway: the fort that has just come down — or just beaten
;  you — is worth looking at from the place you were throwing at it.
; ----------------------------------------------------------------------------
banner_home:
        xor     a
        ld      (cam_x),a
        ld      (scroll_dir),a
        ld      (flip_dir),a
        call    crtc_set_offset
        jp      world_repaint

; ---- end_banner — A = 0 cleared, 1 failed ---------------------------------
end_banner:
        push    af
        call    banner_home
        pop     af
        jp      end_show

; ---- tries_max — A = how many goes this difficulty allows ------------------
tries_max:
        ld      a,(difficulty)
        cp      DIFF_COUNT
        jr      c,tm_ok
        xor     a
tm_ok:
        ld      hl,tries_tab
        add     a,l
        ld      l,a
        adc     a,h
        sub     l
        ld      h,a
        ld      a,(hl)
        ret
tries_tab:
        db      5,3,2               ; easy, medium, hard

; ---- score_reset — a new game, from the title ------------------------------
score_reset:
        xor     a
        ld      (score),a
        ld      (score+1),a
        ld      (score+2),a
        ret

; ---- score_add — HL = points to add ----------------------------------------
score_add:
        ld      de,(score)
        add     hl,de
        ld      (score),hl
        ret     nc
        ld      hl,score+2
        inc     (hl)
        ret

; ---- hi_check — has this beaten the disc? ----------------------------------
;  Only the FLAG is set here. Writing a sector stops the machine for about
;  a second while the motor spins up, and doing that in the middle of a
;  level would be felt. It goes to the disc at the menu — see hi_flush.
; ----------------------------------------------------------------------------
hi_check:
        ld      a,(score+2)
        ld      hl,hi_score+2
        cp      (hl)
        jr      c,hc_no
        jr      nz,hc_yes
        ld      hl,(score)
        ld      de,(hi_score)
        or      a
        sbc     hl,de
        jr      c,hc_no
        jr      z,hc_no
hc_yes:
        ld      hl,(score)
        ld      (hi_score),hl
        ld      a,(score+2)
        ld      (hi_score+2),a
        ld      a,1
        ld      (hi_dirty),a
hc_no:
        ret

; ---- hi_flush — put it on the disc, if it has moved since the last time --
hi_flush:
        ld      a,(hi_dirty)
        or      a
        ret     z
        jp      hi_save

; ----------------------------------------------------------------------------
;  game_to_menu — leave a game in progress. The disc write happens HERE and
;  nowhere else: it stops the machine for about a second while the motor
;  spins up, which is unnoticeable at a menu and unforgivable mid-shot.
; ----------------------------------------------------------------------------
game_to_menu:
        xor     a
        ld      (tries),a
        call    hi_flush
        call    score_reset
        xor     a
        ld      (level_no),a
        jp      title_show

; ----------------------------------------------------------------------------
;  CLEAR / FAIL — a banner, then SPACE
; ----------------------------------------------------------------------------
gu_banner:
;  The fort does not stop falling just because the turn is over. Without
;  this, a piece still in the air when the last pig popped hung there for
;  good — frozen mid-fall, BS_FALL for ever, because nothing was left
;  running to land it. It costs nothing once everything has settled.
        call    blocks_update
        call    pigs_update
;  The camera does NOT drift here any more. All three banners snap it to
;  the sling themselves and then lay big lettering over the window, and a
;  drift would scroll that lettering out from under itself.
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
        cp      GS_OVER
        jp      z,game_to_menu      ; nothing left to do but go and look at
        cp      GS_CLEAR            ; the high score
        jr      nz,gb_retry
        xor     a                   ; a NEW fort, so a fresh five goes
        ld      (tries),a
        ld      a,(level_no)
        inc     a
        cp      LEVEL_COUNT
        jr      c,gb_go
        jp      game_to_menu        ; the whole round is done: back to the
                                    ; menu, where the high score is written
gb_go:
        ld      (level_no),a
gb_retry:
        jp      game_start_level

; ============================================================================
;  swap_sides — the whole of the reversed mode.
;
;  Nothing about the level changes: the fort is the same fort and the
;  physics never asks what species anything is. All that turns over is who
;  is in the pouch and who is standing in the way, and both are a creature
;  TYPE — birds are 0..5 and pigs 6..8, so the swap is arithmetic on two
;  small tables. The level files know nothing about it.
; ============================================================================
swap_sides:
        ld      a,(swap_mode)
        or      a
        ret     z

        ld      b,MAX_BIRDS         ; the sling is loaded with pigs
        ld      hl,bird_queue
ss_queue:
        ld      a,(hl)
ss_mod:
        cp      PIG_TYPES           ; six bird types onto three pig ones
        jr      c,ss_mod_done
        sub     PIG_TYPES
        jr      ss_mod
ss_mod_done:
        add     a,PIG_PIG
        ld      (hl),a
        inc     hl
        djnz    ss_queue

        ld      b,MAX_PIGS          ; ...and the fort is defended by birds
        ld      ix,pigs
ss_targets:
        ld      a,(ix+ENT_STATE)
        or      a
        jr      z,ss_next
        ld      a,(ix+ENT_TYPE)
        sub     PIG_PIG
        ld      (ix+ENT_TYPE),a
ss_next:
        ld      de,ENT_SIZE
        add     ix,de
        djnz    ss_targets
        ret

; ============================================================================
;  Camera. One char per frame, and only when the thing worth watching has
;  drifted out of the middle band — a camera that tracks exactly is a
;  camera that jitters.
; ============================================================================
;  Two comfort bands. Following the bird wants a WIDE one — a camera that
;  tracks exactly is a camera that jitters. Holding the impact wants a
;  NARROW one, because the whole point is to put it in the middle and
;  leave it there. The bounds are immediates inside camera_to, patched by
;  whichever entry point you came in through.
CAM_BAND_LO     equ 48
CAM_BAND_HI     equ 104
CAM_MID_LO      equ 76
CAM_MID_HI      equ 84

camera_follow_sling:
        ld      hl,(sh_px)
        jr      cam_wide

;  Once the bird has struck the fort the camera stops chasing it. The bird
;  bounces off somewhere and stops mattering; what the player wants to
;  watch is the thing it knocked over.
camera_follow_shot:
        ld      a,(cam_hit)
        or      a
        jr      z,cfs_bird
        ld      a,CAM_MID_LO
        ld      (ct_lo+1),a
        ld      a,CAM_MID_HI
        ld      (ct_hi+1),a
        ld      hl,(cam_hit_x)
        jr      camera_to
cfs_bird:
        ld      hl,(sh_px)
cam_wide:
        ld      a,CAM_BAND_LO
        ld      (ct_lo+1),a
        ld      a,CAM_BAND_HI
        ld      (ct_hi+1),a
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
ct_lo:  cp      CAM_BAND_LO
        jr      c,ct_left
ct_hi:  cp      CAM_BAND_HI
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
