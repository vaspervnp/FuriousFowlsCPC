; ============================================================================
;  FOWL AND FURIOUS — disk.asm
;  Raw uPD765 driver for the high-score sector (track 0, #C5, inside the
;  reserved SCORES.BIN).
;
;  Lifted whole from CreepersCPC, which lifted it from TerraCPC. It is not
;  worth re-deriving: every one of the notes below is a bug that cost
;  somebody a working disc image, and the code bank has room for it now.
;  The only changes here are the payload — three bytes of high score and
;  the difficulty setting — and the buffer it borrows.
;
;  Ported from TerraCPC's battle-tested driver, which learned the hard
;  lessons on real hardware, WinAPE and RVM:
;   * Emulators LATCH an op-complete interrupt after every READ/WRITE
;     and silently swallow the next command until SENSE INTERRUPT
;     clears it — so SIS-drain before EVERY command.  (A swallowed
;     opcode makes the following parameter bytes parse as commands:
;     that is how a save can shred the whole disc image.)
;   * The result phase is read WHILE the FDC is busy (CB=1), not as a
;     fixed 7 bytes: some emulators return fewer.  On the TC-less CPC
;     every good transfer ends via End-of-Cylinder, so ST1 bit7 EN and
;     ST0's IC bits are benign: success = (ST1 & #37)==0 & (ST2 & #77)==0.
;   * Seek completion is polled with SENSE INTERRUPT (Seek-End), never
;     via MSR busy bits; a 1-byte #80 reply means "not yet".
;   * SPECIFY with ND=1 (polled mode) before recalibrating.
;   * Before each attempt the controller is re-homed: half-sent
;     commands completed with inert zero parameters, stale result
;     bytes flushed, interrupts drained, SPECIFY + RECALIBRATE.
;   * Every wait is bounded; the sticky fdc_abort short-circuits the
;     rest of the operation.  The motor always goes off on exit.
;  A save is only trusted after reading the sector back and comparing.
; ============================================================================

FDC_TO          equ 30000           ; per command/result byte
FDC_STO         equ 50000           ; seek wait (SENSE-INTERRUPT poll)
FDC_XTO         equ 50000           ; execution phase (~1 revolution)
SEC_BUF         equ hud_buf         ; overlays the HUD backbuffer, which is
                                    ; 640 bytes: disk work only happens at
                                    ; boot and at the menu, and the strip is
                                    ; rebuilt from the model afterwards

; ----------------------------------------------------------------------------
;  hi_load — read the sector; adopt the high score if the magic matches
; ----------------------------------------------------------------------------
hi_load:
        di
        call    fdc_motor_on
        ld      b,3
sl_try:
        push    bc
        call    fdc_reinit
        call    fdc_read_sec
        pop     bc
        jr      nc,sl_got
        djnz    sl_try
        jr      sl_off              ; unreadable: keep the defaults
sl_got:
        ld      a,(SEC_BUF)
        cp      'F'
        jr      nz,sl_off
        ld      a,(SEC_BUF+1)
        cp      'F'
        jr      nz,sl_off
        ld      hl,SEC_BUF+2
        ld      de,hi_score
        ld      bc,HI_BLOB
        ldir
sl_off:
        call    fdc_off
        ei
        ret

; ----------------------------------------------------------------------------
;  score_save — write magic+scores, read back and verify, clear dirty
; ----------------------------------------------------------------------------
hi_save:
        di
        ld      c,0                 ; the music ISR is off for the whole
        ld      a,9                 ; write: silence channels B+C now or
        call    psg_write           ; the current note drones through
        ld      c,0                 ; the disk work (it resumes on the
        ld      a,10                ; next note after EI)
        call    psg_write
        ld      hl,SEC_BUF          ; compose the 512-byte sector image
        ld      de,SEC_BUF+1
        ld      bc,511
        ld      (hl),0
        ldir
        ld      a,'F'
        ld      (SEC_BUF),a
        ld      (SEC_BUF+1),a
        ld      hl,hi_score
        ld      de,SEC_BUF+2
        ld      bc,HI_BLOB
        ldir
        call    fdc_motor_on
        ld      b,3
