; ============================================================================
;  FURIOUS FOWLS — input.asm
;  Keyboard matrix scanner, firmware-free.
;
;  The CPC keyboard is a 10x8 matrix read through the AY-3-8912's I/O port:
;  PPI port C bits 0-3 select the row (via a 74LS145 decoder) and bits 7-6
;  drive the PSG bus control lines; the column byte comes back through PSG
;  register 14 onto PPI port A.
;
;  kbd_scan stores all ten rows INVERTED, so a set bit means pressed, and
;  derives kbd_edge: bits set only on the frame a key goes down. Interrupts
;  are masked across the PSG handshake so nothing can interleave its own
;  register accesses halfway through.
; ============================================================================

; ----------------------------------------------------------------------------
;  psg_init — put the AY into a state where the keyboard can be READ.
;
;  Register 7 bit 6 is the direction of the PSG's port A, and port A is
;  where the keyboard's column byte comes back. If the firmware left it as
;  an OUTPUT — and we page the firmware out without ever telling the PSG
;  otherwise — every read returns the same value, so keys appear stuck:
;  hold SPACE and the sling winds up, let go and it never lets go, because
;  as far as the game can tell you are still holding it.
;
;  #3F is also every tone and noise channel disabled, so nothing is left
;  humming from whatever the loader was doing.
; ----------------------------------------------------------------------------
psg_init:
        ld      hl,psg_boot
        ld      b,4
pi_loop:
        push    bc
        ld      d,(hl)
        inc     hl
        ld      e,(hl)
        inc     hl
        push    hl
        call    psg_write
        pop     hl
        pop     bc
        djnz    pi_loop
        ret

psg_boot:
        db      7,#3F               ; both ports INPUT, all channels off
        db      8,0                 ; ...and silent
        db      9,0
        db      10,0

; ---- psg_write — D = register, E = value -----------------------------------
psg_write:
        di
        ld      bc,PPI_CONTROL
        ld      a,#82
        out     (c),a               ; 8255: port A to output
        ld      b,#F4
        out     (c),d               ; the register number on the bus
        ld      b,#F6
        ld      a,#C0
        out     (c),a               ; BDIR=1 BC1=1: latch it
        xor     a
        out     (c),a
        ld      b,#F4
        out     (c),e               ; the value on the bus
        ld      b,#F6
        ld      a,#80
        out     (c),a               ; BDIR=1 BC1=0: write it
        xor     a
        out     (c),a
        ei
        ret

kbd_scan:
        di
        ld      bc,PPI_CONTROL
        ld      a,#82
        out     (c),a               ; 8255: port A to output
        ld      b,#F4
        ld      a,14
        out     (c),a               ; PSG register 14 onto the bus
        ld      b,#F6
        ld      a,#C0
        out     (c),a               ; BDIR=1 BC1=1: latch the register number
        xor     a
        out     (c),a               ; PSG inactive
        ld      b,#F7
        ld      a,#92
        out     (c),a               ; 8255: port A to input
        ld      hl,kbd_state
        ld      e,#40               ; BDIR=0 BC1=1 (read) + row 0
kbd_row:
        ld      b,#F6
        out     (c),e
        ld      b,#F4
        in      a,(c)               ; column bits, 0 = pressed
        cpl
        ld      d,a
        ld      a,(hl)              ; last frame
        cpl
        and     d                   ; rising edges only
        push    hl                  ; the edge array follows the state array.
        push    de                  ; NOT via BC: C is the low half of the
        ld      de,KBD_ROWS         ; port address every OUT below uses
        add     hl,de
        pop     de
        ld      (hl),a
        pop     hl
        ld      (hl),d
        inc     hl
        inc     e
        ld      a,e
        cp      #40+KBD_ROWS
        jr      nz,kbd_row
        ld      b,#F6
        xor     a
        out     (c),a
        ld      b,#F7
        ld      a,#82
        out     (c),a               ; port A back to output
        ei
        ret

kbd_state:      ds      KBD_ROWS    ; 1 = held
kbd_edge:       ds      KBD_ROWS    ; 1 = pressed this frame
