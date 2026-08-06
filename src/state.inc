; ============================================================================
;  FURIOUS FOWLS — state.inc
;  Every mutable table in one place, as addresses rather than reserved
;  space: this RAM sits above the loaded image, so nothing here costs a
;  byte on disk. Change a size and everything below it moves; the assert
;  at the bottom catches the day it stops fitting.
; ============================================================================

; --- the column renderer's working area -------------------------------------
colbuf          equ STATE_BASE              ; 200 lines x 2 bytes of ART
                                            ; (nibble pens, not Mode 0 —
                                            ; compositing is nibble work and
                                            ; the conversion happens once,
                                            ; on the way into video RAM)
COLBUF_SIZE     equ SCREEN_LINES*2

bg_template     equ colbuf+COLBUF_SIZE      ; sky + turf, identical for every
                                            ; column because the ground is
                                            ; flat: built once, copied per
                                            ; column instead of recomputed

hud_buf         equ bg_template+COLBUF_SIZE ; the status strip, composed
HUD_STRIDE      equ VIEW_CHARS*2            ; straight in MODE 0 so it can be
HUD_SIZE        equ HUD_STRIDE*HUD_LINES    ; LDIR'd into the ring as-is

;  What is under the bird. Rebuilding the scene beneath it is four columns
;  of background every time it moves, which does not fit in a frame
;  alongside the blit — so the pixels it covers are kept and put back
;  instead. See shot.asm. spr_clip never hands back more than one sprite
;  row, so the store is that wide and no wider.
shot_back       equ hud_buf+HUD_SIZE
SHOT_BACK_SIZE  equ (CR_BYTES_PER_ROW+1)*CR_HEIGHT

; --- the level, unpacked ----------------------------------------------------
scen_count      equ shot_back+SHOT_BACK_SIZE
scen_tab        equ scen_count+1            ; 3 bytes: cell, char col, y
SCEN_ENT        equ 3

grid            equ scen_tab+MAX_SCENERY*SCEN_ENT
                                            ; GRID_W x GRID_H occupancy, row
                                            ; major. #FF empty, 0..59 a block
                                            ; index, #80|n a pig index
GRID_SIZE       equ GRID_W*GRID_H

blocks          equ grid+GRID_SIZE          ; MAX_BLOCKS x BLK_SIZE
pigs            equ blocks+MAX_BLOCKS*BLK_SIZE
bird_queue      equ pigs+MAX_PIGS*ENT_SIZE  ; MAX_BIRDS creature types

;  The tilted copies of the ten pieces of whichever material set this level
;  uses, built at level load by applying the four rot_map tables. Storing
;  the tilts for all five sets would be 25 KB; building the one set that is
;  actually on screen costs 5 KB and about six frames, once.
rot_art         equ bird_queue+MAX_BIRDS
ROT_ART_SIZE    equ BLK_PIECES*ROT_TILTS*BLK_BYTES

; --- scalars ----------------------------------------------------------------
vars            equ rot_art+ROT_ART_SIZE

cam_x           equ vars+0      ; camera offset, CRTC chars (0..CAM_MAX)
scroll_dir      equ vars+1      ; 0 hold, 1 right, #FF left
flip_dir        equ vars+2      ; 1 = a staged column is waiting for its flip
flip_pend       equ vars+3      ; its direction
spr_cam         equ vars+4      ; the camera it will flip to
spr_col         equ vars+5      ; the world column being staged
cam_free        equ vars+6      ; 1 = the player parked the view

game_state      equ vars+7      ; GS_*
level_no        equ vars+8      ; 0..LEVEL_COUNT-1
block_set       equ vars+9      ; 0..4, chosen by the level
sling_x         equ vars+10     ; world x of the fork centre
bird_count      equ vars+11     ; birds left in the queue, this one included
bird_idx        equ vars+12     ; which queue slot is on the sling
block_count     equ vars+13
pig_count       equ vars+14
pigs_alive      equ vars+15
settle_t        equ vars+16     ; quiet frames counted in GS_SETTLE
banner_t        equ vars+17
settle_cap      equ st_scratch+0
music_ok        equ st_scratch+4    ; 1 = rot_art still holds the tune
esc_armed       equ st_scratch+2    ; one ESC on its own does nothing:
esc_t           equ st_scratch+3    ; a mis-hit mid-shot should not throw
                                    ; the turn away
swap_mode       equ st_scratch+1    ; 1 = the pigs do the throwing.
                                    ; Chosen on the title screen and
                                    ; kept across levels, so it lives
                                    ; outside anything level_load clears