ss_try:
        push    bc
        call    fdc_reinit
        call    fdc_write_sec
        pop     bc
        jr      nc,ss_verify
        djnz    ss_try
        jr      ss_off              ; failed (write-protected?): stay dirty
ss_verify:
        call    fdc_reinit          ; trust nothing: read it back
        call    fdc_read_sec
        jr      c,ss_off
        ld      a,(SEC_BUF)
        cp      'F'
        jr      nz,ss_off
        ld      a,(SEC_BUF+1)
        cp      'F'
        jr      nz,ss_off
        ld      hl,SEC_BUF+2        ; is it really on the disc?
        ld      de,hi_score
        ld      b,HI_BLOB
ss_cmp:
        ld      a,(de)
        cp      (hl)
        jr      nz,ss_off
        inc     hl
        inc     de
        djnz    ss_cmp
        xor     a
        ld      (hi_dirty),a
ss_off:
        call    fdc_off
        ei
        ret

; ----------------------------------------------------------------------------
;  single-sector transfers (seek + SIS drain + command + exec + result)
; ----------------------------------------------------------------------------
fdc_read_sec:
        call    fdc_seek
        ld      a,(fdc_abort)
        or      a
        jr      nz,frs_fail
        call    fdc_sis_drain
        ld      a,#46               ; READ DATA (MFM)
        call    fdc_rw_cmd
        ld      hl,SEC_BUF
        call    fdc_exec_read
        jp      fdc_result
frs_fail:
        scf
        ret

fdc_write_sec:
        call    fdc_seek
        ld      a,(fdc_abort)
        or      a
        jr      nz,frs_fail
        call    fdc_sis_drain
        ld      a,#45               ; WRITE DATA (MFM)
        call    fdc_rw_cmd
        ld      hl,SEC_BUF
        call    fdc_exec_write
        jp      fdc_result

; ----------------------------------------------------------------------------
;  fdc_rw_cmd — the 9-byte command phase.  A = opcode #45/#46.
;  send_fdc preserves DE, so track/sector could ride there; ours are
;  constants.
; ----------------------------------------------------------------------------
fdc_rw_cmd:
        call    send_fdc            ; opcode
        xor     a
        call    send_fdc            ; unit A, head 0
        ld      a,SCORE_TRACK
        call    send_fdc            ; C
        xor     a
        call    send_fdc            ; H
        ld      a,SCORE_SECT
        call    send_fdc            ; R
        ld      a,2
        call    send_fdc            ; N = 512 bytes
        ld      a,SCORE_SECT
        call    send_fdc            ; EOT = R: single sector per command
        ld      a,#2A
        call    send_fdc            ; GPL
        ld      a,#FF
        call    send_fdc            ; DTL
        ret

; ----------------------------------------------------------------------------
;  execution phases — RQM tested BEFORE EXM (the command->exec search
;  window has RQM=0 & EXM=0 and must not read as "finished")
; ----------------------------------------------------------------------------
fdc_exec_write:
        ld      de,FDC_XTO
        ld      bc,FDC_MSR
few_lp:
        in      a,(c)
        bit     7,a                 ; RQM?
        jr      nz,few_go
        dec     de
        ld      a,d
        or      e
        jr      nz,few_lp
        jr      fdc_io_abort
few_go:
        bit     5,a                 ; EXM still set?
        ret     z                   ; exec finished -> result phase
        ld      a,(hl)
        inc     c
        out     (c),a               ; data -> #FB7F
        dec     c
        inc     hl
        jr      few_lp

fdc_exec_read:
        ld      de,FDC_XTO
        ld      bc,FDC_MSR
fer_lp:
        in      a,(c)
        bit     7,a
        jr      nz,fer_go
        dec     de
        ld      a,d
        or      e
        jr      nz,fer_lp
        jr      fdc_io_abort
fer_go:
        bit     5,a
        ret     z
        inc     c
        in      a,(c)               ; data <- #FB7F
        ld      (hl),a
        dec     c
        inc     hl
        jr      fer_lp

