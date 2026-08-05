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

hud_buf         equ bg_template+COLBUF_SIZE ; the status strip, composed in
HUD_STRIDE      equ VIEW_CHARS*2            ; ART form (plotting glyphs is
HUD_SIZE        equ HUD_STRIDE*HUD_LINES    ; nibble work)...

hud_m0          equ hud_buf+HUD_SIZE        ; ...and then converted ONCE into
                                            ; Mode 0, because the strip is
                                            ; re-blitted on every scrolled
                                            ; frame and a per-byte lookup
                                            ; there costs a third of a frame

; --- the level, unpacked ----------------------------------------------------
scen_count      equ hud_m0+HUD_SIZE
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

st_scratch      equ rr_col0+8
STATE_END       equ st_scratch+32

        assert  STATE_END < SCREEN_BASE
