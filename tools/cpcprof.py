#!/usr/bin/env python3
# ============================================================================
#  cpcprof.py — a sampling profiler for the game, in the headless emulator.
#
#      python3 tools/cpcprof.py --keys 160:space+ 168:space- 300:right+ \
#                               --from 330 --to 460
#
#  Stops the Z80 every SAMPLE T-states, reads the program counter, and
#  attributes it to the nearest label at or below it in build/fowls.sym.
#  That is the whole idea; there is nothing clever in it.
#
#  WHY: the scroll seam had to fit in what is left of a frame after the
#  beam has passed, and it did not. Timing it end to end said five
#  interrupt ticks and no more — which routine was spending them was a
#  guess, and the guesses were wrong twice. A profiler is forty lines and
#  it answers the question.
# ============================================================================
import collections
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
os.environ.setdefault('FOWLS_OUT', 'build/shots/prof')

SAMPLE = 137            # T-states between samples. Prime, so it does not
                        # beat against any loop in the game.


def symbols(path='build/fowls.sym'):
    out = []
    for line in open(path):
        w = line.split()
        if len(w) >= 2 and w[1].startswith('#'):
            out.append((int(w[1][1:], 16), w[0]))
    out.sort()
    return out


def owner(syms, pc):
    lo, hi = 0, len(syms) - 1
    if pc < syms[0][0]:
        return '(below the code)'
    while lo < hi:
        mid = (lo + hi + 1) // 2
        if syms[mid][0] <= pc:
            lo = mid
        else:
            hi = mid - 1
    return syms[lo][1]


def main(argv):
    import cpcshot as S
    keys, first, last = {}, 0, 10 ** 9
    i = 1
    while i < len(argv):
        a = argv[i]
        if a == '--keys':
            i += 1
            while i < len(argv) and not argv[i].startswith('--'):
                f, k = argv[i].split(':')
                keys.setdefault(int(f), []).append(k)
                i += 1
            continue
        if a == '--from':
            first = int(argv[i + 1]); i += 2; continue
        if a == '--to':
            last = int(argv[i + 1]); i += 2; continue
        i += 1

    syms = symbols()
    hits = collections.Counter()
    total = 0
    for f in range(1, last + 20):
        for k in keys.get(f, []):
            n, act = k[:-1], k[-1]
            (S.pressed.add if act == '+' else S.pressed.discard)(S.KEYS[n])
        sampling = first <= f <= last
        for s in range(S.SLICES):
            S.state['slice'] = s
            left = S.FRAME_TICKS // S.SLICES
            while left > 0:
                step = min(SAMPLE if sampling else 500, left)
                S.m.ticks_to_stop = step
                left -= step
                S.m.run()
                if sampling:
                    hits[owner(syms, S.m.pc)] += 1
                    total += 1
            S.m.on_handle_active_int()
        S.state['frame'] += 1
        if f > last:
            break

    print('%d samples over frames %d..%d\n' % (total, first, last))
    print('%-28s %7s  %s' % ('routine', 'share', ''))
    for name, n in hits.most_common(24):
        pct = 100.0 * n / max(total, 1)
        print('%-28s %6.2f%%  %s' % (name.lower(), pct, '#' * int(pct)))


if __name__ == '__main__':
    main(sys.argv)
