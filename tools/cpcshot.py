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
DSK_PATH = os.environ.get('FOWLS_DSK', 'dist/fowls.dsk')
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
    if fdc is not None and addr == 0xFB7F:
        fdc.wr(val)
        return
    if fdc is not None and addr == 0xFA7E:
        fdc.motor = val
        return
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


# ---------------- a uPD765 just big enough to hold a high score -------------
#  Not a floppy controller: the four commands src/disk.asm actually sends,
#  with one sector behind them, read from and written back to the DSK image
#  on disc. Without it the driver is untestable — every wait times out, the
#  game boots six seconds late and a save can never be proved to have
#  happened. With it, "save, reboot, load" is a two-line test.
class FDC:
    def __init__(self, path, track, sect):
        self.path, self.track, self.sect = path, track, sect
        self.off = self._locate()
        self.motor = 0
        self.phase = 'cmd'          # cmd | exec_r | exec_w | res
        self.buf, self.want, self.res, self.ri = [], 0, [], 0
        self.data, self.di = bytearray(512), 0
        self.pending = None         # SENSE INTERRUPT reply, once
        self.writes = 0

    def _locate(self):
        """Byte offset of (track, sect) in an EXTENDED DSK."""
        d = open(self.path, 'rb').read()
        assert d[:8] == b'EXTENDED', 'expected an extended DSK'
        ntrk, nside = d[0x30], d[0x31]
        pos = 256
        for t in range(ntrk):
            size = d[0x34 + t] * 256
            if t == self.track:
                blk = d[pos:pos + size]
                assert blk[:10] == b'Track-Info'
                nsec, off = blk[0x15], pos + 256
                for i in range(nsec):
                    e = 0x18 + i * 8
                    ln = blk[e + 6] | (blk[e + 7] << 8)
                    if blk[e + 2] == self.sect:
                        return off
                    off += ln
                raise SystemExit('sector %02X not on track %d' % (self.sect, t))
            pos += size
        raise SystemExit('track %d not in the image' % self.track)

    def read_sector(self):
        with open(self.path, 'rb') as f:
            f.seek(self.off)
            return bytearray(f.read(512))

    def write_sector(self, data):
        with open(self.path, 'r+b') as f:
            f.seek(self.off)
            f.write(bytes(data))
        self.writes += 1

    #  MSR: bit7 RQM, bit6 DIO (1 = FDC->CPU), bit5 EXM, bit4 CB
    def msr(self):
        if self.phase == 'cmd':
            return 0x80 | (0x10 if self.buf else 0)
        if self.phase == 'exec_w':
            return 0xB0                 # RQM, EXM, CB — CPU writes data
        if self.phase == 'exec_r':
            return 0xF0                 # RQM, DIO, EXM, CB — CPU reads data
        return 0xD0                     # result: RQM, DIO, CB

    #  Keyed on the base opcode: the MFM and MT bits live above bit 4.
    PARAMS = {0x03: 2, 0x07: 1, 0x08: 0, 0x0F: 2, 0x05: 8, 0x06: 8}

    def wr(self, v):
        if self.phase == 'exec_w':
            self.data[self.di] = v
            self.di += 1
            if self.di == 512:
                self.write_sector(self.data)
                self.phase, self.res, self.ri = 'res', [0x40, 0x80, 0, 0, 0, 0, 2], 0
            return
        if self.phase != 'cmd':
            return
        self.buf.append(v)
        need = self.PARAMS.get(self.buf[0] & 0x1F)
        if need is None:
            self.buf = []
            return
        if len(self.buf) < need + 1:
            return
        cmd, self.buf = self.buf, []
        c = cmd[0] & 0x1F
        if c == 0x03:                               # SPECIFY
            pass
        elif c in (0x07, 0x0F):                     # RECALIBRATE / SEEK
            self.pending = [0x20, cmd[2] if c == 0x0F else 0]
        elif c == 0x08:                             # SENSE INTERRUPT
            if self.pending:
                self.phase, self.res, self.ri = 'res', self.pending, 0
                self.pending = None
            else:
                self.phase, self.res, self.ri = 'res', [0x80], 0
        elif c == 0x06:                             # READ DATA
            self.data, self.di, self.phase = self.read_sector(), 0, 'exec_r'
        elif c == 0x05:                             # WRITE DATA
            self.data, self.di, self.phase = bytearray(512), 0, 'exec_w'

    def rd(self):
        if self.phase == 'exec_r':
            v = self.data[self.di]
            self.di += 1
            if self.di == 512:
                self.phase, self.res, self.ri = 'res', [0x40, 0x80, 0, 0, 0, 0, 2], 0
            return v
        if self.phase == 'res':
            v = self.res[self.ri]
            self.ri += 1
            if self.ri == len(self.res):
                self.phase, self.res = 'cmd', []
            return v
        return 0xFF