settle_req      equ vars+18     ; 1 = the fort may have shifted, so
                                ; blocks_update must sweep the grid
score           equ vars+19     ; 3 bytes, BCD-free binary
frame_counter   equ vars+22
irq_counter     equ vars+23     ; 2 bytes
int_slice       equ vars+25
rnd_seed        equ vars+26     ; 2 bytes

; --- the shot ---------------------------------------------------------------
sh_state        equ vars+28     ; 0 idle, 1 flying
sh_x            equ vars+29     ; 24-bit signed: frac, then a 16-bit pixel
sh_y            equ vars+32     ; ...so the bird may leave the world and
sh_vx           equ vars+35     ; come back. Velocities are 8.8 signed.
sh_vy           equ vars+37
sh_type         equ vars+39     ; creature index of the bird in the air
sh_frame        equ vars+40
sh_px           equ vars+41     ; where it was last drawn, for the erase
sh_py           equ vars+43
sh_drawn        equ vars+45     ; 1 = there is something on screen to erase
sh_hits         equ vars+46
sh_rest         equ vars+47     ; frames it has spent going nowhere

aim_angle       equ vars+48     ; 1/256 of a turn
aim_power       equ vars+49     ; 0..POWER_MAX
charging        equ vars+50

; --- scratch used by the renderers ------------------------------------------
sb_y0           equ vars+51     ; scene_build line window
sb_n            equ vars+52
sb_col          equ vars+53

sp_art          equ vars+54     ; sprite blit parameters
sp_x            equ vars+56     ; world x (16-bit signed)
sp_y            equ vars+58     ; world y (signed; clipped to the play area)
sp_w            equ vars+60     ; art bytes per row
sp_h            equ vars+61     ; rows
sp_rowbuf       equ vars+63     ; 2 x 10 bytes: the shifted mask and data
SP_ROWBUF_SIZE  equ 20

rr_col0         equ sp_rowbuf+SP_ROWBUF_SIZE   ; redraw_rect window
rr_ncol         equ rr_col0+1
rr_y0           equ rr_col0+2
rr_n            equ rr_col0+3

;  The impact spread's working set: the best force that has reached each
;  piece so far, and which side it arrived from. Relaxed to a fixed point
;  rather than walked with a queue — see impact_spread.
spread_force    equ rr_col0+8
spread_dir      equ spread_force+MAX_BLOCKS
spread_pigf     equ spread_dir+MAX_BLOCKS

;  ...and HOW FAR OUT each one was reached: 0 is the piece the bird hit, 1
;  everything touching it, and so on. The forces alone say what happens but
;  not in what order, and a fort that folds outward from the impact reads
;  as cause and effect where the same pieces moving in table order read as
;  noise. Recorded during the walk, spent by is_apply. See impact_spread.
spread_hop      equ spread_pigf+MAX_PIGS
spread_pighop   equ spread_hop+MAX_BLOCKS

;  Where the bird struck the fort. Once it has, the camera stops chasing
;  the bird and holds this point in the middle of the screen — that is
;  where the collapse happens, and it is the whole reason for the shot.
cam_hit_x       equ rr_col0+5   ; world x of the impact (16-bit)
cam_hit         equ rr_col0+7   ; 1 = there has been one this turn

ui_dirty        equ rr_col0+4   ; 1 = the status strip needs recomposing;
                                ; done in the main loop, not wherever the
                                ; count changed, because ui_blit is 13k
                                ; T-states and pigs die inside the sweep

;  Three voices, nine bytes each: where the next step is, how long the
;  current one has left, and the pitch and volume it is sliding through.
snd_state       equ spread_pighop+MAX_PIGS

;  The elastic is seventy-odd single pixels scattered over a wide box, and
;  it moves every time the sling is wound another notch. Rebuilding the
;  scenery under it to erase it is what the pull flickers on; keeping the
;  byte each pixel covered costs three bytes apiece and puts it back
;  exactly. Same mechanism as the aim dots — see px_keep in shot.asm.
BAND_SLOTS      equ 80
band_slot       equ snd_state+27
band_n          equ band_slot+BAND_SLOTS*3

st_scratch      equ band_n+1
STATE_END       equ st_scratch+32

;  The title theme borrows rot_art — five kilobytes that hold nothing until
;  a level loads. That is free until you come BACK to the menu, by which
;  point level_load has built the tilted block art over the top of it. So
;  music_ok says whether the bytes are still music; once they are not, the
;  menu is simply quiet. Making it permanent needs 446 bytes that this
;  machine does not currently have spare — see the note in hardware.inc.
music_base      equ rot_art

        assert  STATE_END < SCREEN_BASE