fdc_io_abort:
        ld      a,1
        ld      (fdc_abort),a
        ret

; ----------------------------------------------------------------------------
;  result phase — consume bytes WHILE the FDC is busy (CB=1).
;  Success = not aborted AND (ST1 & #37)==0 AND (ST2 & #77)==0.
;  ST1 bit7 EN and ST0's IC bits are the NORMAL TC-less ending.
; ----------------------------------------------------------------------------
fdc_result:
        xor     a
        ld      (fdc_st1),a
        ld      (fdc_st2),a
        ld      (fdc_rescnt),a
        ld      a,(fdc_abort)
        or      a
        jr      nz,fr_fail
fr_lp:
        ld      de,FDC_STO
fr_w:
        ld      bc,FDC_MSR
        in      a,(c)
        bit     4,a                 ; CB: command still in progress?
        jr      z,fr_done
        and     #C0
        cp      #C0                 ; RQM & DIO: a result byte is ready
        jr      z,fr_rd
        dec     de
        ld      a,d
        or      e
        jr      nz,fr_w
        ld      a,1
        ld      (fdc_abort),a
        jr      fr_fail
fr_rd:
        inc     c
        in      a,(c)
        ld      b,a
        ld      a,(fdc_rescnt)
        cp      12
        jr      nc,fr_fail          ; runaway result stream
        inc     a
        ld      (fdc_rescnt),a
        dec     a                   ; index of the byte just read
        jr      z,fr_lp             ; ST0: ignored (IC bits benign)
        dec     a
        jr      nz,fr_i2
        ld      a,b
        ld      (fdc_st1),a
        jr      fr_lp
fr_i2:
        dec     a
        jr      nz,fr_lp            ; byte 4+: drain
        ld      a,b
        ld      (fdc_st2),a
        jr      fr_lp
fr_done:
        ld      a,(fdc_abort)
        or      a
        jr      nz,fr_fail
        ld      a,(fdc_st1)
        and     #37                 ; MA|NW|ND|OR|DE (EN masked)
        jr      nz,fr_fail
        ld      a,(fdc_st2)
        and     #77
        jr      nz,fr_fail
        or      a                   ; CF=0: success
        ret
fr_fail:
        scf
        ret

; ----------------------------------------------------------------------------
;  fdc_reinit — re-home before an attempt: complete a half-sent command
;  with inert zeroes, flush a stale result phase, drain interrupts,
;  SPECIFY (ND=1), RECALIBRATE.
; ----------------------------------------------------------------------------
fdc_reinit:
        xor     a
        ld      (fdc_abort),a
        ld      b,16                ; half-sent command? feed zero params
fri_zf:
        push    bc
        ld      bc,FDC_MSR
        in      a,(c)
        and     #D0
        cp      #90                 ; command phase, awaiting parameters
        jr      nz,fri_zf_done
        xor     a
        call    send_fdc
        pop     bc
        djnz    fri_zf
        jr      fri_flush
fri_zf_done:
        pop     bc
fri_flush:
        ld      b,16                ; stale result bytes? flush them
fri_sd:
        push    bc
        ld      bc,FDC_MSR
        in      a,(c)
        and     #C0
        cp      #C0
        jr      nz,fri_sd_done
        inc     c
        in      a,(c)
        pop     bc
        djnz    fri_sd
        jr      fri_spec
fri_sd_done:
        pop     bc
fri_spec:
        call    fdc_sis_drain       ; a pending int would EAT SPECIFY
        ld      a,#03               ; SPECIFY
        call    send_fdc
        ld      a,#8F               ; (SRT<<4)|HUT
        call    send_fdc
        ld      a,#1F               ; (HLT<<1)|ND — ND=1: polled mode
        call    send_fdc
        call    fdc_sis_drain
        ld      a,#07               ; RECALIBRATE
        call    send_fdc
        xor     a
        call    send_fdc
        jp      fdc_wait_seek

fdc_seek:
        ld      a,(fdc_abort)
        or      a
        ret     nz
        call    fdc_sis_drain
        ld      a,#0F               ; SEEK
        call    send_fdc
        xor     a
        call    send_fdc
        ld      a,SCORE_TRACK
        call    send_fdc
        ; fall through

; ----------------------------------------------------------------------------
;  fdc_wait_seek — SENSE INTERRUPT until Seek-End (1-byte #80 = not yet)
; ----------------------------------------------------------------------------
fdc_wait_seek:
        push    de
        ld      de,FDC_STO
fws_lp:
        ld      a,(fdc_abort)
        or      a
        jr      nz,fws_end
        ld      a,#08               ; SENSE INTERRUPT STATUS
        call    send_fdc
        call    recv_fdc            ; ST0
        ld      b,a
        and     #C0
        cp      #C0                 ; ready-change: 2-byte reply, drain
        jr      z,fws_rc
        bit     5,b                 ; Seek End?
        jr      nz,fws_se
        dec     de                  ; #80 invalid: not finished yet
        ld      a,d
        or      e
        jr      nz,fws_lp
        ld      a,1
        ld      (fdc_abort),a
fws_end:
        pop     de
        ret
fws_rc:
        call    recv_fdc            ; PCN, discard
        jr      fws_lp
fws_se:
        call    recv_fdc            ; PCN, discard
        pop     de
        ret

; ----------------------------------------------------------------------------
;  fdc_sis_drain — SENSE INTERRUPT until the 1-byte "nothing pending"
;  (emulators latch an op-complete interrupt that eats the next command)
; ----------------------------------------------------------------------------
fdc_sis_drain:
        ld      b,8
fsd_lp:
        push    bc
        ld      a,#08
        call    send_fdc
        call    recv_fdc            ; ST0
        cp      #80
        jr      z,fsd_done
        call    recv_fdc            ; PCN of the 2-byte reply
        pop     bc
        djnz    fsd_lp
        ret
fsd_done:
        pop     bc
        ret

; ----------------------------------------------------------------------------
;  send_fdc / recv_fdc — one byte each way, direction-checked, bounded
; ----------------------------------------------------------------------------
send_fdc:
        push    af
        ld      a,(fdc_abort)
        or      a
        jr      nz,sf_swallow       ; aborted: swallow the rest
        push    de
        ld      de,FDC_TO
sf_wait:
        ld      bc,FDC_MSR
        in      a,(c)
        add     a,a                 ; CF = RQM, SF = DIO
        jr      nc,sf_cnt           ; not ready
        jp      m,sf_cnt            ; FDC wants to TALK: wrong direction
        pop     de
        pop     af
        inc     c
        out     (c),a               ; -> #FB7F
        ret
sf_cnt:
        dec     de
        ld      a,d
        or      e
        jr      nz,sf_wait
        ld      a,1
        ld      (fdc_abort),a
        pop     de
sf_swallow:
        pop     af
        ret

recv_fdc:
        ld      a,(fdc_abort)
        or      a
        ret     nz
        push    de
        ld      de,FDC_TO
rf_wait:
        ld      bc,FDC_MSR
        in      a,(c)
        add     a,a
        jr      nc,rf_cnt
        jp      p,rf_cnt            ; DIO=0: nothing to read yet
        pop     de
        inc     c
        in      a,(c)               ; <- #FB7F
        ret
rf_cnt:
        dec     de
        ld      a,d
        or      e
        jr      nz,rf_wait
        ld      a,1
        ld      (fdc_abort),a
        pop     de
        ret

; ----------------------------------------------------------------------------
;  motor control + ~1s spin-up
; ----------------------------------------------------------------------------
fdc_motor_on:
        xor     a
        ld      (fdc_abort),a
        ld      bc,FDC_MOTOR
        ld      a,1
        out     (c),a
        ld      de,#04B0            ; ~1s at 4 MHz
fmo_out:
        ld      b,0
fmo_in:
        djnz    fmo_in
        dec     de
        ld      a,d
        or      e
        jr      nz,fmo_out
        ret

fdc_off:
        push    af
        ld      bc,FDC_MOTOR
        xor     a
        out     (c),a
        pop     af
        ret

fdc_st1:        db      0
fdc_st2:        db      0
fdc_rescnt:     db      0
