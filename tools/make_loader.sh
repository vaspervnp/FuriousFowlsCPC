#!/bin/sh
# ============================================================================
#  make_loader.sh — generate the AMSDOS ASCII BASIC bootloader (FOWLS.BAS)
#
#  Two binaries, in this order:
#    FOWLART.BIN -> &C000, the creature frames parked in video RAM. There is
#                   nowhere else to put 13.5 KB that has to reach #0400:
#                   the running BASIC program is sitting on that address.
#                   Every ink is black by then, so the garbage never shows.
#    FOWLS.BIN   -> &4000, the game itself plus the block art at #8000.
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
    printf '20 MODE 0:BORDER 0:FOR i=0 TO 15:INK i,0:NEXT\r\n'
    printf '30 MEMORY &3FFF\r\n'
    printf '40 LOAD"FOWLART.BIN",&C000\r\n'
    printf '50 LOAD"FOWLS.BIN",&4000\r\n'
    printf '60 CALL &4000\r\n'
    printf '\032'
} > "$out"

echo "wrote $out"
