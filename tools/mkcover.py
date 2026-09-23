#!/usr/bin/env python3
# ============================================================================
#  mkcover.py — the sleeve. A 1985 Amstrad disc cover, drawn from scratch.
#
#      python3 tools/mkcover.py docs
#
#  Writes the full wrap-around inlay — BACK | SPINE | FRONT on one flat
#  2550 x 1600 sheet, 215.9 x 135.5 mm at 300 dpi — plus the front and back
#  as standalone panels, the disc label, and PDFs at the physical size.
#
#  The spine is 12.7 mm, which is the case and not the disc: the media is
#  5 mm, the cassette-style library case it shipped in is 10 to 13, and
#  deriving the spine from the disc is the classic way to end up 6 mm
#  short and pull the front cover's title off centre.
#
#  WHY A PROGRAM AND NOT A PAINTING: same reason the spritesheets are
#  generated — so the thing can be changed. Move the fort, repaint the sky,
#  put the crown on a different pig, run it again.
#
#  The house style of a 1985 sleeve, which is what this is imitating:
#
#    * a colour flash across the top, because the printer had the ink
#    * the title in heavy italic caps with a hard extrude and no blur —
#      airbrush was expensive, a drop shadow was free
#    * the art in a keyline box, not bled to the edge
#    * a format banner along the bottom naming every machine it runs on
#    * at least one starburst
#
#  The subjects are painted in the GAME'S OWN COLOURS — the sixteen
#  firmware pens src/video.asm loads — so the bird on the sleeve is the
#  bird on the screen. Sleeve art in 1985 was famously not, but this one
#  is, and it costs nothing.
# ============================================================================
import os
import sys
import math
import random

from PIL import Image, ImageChops, ImageDraw, ImageFont, ImageFilter

SS = 3                                  # supersample: Pillow has no AA
W, H = 1200, 1600                       # ONE PANEL, never the whole sheet
DPI = 300
SPINE = 150                             # 12.7 mm — see build_spine
SHEET_W = W + SPINE + W

FONT_DIR = '/usr/share/fonts/truetype'
F_TITLE = FONT_DIR + '/roboto/unhinted/RobotoTTF/Roboto-Black.ttf'
F_NARROW = FONT_DIR + '/liberation/LiberationSansNarrow-Bold.ttf'
F_BOLD = FONT_DIR + '/liberation/LiberationSans-Bold.ttf'
F_TEXT = FONT_DIR + '/liberation/LiberationSans-Regular.ttf'


