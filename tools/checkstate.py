#!/usr/bin/env python3
# ============================================================================
#  checkstate.py — two things the assembler will never tell you.
#
#      python3 tools/checkstate.py
#
#  1. TWO NAMES ON ONE BYTE. src/state.inc is a page of equates, not
#     reservations. Write `level_theme equ vars+10` next to the `sling_x
#     equ vars+10` that is already there and RASM is perfectly happy; you
#     find out when level_load writes the fork's x over the sky colour and
#     the ground comes out right while the sky comes out wrong. This
#     resolves every equate in the file and says which names collide.
#
#     A collision is not always a bug — a few names here deliberately
#     alias — so ALIASES lists the ones that are meant, and anything else
#     is an error.
#
#  2. A THEME SKY THAT IS ALSO A PEN. Pen 0 is only ever the sky, but the
#     other fifteen hardware colours belong to the art. Set the sky to
#     HW_ORANGE and every wooden thing in the game is the colour of the
#     sky behind it.
# ============================================================================
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

STATE = 'src/state.inc'
VIDEO = 'src/video.asm'

#  Names that share a byte on purpose.
ALIASES = {
    frozenset(('music_base', 'rot_art')),   # the theme borrows the tilt art
    frozenset(('sec_buf', 'hud_buf')),      # the disc sector borrows the HUD
    frozenset(('colbuf', 'state_base')),    # ...and the first thing in a
    frozenset(('cam_x', 'vars')),           # block is at the block's base
}

EQU = re.compile(r'^\s*(\w+)\s+equ\s+([^;]+?)\s*(?:;.*)?$', re.I | re.M)


def resolve(path, seed):
    """Evaluate the file's equates in order. Anything that will not
    evaluate yet is left out rather than guessed at."""
    vals = dict(seed)
    for name, expr in EQU.findall(open(path).read()):
        e = re.sub(r'#([0-9A-Fa-f]+)', r'0x\1', expr).lower()
        try:
            vals[name.lower()] = eval(e, {'__builtins__': {}},
                                      {k: v for k, v in vals.items()})
        except Exception:
            pass                            # forward reference or a symbol
    return vals                             # from somewhere else: skip it


def main():
    #  The sizes state.inc is built on, from the two files that own them.
    seed = {}
    for path in ('src/hardware.inc', 'build/level_defs.inc',
                 'build/art_defs.inc', 'build/rot_defs.inc'):
        if os.path.exists(path):
            seed.update(resolve(path, seed))

    vals = resolve(STATE, seed)
    #  Only names DEFINED in state.inc. The seeds carry I/O port addresses
    #  from hardware.inc — CRTC_DAT is #BD00 — and once the state block
    #  grew past them the checker started reporting a port and a variable
    #  as a collision. They are different address spaces.
    mine = set(n.lower() for n, _ in EQU.findall(open(STATE).read()))

    #  Only the addresses in the state block, not the SIZE constants.
    base, end = vals.get('state_base'), vals.get('state_end')
    if base is None:
        raise SystemExit('checkstate: cannot resolve STATE_BASE')
    at = {}
    for name, v in vals.items():
        if name not in mine:
            continue
        if not isinstance(v, int) or not base <= v < (end or 0xC000):
            continue
        if name.endswith('_size') or name.endswith('_stride'):
            continue
        at.setdefault(v, []).append(name)

    bad = 0
    for addr in sorted(at):
        names = sorted(at[addr])
        if len(names) < 2 or frozenset(names) in ALIASES:
            continue
        print('  %04X: %s' % (addr, ' and '.join(names)))
        bad += 1
    if bad:
        print('checkstate: %d address(es) with more than one name' % bad)

    #  ...and the sky against the pens.
    import levels
    pens = re.findall(r'db\s+(HW_\w+)', open(VIDEO).read())[1:16]
    for name, sky, _bands in levels.THEMES:
        if sky in pens:
            print('  theme %r: sky %s is also a pen — everything drawn in '
                  'that colour vanishes' % (name, sky))
            bad += 1

    if bad:
        raise SystemExit(1)
    print('checkstate: %d state addresses, no collisions; %d themes, no '
          'sky is a pen' % (len(at), len(levels.THEMES)))


if __name__ == '__main__':
    main()
