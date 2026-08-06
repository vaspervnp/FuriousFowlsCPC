#!/bin/sh
# ============================================================================
#  make_loader.sh — generate the AMSDOS ASCII BASIC bootloader (FOWLS.BAS)
#
#  Shows the REVIVE8BIT Mode 0 splash (REVIVE8B.SCR straight into video RAM
#  at &C000, inks from assets/revive8b.txt), waits for SPACE or ten seconds
#  (TIME ticks at 300 Hz), then loads the game.
#
#  Then two binaries, in this order:
#    FOWLART.BIN -> &C000, the creature frames plus the sine and sound
#                   tables, parked in video RAM. There is nowhere else to
#                   put 14 KB that has to reach #0400: the running BASIC
#                   program is sitting on that address.
#    FOWLS.BIN   -> &4000, the game itself plus the block art at #8000.
#
#  THE INKS GO BLACK TWICE, and the second time is the one that matters.
#  Creepers can leave its splash up while it loads, because nothing else it
#  loads goes anywhere near the screen. Here FOWLART.BIN lands on &C000 —
#  the splash's own pixels — so without blacking out first, the player
#  watches the artwork dissolve into fourteen kilobytes of sprite data.
#
#  Then CALL &4000, and the first thing entry_point does is copy the art
#  down out of video RAM and wipe the screen.
#
#  Imported as an AMSDOS ASCII file (iDSK -t 0), so the user types RUN"FOWLS".
#  ASCII conventions: CRLF line endings, 0x1A (^Z) end-of-file marker.
# ============================================================================
set -e
out="${1:-build/FOWLS.BAS}"

{
    printf '10 REM FURIOUS FOWLS loader\r\n'
    printf '20 BORDER 0:MODE 0:FOR i=0 TO 15:INK i,0:NEXT\r\n'
    printf '30 MEMORY &3FFF\r\n'
    printf '40 LOAD"REVIVE8B.SCR",&C000\r\n'
    printf '50 INK 0,0:INK 1,13:INK 2,26:INK 3,15:INK 4,25:INK 5,10:INK 6,3:INK 7,1\r\n'
    printf '60 INK 8,11:INK 9,23:INK 10,6:INK 11,24:INK 12,20:INK 13,16:INK 14,12:INK 15,4\r\n'
    printf '70 t=TIME+3000\r\n'
    printf '80 IF INKEY(47)<>-1 THEN 100\r\n'
    printf '90 IF TIME<t THEN 80\r\n'
    printf '100 FOR i=0 TO 15:INK i,0:NEXT\r\n'
    printf '110 LOAD"FOWLART.BIN",&C000\r\n'
    printf '120 LOAD"FOWLS.BIN",&4000\r\n'
    printf '130 CALL &4000\r\n'
    printf '\032'
} > "$out"

echo "wrote $out"