# ---------------------------------------------------------------------------
#  The CPC's palette. Every channel is 0, 128 or 255 and that is the whole
#  of it; the machine cannot make a colour that is not in this list.
# ---------------------------------------------------------------------------
def fw(n):
    """Firmware colour number -> RGB. The 27 colours are green-major,
    then red, then blue, each of them off/half/full — so the whole
    palette is three lines of arithmetic and no lookup table."""
    L = (0, 128, 255)
    return (L[(n % 9) // 3], L[n // 9], L[n % 3])


RED = fw(6)             # 255,0,0    the bird
BROWN = fw(3)           # 128,0,0    trunk, and the shade under everything
ORANGE = fw(15)         # 255,128,0  timber
YELLOW = fw(24)         # 255,255,0  beak, crown
PALEY = fw(25)          # 255,255,128
GREEN = fw(18)          # 0,255,0    the pigs
DGREEN = fw(9)          # 0,128,0
GREY = fw(13)           # 128,128,128 stone
WHITE = fw(26)
BLACK = (0, 0, 0)
PINK = fw(16)

INK = (14, 12, 18)                      # the sleeve's black, not quite black
FLASH = [(214, 26, 32), (240, 126, 20), (247, 200, 24),
         (26, 150, 78), (24, 92, 176), (128, 40, 142)]


def mix(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def shade(c, t):
    """Toward the warm dark the whole picture sits in, not toward black —
    black shading is what makes flat colour look like a diagram."""
    return mix(c, (46, 18, 40), t)


def light(c, t):
    return mix(c, (255, 236, 176), t)


# ---------------------------------------------------------------------------
#  A pen that works in cover coordinates and draws at SS times the size.
# ---------------------------------------------------------------------------
class Pen:
    def __init__(self, img, ox=0, oy=0):
        self.d = ImageDraw.Draw(img)
        self.ox, self.oy = ox, oy

    def _p(self, xy):
        return [((x + self.ox) * SS, (y + self.oy) * SS) for x, y in xy]

    def _b(self, box):
        x0, y0, x1, y1 = box
        return [((x0 + self.ox) * SS, (y0 + self.oy) * SS),
                ((x1 + self.ox) * SS, (y1 + self.oy) * SS)]

    def rect(self, box, fill=None, outline=None, width=1):
        self.d.rectangle(self._b(box), fill=fill, outline=outline,
                         width=max(1, int(width * SS)))

    def ellipse(self, box, fill=None, outline=None, width=1):
        self.d.ellipse(self._b(box), fill=fill, outline=outline,
                       width=max(1, int(width * SS)))

    def poly(self, pts, fill=None, outline=None, width=1):
        self.d.polygon(self._p(pts), fill=fill, outline=outline,
                       width=max(1, int(width * SS)))

    def line(self, pts, fill=None, width=1, joint='curve'):
        self.d.line(self._p(pts), fill=fill, width=max(1, int(width * SS)),
                    joint=joint)

    def arc(self, box, a0, a1, fill=None, width=1):
        self.d.arc(self._b(box), a0, a1, fill=fill,
                   width=max(1, int(width * SS)))


def font(path, size):
    return ImageFont.truetype(path, int(size * SS))


def text(img, xy, s, path, size, fill, anchor='la', spacing=0):
    d = ImageDraw.Draw(img)
    f = font(path, size)
    x, y = xy[0] * SS, xy[1] * SS
    if not spacing:
        d.text((x, y), s, font=f, fill=fill, anchor=anchor)
        return
    #  Letter-spaced, which every piece of 1985 packaging small print was.
    tr = spacing * SS
    total = sum(d.textlength(ch, font=f) + tr for ch in s) - tr
    if anchor[0] == 'm':
        x -= total / 2
    elif anchor[0] == 'r':
        x -= total
    for ch in s:
        d.text((x, y), ch, font=f, fill=fill, anchor='l' + anchor[1])
        x += d.textlength(ch, font=f) + tr


def text_w(s, path, size, spacing=0):
    d = ImageDraw.Draw(Image.new('L', (1, 1)))
    f = font(path, size)
    if not spacing:
        return d.textlength(s, font=f) / SS
    tr = spacing * SS
    return (sum(d.textlength(c, font=f) + tr for c in s) - tr) / SS


# ---------------------------------------------------------------------------
#  THE ILLUSTRATION
#
#  Sunset, because a sunset is four flat bands of colour and a circle and
#  it was on the front of half the software sold that year. The sun sits
#  between the slingshot and the fort so that both of them are rimmed with
#  light on the inside edge, which is the only lighting trick in here and
#  it does all the work.
# ---------------------------------------------------------------------------
AW, AH = 1100, 846
HORIZON = 585
GROUND = 692                            # where things stand

SKY = [(0.00, (26, 10, 56)),
       (0.30, (92, 22, 90)),
       (0.56, (184, 44, 74)),
       (0.76, (236, 102, 34)),
       (1.00, (255, 208, 122))]

SUN = (436, 466, 152)                   # x, y, radius


def ramp(stops, t):
    for i in range(len(stops) - 1):
        a, ca = stops[i]
        b, cb = stops[i + 1]
        if t <= b:
            return mix(ca, cb, (t - a) / (b - a) if b > a else 0)
    return stops[-1][1]


def sky(img):
    """Bands, then the sun's glow added on top so that it burns out to
    white near the disc instead of merely being a paler orange. A 1985
    cover was four-colour on card and the ramps were screened; the airbrush
    haze is the only part of this that a printer of the day would have
    found expensive."""
    d = ImageDraw.Draw(img)
    top = HORIZON * SS
    for y in range(top):
        d.line([(0, y), (AW * SS, y)], fill=ramp(SKY, y / top))

    sx, sy, sr = (v * SS for v in SUN)
    glow = Image.new('RGB', img.size, (0, 0, 0))
    gd = ImageDraw.Draw(glow)
    for i in range(48, 0, -1):
        r = sr * (1 + i * 0.105)
        v = 92 * (1 - i / 48.0) ** 2.0
        gd.ellipse([sx - r, sy - r * 0.84, sx + r, sy + r * 0.84],
                   fill=(int(v), int(v * 0.70), int(v * 0.26)))
    glow = glow.filter(ImageFilter.GaussianBlur(14 * SS))
    img.paste(ImageChops.add(img, glow), (0, 0))


def sun_disc(pen):
    sx, sy, sr = SUN
    pen.ellipse((sx - sr, sy - sr, sx + sr, sy + sr), fill=(255, 214, 128))
    pen.ellipse((sx - sr * 0.92, sy - sr * 0.92, sx + sr * 0.92,
                 sy + sr * 0.92), fill=(255, 238, 180))
    pen.ellipse((sx - sr * 0.56, sy - sr * 0.56, sx + sr * 0.56,
                 sy + sr * 0.56), fill=(255, 253, 240))
    #  the sliced sun: bars of sky laid back over the disc, widening down
    for off, h in ((16, 6), (42, 10), (72, 14)):
        c = ramp(SKY, (sy + off) / float(HORIZON))
        pen.rect((sx - sr - 4, sy + off, sx + sr + 4, sy + off + h), fill=c)


def clouds(pen):
    """Flat streaks with a lit lower edge. A sunset cloud seen from below
    is a bar of shadow with a line of fire under it, and anything rounder
    than that reads as a flying saucer — which the first draft of this
    did."""
    rnd = random.Random(7)
    for x, y, w, h in ((402, 126, 430, 12), (-90, 196, 560, 15),
                       (700, 262, 360, 11), (232, 330, 640, 16),
                       (664, 420, 420, 13), (44, 452, 300, 11)):
        base = ramp(SKY, y / float(HORIZON))
        dark = mix(base, (56, 14, 62), 0.46)
        for k in range(3):
            ww, hh = w * (1 - k * 0.26), h * (1 - k * 0.22)
            xx = x + rnd.randrange(-40, 40) + k * w * 0.13
            yy = y - k * hh * 0.62
            pen.ellipse((xx, yy, xx + ww, yy + hh), fill=dark)
        pen.ellipse((x + w * 0.05, y + h * 0.50, x + w * 0.95, y + h * 1.04),
                    fill=light(base, 0.70))
        pen.ellipse((x + w * 0.08, y + h * 0.36, x + w * 0.92, y + h * 0.92),
                    fill=dark)


def ridges(pen):
    """Three rows of hills, each nearer one darker and flatter. The stump
    of the oak is on the far one, which is the only reason it is there."""
    for depth, (base_y, amp, col, seed) in enumerate((
            (492, 40, (104, 44, 96), 31), (530, 26, (66, 26, 74), 17),
            (562, 15, (40, 15, 52), 5))):
        rnd = random.Random(seed)
        pts, x = [(-10, AH)], -10
        while x < AW + 10:
            pts.append((x, base_y + rnd.randrange(-amp, amp + 1)))
            x += 80 + rnd.randrange(0, 80)
        pts.append((AW + 10, AH))
        pen.poly(pts, fill=col)
        if depth == 0:
            sy = base_y - 6
            pen.poly([(866, sy + 26), (872, sy - 30), (890, sy - 34),
                      (896, sy + 26)], fill=col)
            pen.poly([(872, sy - 30), (858, sy - 54), (878, sy - 38),
                      (890, sy - 34)], fill=col)


def ground(pen):
    #  A thin warm rim right on the horizon and then straight into the dark.
    pen.rect((0, HORIZON - 3, AW, HORIZON + 9), fill=(146, 58, 44))
    for y0, y1, c in ((HORIZON + 9, 634, (44, 62, 28)),
                      (634, 716, (30, 48, 22)),
                      (716, AH, (17, 31, 15))):
        pen.rect((0, y0, AW, y1), fill=c)
    rnd = random.Random(11)
    for _ in range(300):
        x = rnd.randrange(-10, AW + 10)
        y = rnd.randrange(HORIZON + 8, AH)
        t = (y - HORIZON) / float(AH - HORIZON)
        h = 6 + 26 * t
        c = mix((96, 124, 44), (10, 22, 10), t * 0.85)
        pen.line([(x, y), (x + rnd.randrange(-7, 8), y - h)], fill=c,
                 width=1 + 2 * t)



# ---------------------------------------------------------------------------
#  THE CAST. Nine creatures exist in the game — six birds by plumage and
#  three pigs by headgear — and the sleeve uses the red bird, the king and
#  the one in the helmet, which is the usual arrangement: the hero, the
#  boss, and somebody to hit on the way past.
# ---------------------------------------------------------------------------
def rim(pen, box, a0, a1, col, w):
    pen.arc(box, a0, a1, fill=col, width=w)


def bird(pen, cx, cy, r, body=RED, belly=PALEY, mood='furious', face=1):
    o = max(2.0, r * 0.085)
    dk, lt = shade(body, 0.45), light(body, 0.45)

    #  tail, behind
    for k, (dy, sp) in enumerate(((-0.42, 1.55), (0.02, 1.70), (0.44, 1.52))):
        pen.poly([(cx - face * r * 0.70, cy + r * (dy - 0.22)),
                  (cx - face * r * sp, cy + r * (dy - 0.30 - k * 0.04)),
                  (cx - face * r * 0.70, cy + r * (dy + 0.24))],
                 fill=dk, outline=INK, width=o * 0.8)
    #  crest
    for k, (dx, dy, sp) in enumerate(((-0.30, -0.80, 0.55), (0.02, -0.92, 0.66),
                                      (0.32, -0.80, 0.52))):
        pen.poly([(cx + face * r * (dx - 0.16), cy + r * dy),
                  (cx + face * r * (dx - 0.04), cy + r * (dy - sp)),
                  (cx + face * r * (dx + 0.20), cy + r * (dy + 0.06))],
                 fill=dk, outline=INK, width=o * 0.8)

    pen.ellipse((cx - r, cy - r * 0.95, cx + r, cy + r * 0.95),
                fill=body, outline=INK, width=o)
    pen.ellipse((cx - r * 0.52, cy + r * 0.04, cx + r * 0.58, cy + r * 0.88),
                fill=belly)
    #  the sun is to the right of the sling, so the light is on that edge
    rim(pen, (cx - r * 0.97, cy - r * 0.92, cx + r * 0.97, cy + r * 0.92),
        -66, 58, lt, o * 0.9)

    ex, ey, er = cx + face * r * 0.30, cy - r * 0.26, r * 0.25
    for s in (-1, 1):
        x = ex + face * s * r * 0.22 + face * r * 0.10
        pen.ellipse((x - er, ey - er, x + er, ey + er), fill=WHITE,
                    outline=INK, width=o * 0.7)
        if mood == 'flying':
            pen.line([(x - er * 0.8, ey), (x + er * 0.8, ey)], fill=INK,
                     width=o * 0.9)
        else:
            p = er * 0.44
            px = x + face * er * (0.30 if mood == 'furious' else 0.0)
            pen.ellipse((px - p, ey - p * 0.2, px + p, ey + p * 1.8), fill=INK)
    if mood != 'flying':                    # the brows. The whole character.
        for s in (-1, 1):
            x = ex + face * s * r * 0.22 + face * r * 0.10
            pen.poly([(x - er * 1.25, ey - er * 1.30),
                      (x + er * 1.25, ey - er * (2.10 if s < 0 else 0.80)),
                      (x + er * 1.25, ey - er * (1.40 if s < 0 else 0.10)),
                      (x - er * 1.25, ey - er * 0.60)], fill=INK)

    by = cy + r * 0.08
    pen.poly([(cx + face * r * 0.58, by - r * 0.26),
              (cx + face * r * 1.34, by + r * 0.04),
              (cx + face * r * 0.58, by + r * 0.16)],
             fill=YELLOW, outline=INK, width=o * 0.8)
    pen.poly([(cx + face * r * 0.58, by + r * 0.16),
              (cx + face * r * 1.14, by + r * 0.13),
              (cx + face * r * 0.58, by + r * 0.46)],
             fill=shade(YELLOW, 0.32), outline=INK, width=o * 0.8)


def pig(pen, cx, cy, r, gear=None, face=1):
    o = max(2.0, r * 0.095)
    dk = shade(GREEN, 0.40)
    for s in (-1, 1):                       # ears
        pen.poly([(cx + s * r * 0.62, cy - r * 0.58),
                  (cx + s * r * 0.98, cy - r * 1.18),
                  (cx + s * r * 0.24, cy - r * 0.92)],
                 fill=dk, outline=INK, width=o)
    pen.ellipse((cx - r, cy - r * 0.94, cx + r, cy + r * 0.94),
                fill=GREEN, outline=INK, width=o)
    rim(pen, (cx - r * 0.97, cy - r * 0.92, cx + r * 0.97, cy + r * 0.92),
        -100, 20, light(GREEN, 0.5), o * 0.9)

    sw, sh = r * 0.66, r * 0.46
    sy = cy + r * 0.30
    pen.ellipse((cx - sw, sy - sh, cx + sw, sy + sh), fill=DGREEN,
                outline=INK, width=o)
    for s in (-1, 1):
        pen.ellipse((cx + s * sw * 0.44 - sw * 0.16, sy - sh * 0.42,
                     cx + s * sw * 0.44 + sw * 0.16, sy + sh * 0.42), fill=INK)

    er = r * 0.23
    for s in (-1, 1):
        x, y = cx + s * r * 0.44, cy - r * 0.34
        pen.ellipse((x - er, y - er, x + er, y + er), fill=WHITE,
                    outline=INK, width=o * 0.7)
        p = er * 0.42
        pen.ellipse((x + face * p * 0.5 - p, y - p, x + face * p * 0.5 + p,
                     y + p), fill=INK)
        #  a smug little arch, not a scowl: they think they have won
        pen.arc((x - er * 1.3, y - er * 2.2, x + er * 1.3, y + er * 0.2),
                200, 340, fill=INK, width=o * 0.8)

    if gear == 'crown':
        w, h = r * 0.92, r * 0.52
        top, base = cy - r * 1.28, cy - r * 0.76
        pts = [(cx - w, base), (cx - w, top + h * 0.22),
               (cx - w * 0.5, top + h * 0.62), (cx - w * 0.02, top),
               (cx + w * 0.46, top + h * 0.62), (cx + w, top + h * 0.22),
               (cx + w, base)]
        pen.poly(pts, fill=YELLOW, outline=INK, width=o)
        pen.rect((cx - w, base - h * 0.22, cx + w, base), fill=ORANGE,
                 outline=INK, width=o * 0.8)
        for s in (-1, 0, 1):
            pen.ellipse((cx + s * w * 0.62 - r * 0.09, base - h * 0.19,
                         cx + s * w * 0.62 + r * 0.09, base - h * 0.01),
                        fill=RED)
    elif gear == 'helmet':
        pen.poly([(cx - r * 1.06, cy - r * 0.28), (cx - r * 0.92, cy - r * 0.96),
                  (cx, cy - r * 1.30), (cx + r * 0.92, cy - r * 0.96),
                  (cx + r * 1.06, cy - r * 0.28), (cx + r * 0.72, cy - r * 0.34),
                  (cx, cy - r * 0.52), (cx - r * 0.72, cy - r * 0.34)],
                 fill=GREY, outline=INK, width=o)
        pen.rect((cx - r * 0.09, cy - r * 1.24, cx + r * 0.09, cy + r * 0.12),
                 fill=light(GREY, 0.25), outline=INK, width=o * 0.7)


# ---------------------------------------------------------------------------
#  THE FORT. Built out of the pieces the game actually has — stone footing,
#  uprights, floors, a crate, a charge, a rope across the top — because the
#  cover promising a thing the game does not contain is a 1985 tradition
#  this one can do without.
# ---------------------------------------------------------------------------
def sprite(w, h, fn, angle=0.0):
    im = Image.new('RGBA', (int(w * SS), int(h * SS)), (0, 0, 0, 0))
    fn(Pen(im))
    if angle:
        im = im.rotate(angle, resample=Image.BICUBIC, expand=True)
    return im


def stamp(img, im, cx, cy):
    img.alpha_composite(im, (int(cx * SS - im.width / 2),
                             int(cy * SS - im.height / 2)))


def plank(pen, x, y, w, h, col=ORANGE, grain=True):
    o = max(2.0, min(w, h) * 0.09)
    pen.rect((x, y, x + w, y + h), fill=col, outline=INK, width=o)
    pen.rect((x + o, y + o, x + w - o, y + o + max(2, h * 0.14)),
             fill=light(col, 0.40))
    pen.rect((x + o, y + h - o - max(2, h * 0.16), x + w - o, y + h - o),
             fill=shade(col, 0.38))
    if grain and w > h:
        for k in (0.40, 0.66):
            pen.line([(x + w * 0.12, y + h * k), (x + w * 0.88, y + h * k)],
                     fill=shade(col, 0.26), width=max(1, h * 0.05))
    elif grain:
        for k in (0.36, 0.64):
            pen.line([(x + w * k, y + h * 0.10), (x + w * k, y + h * 0.90)],
                     fill=shade(col, 0.26), width=max(1, w * 0.05))


def stone(pen, x, y, w, h):
    plank(pen, x, y, w, h, GREY, grain=False)
    rnd = random.Random(int(x))
    for _ in range(3):                      # a course line or two
        yy = y + rnd.uniform(0.25, 0.8) * h
        pen.line([(x + 4, yy), (x + w - 4, yy)], fill=shade(GREY, 0.45),
                 width=max(1, h * 0.05))


C = 44                                      # one game cell, on the sleeve
FX, FY = 636, GROUND                        # the fort's bottom left


def cell(col, row):
    return FX + col * C, FY - (row + 1) * C


def fort(pen):
    for c in (0, 2, 4, 6):                                  # stone footing
        x, y = cell(c, 0)
        stone(pen, x, y, C * 2, C)

    x, y = cell(0, 1)                                       # ground floor
    plank(pen, x, y, C * 0.9, C)
    plank(pen, *cell(1, 1), C * 0.9, C)
    plank(pen, *cell(5, 1), C * 0.9, C)
    x, y = cell(6, 1)                                       # the charge
    pen.rect((x + 4, y + 6, x + C * 1.7, y + C - 2), fill=RED, outline=INK,
             width=4)
    pen.rect((x + 4, y + 6, x + C * 1.7, y + 16), fill=shade(RED, 0.35))
    pen.line([(x + C * 0.85, y + 6), (x + C * 1.05, y - 14),
              (x + C * 0.74, y - 26)], fill=(226, 214, 184), width=5)
    pen.poly([(x + C * 0.74, y - 22), (x + C * 0.60, y - 44),
              (x + C * 0.80, y - 38), (x + C * 0.92, y - 58),
              (x + C * 0.96, y - 30)], fill=YELLOW, outline=ORANGE, width=3)

    for c in (0, 4):                                        # first floor
        x, y = cell(c, 2)
        plank(pen, x, y + C * 0.30, C * 4, C * 0.62)

    plank(pen, *cell(0, 3), C * 0.9, C)                     # first storey
    x, y = cell(1, 3)
    plank(pen, x, y + C * 0.22, C * 1.7, C * 0.74, grain=False)   # crate
    pen.rect((x + C * 0.2, y + C * 0.42, x + C * 1.5, y + C * 0.78),
             fill=shade(ORANGE, 0.5))
    plank(pen, *cell(3, 3), C * 0.9, C)
    plank(pen, *cell(6, 3), C * 0.9, C)
    x, y = cell(7, 3)                                       # a pane of glass
    pen.rect((x, y, x + C * 0.9, y + C), fill=(150, 235, 245), outline=INK,
             width=3)
    pen.line([(x + 6, y + C - 8), (x + C * 0.8, y + 8)], fill=WHITE, width=5)

    for c in (0, 4):                                        # second floor
        x, y = cell(c, 4)
        plank(pen, x, y + C * 0.30, C * 4, C * 0.62)

    #  a dark recess behind the ground-floor opening, so the pig in it
    #  reads as inside the fort rather than stuck on the front
    x, y = cell(2, 1)
    pen.rect((x - 6, y - 4, x + C * 2.95, y + C), fill=(34, 20, 26))

    for c in (0, 1, 6, 7):                                  # top storey
        plank(pen, cell(c, 5)[0] + C * 0.05, 441, C * 0.85, 44)

    for c in (0, 7):                                        # the two masts
        plank(pen, cell(c, 5)[0] + C * 0.16, 270, C * 0.62, 176)

    lx, rx, ty = 655, 963, 282                              # the rope walk
    pts = [(lx + t * (rx - lx) / 18.0,
            ty + 40 * math.sin(math.pi * t / 18.0)) for t in range(19)]
    pen.line([(x, y + 5) for x, y in pts], fill=(112, 82, 44), width=10)
    pen.line(pts, fill=(230, 210, 156), width=7)

    pen.poly([(640, 441), (812, 353), (984, 441)], fill=ORANGE, outline=INK,
             width=5)                                       # the roof
    pen.poly([(640, 441), (812, 353), (812, 397)],
             fill=light(ORANGE, 0.38))
    for k in range(1, 5):                                   # rafters
        pen.line([(812, 353 + k * 15), (648 + k * 32, 441)],
                 fill=shade(ORANGE, 0.30), width=3)
        pen.line([(812, 353 + k * 15), (976 - k * 32, 441)],
                 fill=shade(ORANGE, 0.20), width=3)



#  The fork and the bands, which took three goes. What was wrong the first
#  two times: the bands were the same brown as the wood and ran nearly
#  parallel to the left limb, so the eye read them as a third branch. They
#  are a different colour and a different direction now, and the pouch is
#  far enough back that both bands diverge from the limb they leave.
WOOD = (76, 42, 28)
TIP_L, TIP_R = (386, 466), (588, 458)
POUCH = (198, 642)


def sling(pen):
    """The last fork of the oak, still standing where the trunk used to be.
    It stands in front of the sun on purpose: a fork against a sunset is
    the whole poster."""
    pen.poly([(444, 836), (438, 694), (524, 690), (532, 836)], fill=WOOD,
             outline=INK, width=5)
    pen.poly([(440, 714), (364, 480), (408, 450), (502, 692)], fill=WOOD,
             outline=INK, width=5)
    pen.poly([(464, 700), (566, 444), (610, 474), (518, 716)], fill=WOOD,
             outline=INK, width=5)
    for a, b in (((462, 810), (466, 712)), ((500, 816), (504, 716)),
                 ((404, 630), (424, 530)), ((556, 620), (578, 526))):
        pen.line([a, b], fill=shade(WOOD, 0.45), width=7)
    pen.line([(518, 712), (602, 472)], fill=(208, 144, 82), width=9)
    pen.line([(526, 820), (524, 696)], fill=(186, 124, 72), width=8)
    pen.line([(404, 456), (444, 706)], fill=(152, 98, 60), width=6)


def bands(pen):
    """Two straight runs from the fork tips to the pouch, because a
    stretched band IS straight. Rubber, not timber: grey-plum, so it does
    not disappear into the fork it is tied to."""
    for tip, end in ((TIP_L, (202, 624)), (TIP_R, (202, 660))):
        pen.line([tip, end], fill=(16, 12, 16), width=19)
        pen.line([tip, end], fill=(86, 66, 80), width=11)
        pen.line([(tip[0] - 1, tip[1] - 4), (end[0] - 1, end[1] - 4)],
                 fill=(172, 150, 168), width=3)
    pen.poly([(144, 592), (214, 612), (216, 678), (142, 694)],
             fill=(48, 32, 28), outline=INK, width=4)
    pen.line([(156, 608), (200, 624)], fill=(104, 72, 58), width=5)


def bezier(p0, c, p1, t):
    u = 1 - t
    return (u * u * p0[0] + 2 * u * t * c[0] + t * t * p1[0],
            u * u * p0[1] + 2 * u * t * c[1] + t * t * p1[1])


def trajectory(pen, p0, c, p1, n=26):
    for i in range(n + 1):
        t = i / float(n)
        x, y = bezier(p0, c, p1, t)
        r = 3.0 + 6.0 * (1 - abs(t - 0.5) * 2) ** 0.7
        pen.ellipse((x - r - 1.6, y - r - 1.6, x + r + 1.6, y + r + 1.6),
                    fill=(120, 40, 30))
        pen.ellipse((x - r, y - r, x + r, y + r), fill=(255, 226, 150))


def burst(pen, cx, cy, r):
    pts = []
    for i in range(20):
        a = math.pi * 2 * i / 20.0
        k = r * (1.0 if i % 2 == 0 else 0.46)
        pts.append((cx + math.cos(a) * k, cy + math.sin(a) * k * 0.92))
    pen.poly(pts, fill=(255, 160, 40), outline=INK, width=5)
    pts = [(cx + (x - cx) * 0.62, cy + (y - cy) * 0.62) for x, y in pts]
    pen.poly(pts, fill=(255, 246, 206))


# ---------------------------------------------------------------------------
def paint_art():
    img = Image.new('RGBA', (AW * SS, AH * SS), (0, 0, 0, 255))
    base = Image.new('RGB', img.size, (0, 0, 0))
    sky(base)
    p = Pen(base)
    sun_disc(p)
    clouds(p)
    ridges(p)
    ground(p)
    img.paste(base, (0, 0))

    p = Pen(img)
    trajectory(p, (330, 618), (520, 108), (698, 362))
    fort(p)

    #  the pigs, in their usual arrangement: one on the roof with the crown,
    #  one at a window, one outside who has not looked up yet
    stamp(img, sprite(140, 140, lambda q: pig(q, 70, 74, 40, 'crown')),
          890, 356)
    stamp(img, sprite(110, 110, lambda q: pig(q, 55, 58, 30, 'helmet')),
          786, 620)
    stamp(img, sprite(130, 130, lambda q: pig(q, 65, 68, 38, None, face=-1)),
          1034, 654)

    burst(Pen(img), 692, 372, 86)
    #  ...and one that has looked up, on its way off the roof
    stamp(img, sprite(110, 110, lambda q: pig(q, 55, 58, 30, None), 38),
          748, 214)
    for (x, y, w, h, a) in ((622, 286, 96, 26, 28), (700, 232, 74, 22, -42),
                            (760, 296, 110, 24, 62), (598, 404, 66, 22, -14),
                            (822, 240, 80, 22, 18)):
        stamp(img, sprite(w + 14, h + 14,
                          lambda q, w=w, h=h: plank(q, 7, 7, w, h), a), x, y)

    for k in (1, 2, 3):                     # speed lines back down the arc
        Pen(img).line([(452 - k * 26, 356 + k * 24),
                       (496 - k * 26, 322 + k * 22)],
                      fill=(255, 228, 178), width=9 - k * 2)
    stamp(img, sprite(150, 150,
                      lambda q: bird(q, 75, 78, 46, mood='flying'), -18),
          524, 296)

    p = Pen(img)
    sling(p)
    bands(p)
    stamp(img, sprite(280, 280, lambda q: bird(q, 140, 142, 80)), 232, 642)

    stamp(img, sprite(160, 160,
                      lambda q: bird(q, 80, 82, 44, fw(24), PALEY, 'waiting')),
          88, 742)
    stamp(img, sprite(130, 130,
                      lambda q: bird(q, 65, 67, 34, WHITE, PALEY, 'waiting')),
          182, 786)

    #  grade: one warm wash over everything, which is what makes a picture
    #  assembled out of flat fills look like it was lit
    wash = Image.new('RGB', img.size, (0, 0, 0))
    wd = ImageDraw.Draw(wash)
    for y in range(img.height):
        t = y / float(img.height)
        wd.line([(0, y), (img.width, y)],
                fill=mix((70, 26, 52), (128, 52, 18), t))
    rgb = Image.composite(ImageChops.screen(img.convert('RGB'), wash),
                          img.convert('RGB'),
                          Image.new('L', img.size, 40))

    vig = Image.new('L', img.size, 0)
    vd = ImageDraw.Draw(vig)
    m = int(min(img.size) * 0.16)
    vd.ellipse([-m, -m, img.width + m, img.height + m], fill=255)
    vig = vig.filter(ImageFilter.GaussianBlur(m * 0.5))
    return Image.composite(rgb, Image.eval(rgb, lambda v: int(v * 0.68)), vig)


# ---------------------------------------------------------------------------
#  THE LOGOTYPE. Heavy caps, sheared right, a hard extrude down-right and a
#  gradient face with a flat highlight across the top third. No blur
#  anywhere: a drop shadow with a soft edge is a 1995 idea.
# ---------------------------------------------------------------------------
def caps_mask(s, target_w, tracking=0.02):
    px = 200
    f = font(F_TITLE, px)
    d = ImageDraw.Draw(Image.new('L', (1, 1)))
    tr = px * SS * tracking
    w = int(sum(d.textlength(c, font=f) + tr for c in s))
    h = int(px * SS * 1.5)
    m = Image.new('L', (w + int(h * 0.20) + 60, h), 0)
    md = ImageDraw.Draw(m)
    x = 30
    for ch in s:
        md.text((x, h * 0.62), ch, font=f, fill=255, anchor='ls')
        x += d.textlength(ch, font=f) + tr
    m = m.transform(m.size, Image.AFFINE, (1, 0.20, -0.20 * h, 0, 1, 0),
                    resample=Image.BICUBIC)
    m = m.crop(m.getbbox())
    tw = int(target_w * SS)
    return m.resize((tw, max(1, int(m.height * tw / m.width))),
                    Image.LANCZOS)


TITLE_FACE = [(0.00, (255, 255, 214)), (0.34, (255, 232, 60)),
              (0.46, (255, 236, 120)), (0.50, (255, 176, 20)),
              (0.76, (246, 104, 16)), (1.00, (198, 16, 22))]


def logotype(img, s, cx, top, target_w):
    m = caps_mask(s, target_w)
    w, h = m.size
    depth = max(3, int(h * 0.085))
    x0, y0 = int(cx * SS - w / 2), int(top * SS)

    key = m.filter(ImageFilter.MaxFilter(2 * int(h * 0.035) + 1))
    for dx, dy in ((0, 0), (depth, depth)):
        img.paste(INK, (x0 + dx, y0 + dy), key)
    for i in range(depth, 0, -1):
        img.paste(mix((150, 14, 26), (74, 6, 18), i / float(depth)),
                  (x0 + i, y0 + i), m)

    face = Image.new('RGB', (w, h))
    fd = ImageDraw.Draw(face)
    for y in range(h):
        fd.line([(0, y), (w, y)], fill=ramp(TITLE_FACE, y / float(h)))
    img.paste(face, (x0, y0), m)
    return h / float(SS)


def fits(s, path, size, w, spacing=0, where=''):
    """Raise rather than overflow. Pillow will happily draw a line straight
    off the edge of the panel and the only sign is in the proof, which is
    exactly the kind of thing you stop noticing on the fortieth render."""
    got = text_w(s, path, size, spacing)
    if got > w:
        raise SystemExit('mkcover: %s overflows by %.0f px: %r'
                         % (where or 'text', got - w, s))
    return s


def paragraph(img, x, y, w, body, path, size, fill, leading, spacing=0):
    """Word-wrapped, ragged right. Blank lines separate paragraphs. Never
    justified: 1985 back-cover blurb was set ragged in a single column, and
    justifying a narrow measure opens rivers you cannot close."""
    for block in body.split('\n\n'):
        line = ''
        for word in block.split():
            trial = (line + ' ' + word).strip()
            if line and text_w(trial, path, size, spacing) > w:
                text(img, (x, y), line, path, size, fill, spacing=spacing)
                y += leading
                line = word
            else:
                line = trial
        if line:
            text(img, (x, y), line, path, size, fill, spacing=spacing)
            y += leading
        y += leading * 0.55
    return y - leading * 0.55


def title_block(img, cx, top, target_w, gap=6):
    """The two stacked lines of the logotype. Returns the y it ends at, so
    whatever comes next stacks off the type rather than off a constant that
    stops being true the moment the width changes."""
    h = logotype(img, 'FOWL AND', cx, top, target_w)
    h2 = logotype(img, 'FURIOUS', cx, top + h + gap, target_w)
    return top + h + gap + h2


def flash_bar(pen, w, h=26):
    """The colour flash across the top. It runs unbroken across all three
    panels of the inlay, which is the one thing that makes a wrap read as
    one printed sheet rather than three pictures side by side."""
    bw = w / float(len(FLASH))
    for i, c in enumerate(FLASH):
        pen.rect((i * bw, 0, (i + 1) * bw + 1, h), fill=c)


def foot(img, pen, w, left, right, y=1532):
    pen.rect((50, y, w - 50, y + 2), fill=(70, 64, 78))
    text(img, (50, y + 16), left, F_NARROW, 20, (152, 146, 160), spacing=3)
    text(img, (w - 50, y + 16), right, F_NARROW, 20, (152, 146, 160),
         anchor='ra', spacing=3)


#  cpcshot.py writes every Mode 0 pixel 4 output pixels wide and every
#  scanline twice, so its PNG is already at the 2:1 pixel aspect a real
#  machine shows — do not "correct" it to square pixels or every sprite
#  comes out tall and thin. Half of 688 x 448 is exact, which undoes that
#  doubling and nothing else: the result is pixel-for-pixel what the CRTC
#  put out. NEAREST, obviously — a smoothly resampled screenshot is the
#  loudest possible modern tell on an otherwise period sleeve.
SHOT_W, SHOT_H = 344, 224               # 688 x 448, halved exactly


def shot_box(img, pen, path, x, y, caption):
    """One screenshot in a keyline box with a caption under it. These are
    REAL frames off the headless emulator in tools/cpcshot.py, not mock-ups
    or a better machine's graphics — which in 1985 was very much not the
    convention."""
    im = Image.open(path).convert('RGB')
    pen.rect((x - 3, y - 3, x + SHOT_W + 3, y + SHOT_H + 3),
             fill=(236, 230, 220))
    img.paste(im.resize((SHOT_W * SS, SHOT_H * SS), Image.NEAREST),
              (int(x * SS), int(y * SS)))
    text(img, (x + SHOT_W / 2.0, y + SHOT_H + 12), caption, F_NARROW, 15,
         (170, 164, 178), anchor='ma', spacing=1)
    return SHOT_H + 36


def starburst(pen, cx, cy, r, points, fill, outline=INK, wobble=0.56):
    pts = []
    for i in range(points * 2):
        a = math.pi * 2 * i / (points * 2.0) - math.pi / 2
        k = r if i % 2 == 0 else r * wobble
        pts.append((cx + math.cos(a) * k, cy + math.sin(a) * k))
    pen.poly(pts, fill=fill, outline=outline, width=3)


# ---------------------------------------------------------------------------
#  PANELS. Each one renders into its OWN image at its own natural size and is
#  pasted into the wrap afterwards. The alternative — threading an origin
#  through every drawing call — would mean touching text(), logotype(),
#  sky(), paint_art()'s wash and vignette, and every absolute coordinate in
#  here. A paste is one line and cannot be got subtly wrong.
def build_front():
    img = Image.new('RGB', (W * SS, H * SS), INK)
    p = Pen(img)

    flash_bar(p, W)

    text(img, (W / 2, 42), 'REVIVE8BIT PRESENTS', F_NARROW, 21,
         (198, 192, 206), anchor='ma', spacing=6)

    title_block(img, W / 2, 74, 942)

    text(img, (W / 2, 398), 'THEY TOOK THE TREE.   TAKE IT BACK.', F_NARROW,
         26, (244, 192, 98), anchor='ma', spacing=4)

    # ---- the picture, in a keyline box -------------------------------------
    fx0, fy0 = 50, 448
    p.rect((fx0 - 5, fy0 - 5, fx0 + AW + 5, fy0 + AH + 5),
           fill=(236, 230, 220))
    img.paste(paint_art(), (fx0 * SS, fy0 * SS))

    # ---- the format banner -------------------------------------------------
    p.rect((0, 1316, W, 1320), fill=(255, 214, 60))
    p.rect((0, 1320, W, 1382), fill=(206, 22, 30))
    text(img, (W / 2, 1338), 'AMSTRAD CPC 464  ·  6128', F_NARROW, 31,
         WHITE, anchor='ma', spacing=7)

    # ---- the furniture -----------------------------------------------------
    p.rect((50, 1408, 430, 1492), fill=(236, 230, 220))
    text(img, (240, 1420), 'REVIVE8BIT', F_TITLE, 44, INK, anchor='ma',
         spacing=1)
    text(img, (240, 1462), '2026  ·  VASPER', F_NARROW, 19, (86, 80, 92),
         anchor='ma', spacing=5)

    for i, line in enumerate(('FIFTY FORTS', 'ONE SLINGSHOT',
                              'NO SURVIVORS')):
        text(img, (470, 1410 + i * 30), line, F_NARROW, 24, (244, 192, 98),
             spacing=2)

    #  a 3" disc: a hard shell with a shutter, not the vinyl record the
    #  first draft drew
    p.rect((776, 1400, 890, 1494), fill=(46, 44, 54), outline=(112, 108, 122),
           width=2)
    p.rect((784, 1408, 882, 1454), fill=(236, 230, 220))
    p.rect((784, 1462, 824, 1486), fill=(168, 168, 176))
    p.ellipse((846, 1462, 874, 1486), fill=(24, 22, 30))
    text(img, (833, 1504), '3 INCH DISC', F_NARROW, 17, (236, 230, 220),
         anchor='ma', spacing=3)

    starburst(p, 1058, 1446, 92, 11, (255, 210, 40))
    text(img, (1058, 1414), '100%', F_TITLE, 34, INK, anchor='ma')
    text(img, (1058, 1452), 'MACHINE', F_NARROW, 19, INK, anchor='ma',
         spacing=2)
    text(img, (1058, 1470), 'CODE', F_NARROW, 19, INK, anchor='ma',
         spacing=2)

    foot(img, p, W, 'LOAD WITH   RUN"FOWLS', 'MADE IN GREECE')

    return img


# ---------------------------------------------------------------------------
#  THE BACK. Everything on it was checked against the source before it was
#  set: a workflow wrote the copy with file:line evidence for each claim and
#  a second agent tried to refute every one of them. What it threw out is in
#  the commit message. 1985 back covers were works of fiction; this one is
#  not, which is the joke.
# ---------------------------------------------------------------------------
#  Real frames, off the headless emulator in tools/cpcshot.py, captured with
#  the key sequences recorded in the commit. Three, not four: four screens
#  was the 1987 habit and two the 1985 one, and three in a row is what fits.
SHOTS = [
    ('docs/shot-sling.png', 'FORT ONE.  THE SLING AT FULL DRAW.'),
    ('docs/shot-flight.png', 'FORT 46.  EIGHT PIGS, AND A BIRD IN THE AIR.'),
    ('docs/shot-desert.png', 'FORT 37.  ONE OF THE SIX SKIES.'),
]

BLURB = """The birds had a tree. The pigs had a field, a saw, and one whole
night while the choir slept. By morning there were fifty forts on the ridge,
with a pig inside each one looking pleased.

You have the last fork of the trunk, a length of elastic, and a queue of
birds. You are not demolishing anything. You are taking the timber back, one
plank at a time, and it has to land on somebody.

Nothing is scored for the wreckage. The score is what the wreckage lands on
— or the bird, if it gets there first — plus a hundred for every bird you
did not need."""

BULLETS = [
    'FIFTY FORTS, AND THE LAST ARE THE BIGGEST',
    'SIXTEEN PIECES, PLANK TO DYNAMITE',
    'SIX BIRDS, THREE PIGS, FIFTY-FOUR FRAMES DRAWN',
    'SCORED ON HOW HARD THE PIGS WERE HIT',
    'NOTHING IS DELETED — IT IS KNOCKED OVER',
    'A 320-PIXEL WORLD, PANNED BY THE CRTC ITSELF',
    'SWAP SIDES AND THROW PIGS AT BIRDS INSTEAD',
    'HIGH SCORE WRITTEN BACK TO THE DISC',
    'TWO HUNDRED AND FORTY-THREE PIGS IN ALL',
    'EASY, MEDIUM OR HARD: FIVE, THREE, TWO GOES',
]

SPECS = [
    ('MACHINE', 'AMSTRAD CPC 464 / 6128'),
    ('MEMORY', '64K. NO EXPANSION NEEDED'),
    ('MEDIA', '3in DISC, ONE SIDE'),
    ('DISPLAY', 'MODE 0 — 160x200 — 16 COLOURS'),
    ('SOUND', 'AY-3-8912, THREE VOICES'),
    ('CONTROL', 'KEYBOARD: CURSORS, SPACE, ESC'),
    ('PLAYERS', 'ONE'),
]


def build_back():
    img = Image.new('RGB', (W * SS, H * SS), INK)
    p = Pen(img)
    flash_bar(p, W)

    logotype(img, 'FOWL AND FURIOUS', W / 2, 52, 1000)
    text(img, (W / 2, 148), 'THEY TOOK THE TREE.   TAKE IT BACK.', F_NARROW,
         24, (244, 192, 98), anchor='ma', spacing=4)

    #  Two screenshots, not four. Four was the 1987 habit; in 1985 two large
    #  ones was the norm, and two leaves the copy room to breathe.
    gap = 30
    x0 = (W - (len(SHOTS) * SHOT_W + (len(SHOTS) - 1) * gap)) / 2.0
    for i, (path, cap) in enumerate(SHOTS):
        fits(cap, F_NARROW, 15, SHOT_W, 1, 'caption %d' % i)
        shot_box(img, p, path, x0 + i * (SHOT_W + gap), 196, cap)

    y = paragraph(img, 66, 520, 1068, BLURB, F_TEXT, 24, (222, 218, 228), 36)

    y += 34
    for i, b in enumerate(BULLETS):
        bx = 66 + (i % 2) * 552
        by = y + (i // 2) * 38
        fits(b, F_NARROW, 21, 512, 1, 'bullet %d' % i)
        p.rect((bx, by + 7, bx + 11, by + 18), fill=(214, 26, 32))
        text(img, (bx + 24, by), b, F_NARROW, 21, (236, 232, 240), spacing=1)

    #  A light slab for the technical block, the publisher and the legal
    #  line. Small reversed-out type fills in when four-colour work goes half
    #  a millimetre out of register, so the small print here is dark on light.
    y = 1058
    p.rect((50, y, W - 50, 1482), fill=(236, 230, 220))

    text(img, (74, y + 22), 'SPECIFICATION', F_TITLE, 20, (176, 32, 24),
         spacing=2)
    for i, (k, v) in enumerate(SPECS):
        yy = y + 60 + i * 30
        text(img, (74, yy), k, F_NARROW, 19, (120, 114, 128), spacing=2)
        text(img, (250, yy), fits(v, F_BOLD, 19, 352, 0, 'spec ' + k),
             F_BOLD, 19, (36, 32, 42))

    text(img, (628, y + 22), 'LOADING', F_TITLE, 20, (176, 32, 24),
         spacing=2)
    text(img, (628, y + 58), 'Insert the disc, label side up.', F_TEXT, 20,
         (36, 32, 42))
    text(img, (628, y + 88), 'Type', F_TEXT, 20, (36, 32, 42))
    text(img, (688, y + 86), 'RUN"FOWLS', F_BOLD, 21, (176, 32, 24))
    text(img, (826, y + 88), 'and press ENTER.', F_TEXT, 20, (36, 32, 42))
    paragraph(img, 628, y + 128, 476,
              'The game writes your high score back to the disc, so leave '
              'the write-protect tab shut.', F_TEXT, 20, (36, 32, 42), 28)

    p.rect((74, y + 292, W - 74, y + 294), fill=(206, 200, 192))
    text(img, (74, y + 316), 'REVIVE8BIT', F_TITLE, 32, (36, 32, 42),
         spacing=1)
    text(img, (74, y + 358), 'VASPER  ·  2026  ·  R8B-DISC-001', F_NARROW,
         18, (110, 104, 118), spacing=3)
    paragraph(img, 628, y + 314, 476,
              'All rights reserved. Unauthorised copying, hiring, lending or '
              'public performance of this program is prohibited.',
              F_TEXT, 15, (110, 104, 118), 21)

    foot(img, p, W, 'WRITTEN IN Z80 ASSEMBLY', 'NOT ONE BYTE TO SPARE')
    return img


def build_spine():
    """Drawn LANDSCAPE and rotated clockwise, because there is no rotated-text
    path anywhere in here and adding one to draw four words would be silly.

    Clockwise, not anticlockwise: the British convention — shared with books
    and video sleeves — is that a spine reads TOP TO BOTTOM when the case
    stands upright. Rotating clockwise maps the landscape strip's left end
    to the spine's top, so ordinary left-to-right text comes out reading
    downwards, and the publisher wordmark at the right end lands at the
    bottom, at eye level in a rack. The check that needs no convention: lay
    the folded case flat with the FRONT UP and the spine on the left, and the
    spine should be readable without moving your head.

    The ground is the same INK as both panels, on purpose. A spine in a
    different colour puts a hard edge exactly on a crease, and a crease is
    placed to about a millimetre by hand — one slip and there is a coloured
    sliver on the front cover that reads as a printing fault."""
    strip = Image.new('RGB', (H * SS, SPINE * SS), INK)
    p = Pen(strip)

    #  rules just inside each fold, so the spine has edges without having a
    #  colour change ON the fold
    for y in (18, SPINE - 20):
        p.rect((40, y, H - 40, y + 2), fill=(58, 52, 66))

    mark, fmt = 'REVIVE8BIT', 'AMSTRAD CPC  ·  3in DISC'
    mw = text_w(mark, F_TITLE, 30, 1)
    fw_ = text_w(fmt, F_NARROW, 23, 4)
    right = H - 56
    text(strip, (right, SPINE / 2.0), mark, F_TITLE, 30, (236, 230, 220),
         anchor='rm', spacing=1)
    text(strip, (right - mw - 46, SPINE / 2.0), fmt, F_NARROW, 23,
         (186, 180, 194), anchor='rm', spacing=4)

    #  the title takes whatever is left, capped so its cap height stays well
    #  inside the spine — type set to fill 12.7 mm gets eaten by the fold on
    #  half a print run
    avail = (right - mw - fw_ - 92) - 150
    #  and capped by HEIGHT too: cap height must stay a good 2 mm inside the
    #  spine or the fold eats it on half the run
    tw = min(avail, 940)
    h = caps_mask('FOWL AND FURIOUS', tw).height / float(SS)
    if h > SPINE * 0.52:
        tw = int(tw * SPINE * 0.52 / h)
        h = caps_mask('FOWL AND FURIOUS', tw).height / float(SS)
    logotype(strip, 'FOWL AND FURIOUS', 150 + tw / 2.0,
             (SPINE - h) / 2.0 - 4, tw)

    return strip.rotate(-90, expand=True)


# ---------------------------------------------------------------------------
#  THE WRAP. Printed flat and folded round the case, so the panels run
#  BACK | SPINE | FRONT left to right: fold it and the back ends up behind
#  the front with the spine between them. Get that order backwards and the
#  sleeve is inside out, which is the one mistake here that looks fine on
#  screen and is only discovered with scissors.
def build_wrap():
    sheet = Image.new('RGB', (SHEET_W * SS, H * SS), INK)
    sheet.paste(build_back(), (0, 0))
    sheet.paste(build_spine(), (W * SS, 0))
    sheet.paste(build_front(), ((W + SPINE) * SS, 0))

    #  The flash is redrawn ACROSS THE WHOLE SHEET, over the three panels'
    #  own copies of it. Each panel has to carry one so that it stands up
    #  alone as a PNG, but on the wrap the six bars have to be six bars
    #  across 216 mm, not three sets of six with a seam at each fold — a
    #  band that breaks at the crease is what makes a wrap read as three
    #  pictures laid side by side.
    p = Pen(sheet)
    flash_bar(p, SHEET_W)

    #  fold marks, in the trim margin at top and bottom, the way a printer
    #  would want them
    for x in (W, W + SPINE):
        p.line([(x, 0), (x, 12)], fill=(120, 116, 128), width=1)
        p.line([(x, H - 12), (x, H)], fill=(120, 116, 128), width=1)
    return sheet.resize((SHEET_W, H), Image.LANCZOS)


# ---------------------------------------------------------------------------
#  The disc label. A 3" Amstrad disc has about 70 x 50 mm of paper on it,
#  which at 300dpi is this.
# ---------------------------------------------------------------------------
LW, LH = 827, 591


def build_label():
    img = Image.new('RGB', (LW * SS, LH * SS), (236, 230, 220))
    p = Pen(img)
    flash_bar(p, LW, 20)
    p.rect((0, LH - 64, LW, LH), fill=INK)

    title_block(img, LW / 2, 54, 560, gap=17)

    bl = Image.new('RGBA', (210 * SS, 190 * SS), (0, 0, 0, 0))
    bird(Pen(bl), 116, 96, 54)
    img.paste(bl, (int(34 * SS), int(292 * SS)), bl)

    text(img, (300, 306), 'FIFTY FORTS.  ONE SLINGSHOT.', F_NARROW, 26, INK,
         spacing=2)
    text(img, (300, 344), 'AMSTRAD CPC 464 / 6128  ·  64K', F_NARROW, 22,
         (96, 90, 102), spacing=2)
    text(img, (300, 380), 'LOAD WITH   RUN"FOWLS', F_BOLD, 22, (196, 24, 32),
         spacing=1)
    text(img, (300, 420), 'SIDE A  ·  THIS DISC IS WRITTEN TO', F_NARROW, 19,
         (96, 90, 102), spacing=2)
    text(img, (300, 444), 'WHEN YOU BEAT THE HIGH SCORE', F_NARROW, 19,
         (96, 90, 102), spacing=2)

    text(img, (24, LH - 44), 'REVIVE8BIT  ·  2026  ·  VASPER', F_NARROW, 21,
         (236, 230, 220), spacing=4)
    text(img, (LW - 24, LH - 44), '100% MACHINE CODE', F_NARROW, 21,
         (255, 210, 40), anchor='ra', spacing=4)
    return img.resize((LW, LH), Image.LANCZOS)


def to_pdf(png, dst):
    from fpdf import FPDF
    im = Image.open(png)
    w_mm, h_mm = im.width / DPI * 25.4, im.height / DPI * 25.4
    pdf = FPDF(unit='mm', format=(w_mm, h_mm))
    pdf.set_auto_page_break(False)
    pdf.set_margins(0, 0, 0)
    pdf.add_page()
    pdf.image(png, 0, 0, w_mm, h_mm)
    pdf.output(dst)


def mm(px):
    return px / DPI * 25.4


def main(out='docs'):
    os.makedirs(out, exist_ok=True)

    def save(img, name):
        path = os.path.join(out, name)
        img.save(path, dpi=(DPI, DPI))
        print('%-24s %5dx%-5d  %5.1f x %5.1f mm'
              % (path, img.width, img.height, mm(img.width), mm(img.height)))
        return path

    cover = save(build_front().resize((W, H), Image.LANCZOS), 'cover.png')
    back = save(build_back().resize((W, H), Image.LANCZOS), 'back.png')
    wrap = save(build_wrap(), 'inlay.png')
    save(build_label(), 'disc-label.png')
    for src in (cover, wrap):
        to_pdf(src, src[:-4] + '.pdf')
        print('%-24s' % (src[:-4] + '.pdf'))
    print('fold at %.1f mm and %.1f mm from the left edge'
          % (mm(W), mm(W + SPINE)))


if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else 'docs')
