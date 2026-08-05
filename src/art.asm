; ============================================================================
;  FURIOUS FOWLS — art.asm
;  The creature bank, assembled as its own file.
;
;  Fifty-four 16x32 frames is 13.5 KB and it has to end up at #0400, which
;  no AMSDOS load can reach while BASIC is still running — the loader's own
;  program lives there. So the loader parks it in VIDEO RAM instead, which
;  is ordinary memory until something draws on it, and entry_point in
;  main.asm copies it down before wiping the screen. The inks are black
;  through all of it, so nobody sees the mess.
; ============================================================================
        org     #C000
        incbin  "creatures.raw"
