; ============================================================================
;  FURIOUS FOWLS — sound.asm
;  A three-voice step sequencer for the AY-3-8912.
;
;  One step per channel per frame, and a step is nothing but a starting
;  pitch with a slide, a starting volume with a fade, and a noise setting.
;  That is deliberately less than a tracker can do and exactly as much as a
;  cartoon needs: a slide is a swoop, a fast fade is a blip, and noise is
;  anything that breaks. Eleven sounds cost under two hundred bytes.
;
;  Channels are claimed, not queued. Starting a sound on a channel drops
;  whatever was there — during a collapse that is what you want, because
;  the twentieth plank landing should sound like now, not like a backlog.
;
;  The data lives with the creature art down in low memory, not in the code
;  bank: see art.asm. It is read in place.
; ============================================================================

SC_PTR          equ 0       ; where the next step is, 0 = channel idle
SC_LEFT         equ 2       ; frames left in the current step
SC_PER          equ 3       ; the tone period, slid every frame
SC_SLIDE        equ 5
SC_VOL          equ 6
SC_VFADE        equ 7
SC_CTL          equ 8       ; noise period, plus the two "off" bits
SND_CH          equ 9

SND_TONE_OFF    equ #20
SND_NOISE_OFF   equ #40

; ----------------------------------------------------------------------------
;  snd_init — every channel idle. psg_init has already put the chip in a
;  state where writing to it is safe.
; ----------------------------------------------------------------------------
snd_init:
        ld      hl,snd_state
        ld      de,snd_state+1
        ld      bc,SND_CH*3-1
        ld      (hl),0
        ldir
        ret

; ----------------------------------------------------------------------------
;  snd_play — A = sound id (SND_*), C = channel 0..2
; ----------------------------------------------------------------------------
snd_play:
        push    bc
        ld      l,a
        ld      h,0
        add     hl,hl
        ld      de,SOUND_OFS
        add     hl,de
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        ld      hl,SOUNDS_BASE
        add     hl,de
        pop     bc
;  ...and an entry for callers that already have the steps. The title theme
;  is not in the sound table at all — it is four hundred bytes sitting in
;  the block-art workspace — but it is the same format, so it plays through
;  the same engine.
snd_play_hl:
        push    hl
        call    snd_chan
        pop     hl
        ld      (ix+SC_PTR),l
        ld      (ix+SC_PTR+1),h
        ld      (ix+SC_LEFT),0      ; the first step loads next frame
        ret

; ----------------------------------------------------------------------------
;  snd_fx — A = sound, B = channel, and NOTHING is disturbed.
;
;  The call sites are deep inside the collapse sweep, where IX is the piece
;  being moved and C is carrying an impact direction. A sound effect that
;  quietly eats either of those is a bug that will not look like a sound
;  bug, so it is cheaper to save everything here than to remember at each
;  of seven call sites.
; ----------------------------------------------------------------------------
snd_fx:
        push    ix
        push    hl
        push    de
        push    bc
        ld      c,b
        call    snd_play
        pop     bc
        pop     de
        pop     hl
        pop     ix
        ret

; ---- snd_chan — C = channel -> IX = its nine bytes of state -----------------
snd_chan:
        ld      a,c
        add     a,a
        add     a,a
        add     a,a
        add     a,c                 ; x9
        ld      e,a
        ld      d,0
        ld      hl,snd_state
        add     hl,de
        push    hl
        pop     ix
        ret

; ============================================================================
;  snd_update — one frame. Called from the main loop.
; ============================================================================
snd_update:
        ld      a,#3F               ; mixer: everything off, and each voice
        ld      (su_mix),a          ; clears the bits it wants back on
        ld      c,0
su_loop:
        push    bc
        call    snd_chan
        call    snd_voice
        pop     bc
        inc     c
        ld      a,c
        cp      3
        jr      c,su_loop
        ld      d,7                 ; and the mixer, once, at the end
        ld      a,(su_mix)
        ld      e,a
        jp      psg_write

; ---- snd_voice — IX = channel state, C = channel index ----------------------
snd_voice:
        ld      a,(ix+SC_PTR)
        or      (ix+SC_PTR+1)
        jp      z,sv_quiet          ; idle: leave it muted
        ld      a,(ix+SC_LEFT)
        or      a
        jr      nz,sv_sound