fdc = FDC(DSK_PATH, 0, 0xC5) if os.path.exists(DSK_PATH) else None


def on_in(addr):
    hi = addr >> 8
    if fdc is not None and addr == 0xFB7E:
        return fdc.msr()
    if fdc is not None and addr == 0xFB7F:
        return fdc.rd()
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


# ---------------------------------------------------------------------------
#  BEAM-ACCURATE CAPTURE
#
#  screenshot() reads video RAM once, after the frame has been emulated. That
#  is not what the player saw. Anything written after the beam had passed
#  shows up in it although nobody saw it, and — worse — anything written
#  before the beam arrived and corrected afterwards does NOT show up although
#  everybody saw it. Chasing the scroll seam with it produced a clean bill of
#  health for a machine that was visibly wrong.
#
#  run_frame_beam() emulates the frame in CHAR-ROW slices and copies each row
#  out of video RAM at the moment the beam would have been over it, with the
#  CRTC offset that was programmed then. The result is a picture of the
#  frame as displayed.
#
#  The display is 25 char rows of 8 lines; the top border is about 5 rows of
#  the 39-row PAL frame, so the beam is over char row n from roughly
#  FRAME_TICKS * (5 + n) / 39 into the frame.
# ---------------------------------------------------------------------------
BEAM_ROWS = 25
BEAM_TOP = 5                      # char rows of top border before row 0
BEAM_TOTAL = 39                   # char rows in the whole PAL frame


def run_frame_beam():
    """One frame, captured as the beam draws it -> a list of 200 rows, each
    a list of `cols*8` pen numbers."""
    cols = crtc[1] or 40
    out = []
    done = 0
    for row in range(-BEAM_TOP, BEAM_TOTAL - BEAM_TOP):
        want = FRAME_TICKS * (row + BEAM_TOP + 1) // BEAM_TOTAL
        while done < want:
            step = min(want - done, FRAME_TICKS // SLICES)
            #  keep the interrupt slices ticking at the right rate
            slice_now = min(SLICES - 1, done * SLICES // FRAME_TICKS)
            state['slice'] = slice_now
            m.ticks_to_stop = step
            m.run()
            done += step
            if (done * SLICES // FRAME_TICKS) != slice_now:
                m.on_handle_active_int()
        if 0 <= row < BEAM_ROWS:
            off = ((crtc[12] & 3) << 8) | crtc[13]
            for line in range(8):
                y = row * 8 + line
                base = 0xC000 + (y & 7) * 0x800
                roff = off + row * cols
                pens_row = []
                for c in range(cols):
                    a = base + ((roff + c) & 0x3FF) * 2
                    for byte in (m.memory[a], m.memory[a + 1]):
                        p0, p1 = decode_pixels(byte)
                        pens_row.append(p0)
                        pens_row.append(p1)
                out.append(pens_row)
    state['frame'] += 1
    return out


def beam_png(rows, name, scale=4):
    rgb = [hw_rgb(p) for p in pens]
    W = len(rows[0]) * scale
    raw = []
    for r in rows:
        line = b''.join(bytes(rgb[p]) * scale for p in r)
        raw.append(b'\x00' + line)
        raw.append(b'\x00' + line)

    def chunk(t, d):
        c = t + d
        return struct.pack('>I', len(d)) + c + struct.pack('>I', zlib.crc32(c))
    png = (b'\x89PNG\r\n\x1a\n'
           + chunk(b'IHDR', struct.pack('>IIBBBBB', W, len(rows) * 2,
                                        8, 2, 0, 0, 0))
           + chunk(b'IDAT', zlib.compress(b''.join(raw), 6))
           + chunk(b'IEND', b''))
    os.makedirs(OUT, exist_ok=True)
    open('%s/%s.png' % (OUT, name), 'wb').write(png)


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
