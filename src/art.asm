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
        include "level_defs.inc"
        include "art_defs.inc"
        include "sound_defs.inc"
        include "music_defs.inc"
        include "hardware.inc"

        org     #C000
        incbin  "creatures.raw"

;  ...and behind it the read-only tables the code bank cannot hold. The
;  order here IS the memory map: each block is padded up to the address
;  hardware.inc declares for it, so the two files cannot drift apart —
;  change an address there and the padding here follows it.
        defs    #C000+(sin_table-CREATURE_ART)-$, 0
        incbin  "sin.raw"
        incbin  "sounds.raw"
        incbin  "font.raw"
        incbin  "scenofs.raw"
        assert  $ == #C000+(line_lut-CREATURE_ART)

;  ...and behind THOSE, the title theme. It is not part of the block that
;  gets copied to low memory — main.asm gives it its own LDIR, into the
;  space the tilted block art will want once a level loads. That is not a
;  trick to save room, it is the lifetime: the music should stop exactly
;  when the game starts, and this way the bytes are gone by then anyway.
        incbin  "music.raw"
