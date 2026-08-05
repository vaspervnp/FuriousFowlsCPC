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
        push    hl
        ld      bc,KBD_ROWS         ; the edge array follows the state array
        add     hl,bc
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
