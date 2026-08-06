#!/usr/bin/env python3
# ============================================================================
#  cpcshot.py — run the game headless and take screenshots.
#
#      python3 tools/cpcshot.py 1 30 120         frames to capture
#      python3 tools/cpcshot.py --keys 60:space+ 200:space- 260
#
#  A Z80 emulator with just enough CPC around it — Gate Array, CRTC, PPI and
#  the PSG's keyboard port — to boot the real binary and decode the real
#  screen. That makes it possible to SEE whether a change worked without a
#  human at an emulator, which for a game this far from a test harness is
#  the difference between checking and hoping.
#
#  The load is exactly what the BASIC loader does: FOWLART.BIN into video
#  RAM, FOWLS.BIN at #4000, then CALL &4000.
#
#  --keys takes frame:key+ / frame:key- events (press and release).
#
#  NOTE for anyone reaching for m.set_write_callback to trap a stray write:
#  the callback REPLACES the write, it does not observe it. Your handler has
#  to do `mem[addr] = value` itself or the machine silently stops storing
#  anything and you will spend a while wondering why the screen went blank.
# ============================================================================
import os
import struct
import sys
import zlib

import z80

BUILD = 'build'
OUT = os.environ.get('FOWLS_OUT', 'build/shots')
FRAME_TICKS = 79872
SLICES = 6

# ---------------- CPC colour tables -----------------------------------------
HW2FW = {0x54: 0, 0x44: 1, 0x55: 2, 0x5C: 3, 0x58: 4, 0x5D: 5, 0x4C: 6,
         0x45: 7, 0x4D: 8, 0x56: 9, 0x46: 10, 0x57: 11, 0x5E: 12, 0x40: 13,
         0x5F: 14, 0x4E: 15, 0x47: 16, 0x4F: 17, 0x52: 18, 0x42: 19,
         0x53: 20, 0x5A: 21, 0x59: 22, 0x5B: 23, 0x4A: 24, 0x43: 25,
         0x4B: 26}
LVL = [0, 0x80, 0xFF]


def hw_rgb(hw):
    fw = HW2FW.get(hw & 0x5F, 0)
    g, rem = divmod(fw, 9)
    r, b = divmod(rem, 3)
    return (LVL[r], LVL[g], LVL[b])


# ---------------- the keys the game uses ------------------------------------
KEYS = {
    'up': (0, 0), 'right': (0, 1), 'down': (0, 2),
    'left': (1, 0), 'copy': (1, 1), 'shift': (2, 5),
    'space': (5, 7), 'n': (5, 6), 'r': (6, 2), 'esc': (8, 2),
}

# ---------------- machine ---------------------------------------------------
m = z80.Z80Machine()
art = open(os.path.join(BUILD, 'FOWLART.BIN'), 'rb').read()
game = open(os.path.join(BUILD, 'FOWLS.BIN'), 'rb').read()
m.memory[0xC000:0xC000 + len(art)] = art
m.memory[0x4000:0x4000 + len(game)] = game
m.pc = 0x4000
m.sp = 0x4000

pens = [0x54] * 17
crtc = [0] * 32
state = {'pensel': 0, 'crtcsel': 0, 'ppia': 0, 'ppic': 0, 'psgsel': 0,
         'frame': 0, 'slice': 0}
psg = [0] * 16
pressed = set()


def on_out(addr, val):
    hi = addr >> 8
    if hi == 0x7F:
        top = val & 0xC0
        if top == 0x00:
            state['pensel'] = 16 if (val & 0x10) else (val & 0x0F)
        elif top == 0x40:
            pens[state['pensel']] = val & 0x5F
    elif hi == 0xBC:
        state['crtcsel'] = val & 0x1F
    elif hi == 0xBD:
        crtc[state['crtcsel']] = val
    elif hi == 0xF4:
        state['ppia'] = val
    elif hi == 0xF6:
        state['ppic'] = val
        top = val & 0xC0
        if top == 0xC0:
            state['psgsel'] = state['ppia'] & 0x0F
        elif top == 0x80:
            psg[state['psgsel']] = state['ppia']