;  ---- the current step has run out: pull the next one in ----
        ld      l,(ix+SC_PTR)
        ld      h,(ix+SC_PTR+1)
        ld      a,(hl)
        or      a
        jp      z,sv_done           ; a zero frame count ends the sound
        ld      (ix+SC_LEFT),a
        inc     hl
        ld      a,(hl)
        ld      (ix+SC_PER),a
        inc     hl
        ld      a,(hl)
        ld      (ix+SC_PER+1),a
        inc     hl
        ld      a,(hl)
        ld      (ix+SC_SLIDE),a
        inc     hl
        ld      a,(hl)              ; volume and fade share a byte
        inc     hl
        ld      b,a
        and     #0F
        ld      (ix+SC_VOL),a
        ld      a,b
        rrca
        rrca
        rrca
        rrca
        and     #0F
        sub     8                   ; the fade is stored biased
        ld      (ix+SC_VFADE),a
        ld      a,(hl)
        ld      (ix+SC_CTL),a
        inc     hl
        ld      (ix+SC_PTR),l
        ld      (ix+SC_PTR+1),h

;  ---- put this frame's values on the chip ----
sv_sound:
        ld      a,c                 ; R0/R1, R2/R3, R4/R5
        add     a,a
        ld      d,a
        ld      e,(ix+SC_PER)
        push    bc
        call    psg_write
        pop     bc
        ld      a,c
        add     a,a
        inc     a
        ld      d,a
        ld      e,(ix+SC_PER+1)
        push    bc
        call    psg_write
        pop     bc
        ld      a,c                 ; R8/R9/R10
        add     a,8
        ld      d,a
        ld      e,(ix+SC_VOL)
        push    bc
        call    psg_write
        pop     bc

        ld      a,(ix+SC_CTL)       ; noise: one generator, last voice wins
        and     SND_NOISE_OFF
        jr      nz,sv_mix
        ld      d,6
        ld      a,(ix+SC_CTL)
        and     #1F
        ld      e,a
        push    bc
        call    psg_write
        pop     bc

;  ---- and switch this voice on in the mixer ----
;  R7 is active LOW: a CLEARED bit enables. Bits 0-2 are the tone for A, B,
;  C and bits 3-5 the noise, so the channel index is the shift for both.
sv_mix:
        ld      a,1
        inc     c
sv_shift:
        dec     c
        jr      z,sv_shifted
        add     a,a
        jr      sv_shift
sv_shifted:
        ld      b,a                 ; B = the tone bit for this channel
        add     a,a
        add     a,a
        add     a,a
        ld      c,a                 ; C = its noise bit
        ld      a,(ix+SC_CTL)
        and     SND_TONE_OFF
        ld      a,(su_mix)
        jr      nz,sv_no_tone
        xor     b                   ; the bit is set, so XOR clears it
sv_no_tone:
        ld      b,a
        ld      a,(ix+SC_CTL)
        and     SND_NOISE_OFF
        ld      a,b
        jr      nz,sv_no_noise
        xor     c
sv_no_noise:
        ld      (su_mix),a

;  ---- then slide the pitch and fade the volume for next frame ----
        ld      l,(ix+SC_PER)
        ld      h,(ix+SC_PER+1)
        ld      a,(ix+SC_SLIDE)
        ld      e,a
        add     a,a                 ; sign-extend the slide into DE
        sbc     a,a
        ld      d,a
        add     hl,de
        ld      a,h
        and     #0F                 ; the period is twelve bits; wrapping it
        ld      h,a                 ; keeps a runaway slide musical
        ld      (ix+SC_PER),l
        ld      (ix+SC_PER+1),h

        ld      a,(ix+SC_VOL)
        add     a,(ix+SC_VFADE)
        jp      p,sv_vol_hi
        xor     a                   ; faded past silence
        jr      sv_vol_ok
sv_vol_hi:
        cp      16
        jr      c,sv_vol_ok
        ld      a,15
sv_vol_ok:
        ld      (ix+SC_VOL),a
        dec     (ix+SC_LEFT)
        ret

sv_done:
        ld      (ix+SC_PTR),0
        ld      (ix+SC_PTR+1),0
sv_quiet:
        ld      a,c                 ; silence it and leave the mixer alone
        add     a,8
        ld      d,a
        ld      e,0
        jp      psg_write

su_mix:         db      #3F