def on_in(addr):
    hi = addr >> 8
    if hi == 0xF5:                      # VSYNC during slice 0
        return 0x01 if state['slice'] == 0 else 0x00
    if hi == 0xF4:
        if (state['ppic'] & 0xC0) != 0x40:
            return 0xFF
        if state['psgsel'] == 14:
            if psg[7] & 0x40:
                return 0xFF
            row = state['ppic'] & 0x0F
            v = 0
            for r, b in pressed:
                if r == row:
                    v |= (1 << b)
            return (~v) & 0xFF
        return psg[state['psgsel']]
    return 0xFF


m.set_output_callback(on_out)
m.set_input_callback(on_in)


def run_frame():
    for s in range(SLICES):
        state['slice'] = s
        m.ticks_to_stop = FRAME_TICKS // SLICES
        m.run()
        m.on_handle_active_int()
    state['frame'] += 1


# ---------------- screen decode + PNG ---------------------------------------
def decode_pixels(byte):
    def pix(right):
        s = 1 if right else 0
        p = 0
        for bit, pb in ((7 - s, 0), (3 - s, 1), (5 - s, 2), (1 - s, 3)):
            if byte & (1 << bit):
                p |= (1 << pb)
        return p
    return pix(False), pix(True)


def screenshot(name):
    off = ((crtc[12] & 3) << 8) | crtc[13]
    #  R1 is BOTH the displayed width and the ring row stride — the 6845
    #  advances MA by R1 per character row. Hard-coding 40 here decodes a
    #  39-column screen into diagonal stairs and blames the game for it.
    cols = crtc[1] or 40
    rgb = [hw_rgb(p) for p in pens]
    BW = 24                             # border, in output pixels
    W = cols * 4 * 4
    rows = []
    brd = bytes(rgb[16])
    brow = brd * (W + 2 * BW)
    for _ in range(BW):
        rows.append(brow)
    mem = m.memory
    for y in range(200):
        line = bytearray(brd * BW)
        base = 0xC000 + (y & 7) * 0x800
        roff = off + (y >> 3) * cols
        for c in range(cols):
            ring = (roff + c) & 0x3FF
            a = base + ring * 2
            for byte in (mem[a], mem[a + 1]):
                p0, p1 = decode_pixels(byte)
                line += bytes(rgb[p0]) * 4
                line += bytes(rgb[p1]) * 4
        line += brd * BW
        rows.append(bytes(line))
        rows.append(bytes(line))
    for _ in range(BW):
        rows.append(brow)
    w, h = W + 2 * BW, 400 + 2 * BW
    raw = b''.join(b'\x00' + r for r in rows)

    def chunk(t, d):
        c = t + d
        return struct.pack('>I', len(d)) + c + struct.pack('>I', zlib.crc32(c))
    png = (b'\x89PNG\r\n\x1a\n'
           + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0))
           + chunk(b'IDAT', zlib.compress(raw, 6))
           + chunk(b'IEND', b''))
    os.makedirs(OUT, exist_ok=True)
    open('%s/%s.png' % (OUT, name), 'wb').write(png)
    print('frame %4d -> %s/%s.png  (crtc offset %d, pc %04X)'
          % (state['frame'], OUT, name, off, m.pc), flush=True)


def main(argv):
    shots, events = [], {}
    args = argv[1:]
    i = 0
    while i < len(args):
        a = args[i]
        if a == '--keys':
            i += 1
            while i < len(args) and ':' in args[i]:
                fr, key = args[i].split(':')
                events.setdefault(int(fr), []).append(key)
                i += 1
            continue
        shots.append(int(a))
        i += 1
    if not shots:
        shots = [1, 5, 60]

    last = max(shots + list(events) + [0])
    for f in range(1, last + 1):
        for key in events.get(f, []):
            name, act = key[:-1], key[-1]
            if name not in KEYS:
                raise SystemExit('unknown key %r' % name)
            if act == '+':
                pressed.add(KEYS[name])
            else:
                pressed.discard(KEYS[name])
        run_frame()
        if f in shots:
            screenshot('f%04d' % f)


if __name__ == '__main__':
    main(sys.argv)
