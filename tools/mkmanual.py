#!/usr/bin/env python3
# ============================================================================
#  mkmanual.py — manual.md / manual-el.md -> PDF
#
#      python3 tools/mkmanual.py docs/manual.md docs/manual.pdf
#      python3 tools/mkmanual.py docs/manual.md docs/manual.pdf docs/cover.png
#
#  A Markdown renderer for exactly the Markdown the two manuals use, and no
#  more: headings, paragraphs, bullets, indented code, tables, rules, with
#  **bold**, *italic* and `code` inside them. Anything else is written out
#  as it stands rather than silently swallowed, which is how you find out
#  that the manual has grown a construct the renderer never learned.
#
#  DejaVu, because it has Greek. Nothing else installed here does, and a
#  Greek manual set in a font without Greek is a page of empty boxes.
# ============================================================================
import os
import re
import sys

from fpdf import FPDF

FONTS = '/usr/share/fonts/truetype/dejavu'
PAGE_W, MARGIN = 210.0, 18.0
TEXT_W = PAGE_W - 2 * MARGIN

INK = (32, 32, 36)
HEAD = (176, 32, 24)          # the game's red
SUB = (92, 92, 100)
RULE = (208, 208, 214)
CODE_BG = (243, 243, 240)


class Manual(FPDF):
    def __init__(self, title):
        super().__init__(format='A4')
        self.title_text = title
        self.plain_pages = 0
        self.set_margins(MARGIN, MARGIN, MARGIN)
        self.set_auto_page_break(True, MARGIN + 6)
        for style, file in (('', 'DejaVuSans.ttf'),
                            ('B', 'DejaVuSans-Bold.ttf'),
                            ('I', 'DejaVuSans-Oblique.ttf')):
            self.add_font('dv', style, os.path.join(FONTS, file))
        self.add_font('dvm', '', os.path.join(FONTS, 'DejaVuSansMono.ttf'))

    def footer(self):
        if self.page_no() <= self.plain_pages:   # no folio on the sleeve
            return
        self.set_y(-14)
        self.set_font('dv', '', 8)
        self.set_text_color(*SUB)
        self.cell(0, 6, '%s   ·   %d' % (self.title_text, self.page_no()),
                  align='C')


#  ---- inline markup --------------------------------------------------------
#  **bold**, *italic*, `code` -> a list of (text, style) runs. Nested markup
#  is not supported and not used.
TOKEN = re.compile(r'\*\*(.+?)\*\*|\*(.+?)\*|`(.+?)`')


def runs(text):
    out, at = [], 0
    for m in TOKEN.finditer(text):
        if m.start() > at:
            out.append((text[at:m.start()], ''))
        if m.group(1) is not None:
            out.append((m.group(1), 'B'))
        elif m.group(2) is not None:
            out.append((m.group(2), 'I'))
        else:
            out.append((m.group(3), 'C'))
        at = m.end()
    if at < len(text):
        out.append((text[at:], ''))
    return out


def write_runs(pdf, text, size, leading):
    """Lay out inline runs by hand: fpdf's own multi_cell cannot change font
    part way through a line, and every paragraph here has bold in it."""
    pdf.set_font('dv', '', size)
    space = pdf.get_string_width(' ')
    x0 = pdf.get_x()
    avail = TEXT_W - (x0 - MARGIN)
    used = 0.0
    for text_run, style in runs(text):
        for i, word in enumerate(text_run.split(' ')):
            if not word:
                if i:                       # a real space between two runs
                    used += space
                continue
            if style == 'C':
                pdf.set_font('dvm', '', size * 0.92)
            else:
                pdf.set_font('dv', style, size)
            w = pdf.get_string_width(word)
            if used and used + space + w > avail:
                pdf.ln(leading)
                pdf.set_x(x0)
                used = 0.0
            elif used:
                pdf.cell(space, leading, ' ')
                used += space
            pdf.cell(w, leading, word)
            used += w
    pdf.ln(leading)


def para(pdf, text, size=10.0, leading=5.0, indent=0.0):
    pdf.set_text_color(*INK)
    pdf.set_x(MARGIN + indent)
    write_runs(pdf, text, size, leading)
    pdf.ln(2)


def heading(pdf, level, text):
    sizes = {1: 26.0, 2: 15.0, 3: 11.5}
    if level == 1:
        pdf.ln(4)
    else:
        pdf.ln(5)
        if pdf.get_y() > 240:               # do not strand a heading
            pdf.add_page()
    pdf.set_font('dv', 'B', sizes.get(level, 11.0))
    pdf.set_text_color(*(HEAD if level < 3 else INK))
    pdf.multi_cell(TEXT_W, sizes.get(level, 11.0) * 0.5, text)
    if level == 1:
        pdf.ln(1)
    else:
        pdf.ln(1.5)


def rule(pdf):
    pdf.ln(1)
    pdf.set_draw_color(*RULE)
    pdf.set_line_width(0.3)
    y = pdf.get_y()
    pdf.line(MARGIN, y, PAGE_W - MARGIN, y)
    pdf.ln(3)


def code_block(pdf, lines):
    pdf.set_font('dvm', '', 9.5)
    h = 5.0
    pdf.set_fill_color(*CODE_BG)
    pdf.set_text_color(*INK)
    for line in lines:
        pdf.set_x(MARGIN)
        pdf.cell(TEXT_W, h, '   ' + line, fill=True)
        pdf.ln(h)
    pdf.ln(2.5)


def table(pdf, rows):
    """rows[0] is the header. Column widths come from the widest cell, then
    are scaled to the text width — the last column takes the slack, which
    is where the prose always is."""
    pdf.set_font('dv', '', 9.5)
    n = max(len(r) for r in rows)
    rows = [r + [''] * (n - len(r)) for r in rows]
    want = []
    for c in range(n):
        w = max(pdf.get_string_width(re.sub(r'[*`]', '', r[c])) for r in rows)
        want.append(min(w + 6, TEXT_W * 0.62))
    total = sum(want)
    if total < TEXT_W:
        want[-1] += TEXT_W - total
    else:
        want = [w * TEXT_W / total for w in want]

    line_h = 4.6
    for i, row in enumerate(rows):
        wrapped = []
        for c, cell in enumerate(row):
            pdf.set_font('dv', 'B' if i == 0 else '', 9.5)
            wrapped.append(wrap(pdf, re.sub(r'\*\*|`|\*', '', cell),
                                want[c] - 4))
        height = max(len(w) for w in wrapped) * line_h + 2
        if pdf.get_y() + height > pdf.h - MARGIN - 8:
            pdf.add_page()
        top = pdf.get_y()
        if i == 0:
            pdf.set_fill_color(238, 238, 234)
            pdf.rect(MARGIN, top, TEXT_W, height, 'F')
        x = MARGIN
        for c in range(n):
            pdf.set_font('dv', 'B' if i == 0 else '', 9.5)
            pdf.set_text_color(*INK)
            for j, line in enumerate(wrapped[c]):
                pdf.set_xy(x + 2, top + 1 + j * line_h)
                pdf.cell(want[c] - 4, line_h, line)
            x += want[c]
        pdf.set_draw_color(*RULE)
        pdf.line(MARGIN, top + height, PAGE_W - MARGIN, top + height)
        pdf.set_y(top + height)
    pdf.ln(3)


def wrap(pdf, text, width):
    out, line = [], ''
    for word in text.split():
        trial = (line + ' ' + word).strip()
        if line and pdf.get_string_width(trial) > width:
            out.append(line)
            line = word
        else:
            line = trial
    out.append(line)
    return out or ['']


def cover_page(pdf, path):
    """The sleeve, bled to the page width and centred. A manual that opens
    on its own cover is the whole reason the cover exists."""
    pdf.add_page()
    pdf.plain_pages = 1
    pdf.set_fill_color(14, 12, 18)
    pdf.rect(0, 0, PAGE_W, pdf.h, 'F')
    from PIL import Image
    im = Image.open(path)
    h = PAGE_W * im.height / im.width
    pdf.image(path, 0, (pdf.h - h) / 2, PAGE_W, h)


def render(src, dst, cover=None):
    lines = open(src, encoding='utf-8').read().split('\n')
    title = lines[0].lstrip('# ').strip()
    pdf = Manual(title)
    if cover and os.path.exists(cover):
        cover_page(pdf, cover)
    pdf.add_page()

    i = 0
    while i < len(lines):
        line = lines[i]
        stripped = line.strip()

        if not stripped:
            i += 1
            continue

        if stripped.startswith('#'):
            level = len(stripped) - len(stripped.lstrip('#'))
            heading(pdf, level, stripped[level:].strip())
            i += 1
            continue

        if set(stripped) == {'-'} and len(stripped) >= 3:
            rule(pdf)
            i += 1
            continue

        if line.startswith('    '):                     # indented code
            block = []
            while i < len(lines) and (lines[i].startswith('    ')
                                      or not lines[i].strip()):
                if not lines[i].strip() and not (
                        i + 1 < len(lines) and lines[i + 1].startswith('    ')):
                    break
                block.append(lines[i][4:])
                i += 1
            code_block(pdf, block)
            continue

        if stripped.startswith('|'):                    # table
            rows = []
            while i < len(lines) and lines[i].strip().startswith('|'):
                cells = [c.strip() for c in lines[i].strip().strip('|').split('|')]
                if not all(set(c) <= set('-: ') and c for c in cells):
                    rows.append(cells)
                i += 1
            table(pdf, rows)
            continue

        if stripped.startswith('- '):                   # bullets
            while i < len(lines) and lines[i].strip().startswith('- '):
                text = lines[i].strip()[2:]
                i += 1
                while i < len(lines) and lines[i].startswith('  ') \
                        and not lines[i].strip().startswith('- '):
                    text += ' ' + lines[i].strip()
                    i += 1
                pdf.set_text_color(*INK)
                pdf.set_font('dv', '', 10)
                pdf.set_xy(MARGIN + 2, pdf.get_y())
                pdf.cell(4, 5, '•')
                pdf.set_x(MARGIN + 6)
                x0 = pdf.get_x()
                pdf.set_x(x0)
                write_runs(pdf, text, 10.0, 5.0)
                pdf.ln(1)
            pdf.ln(1)
            continue

        block = [stripped]                              # a paragraph
        i += 1
        while i < len(lines) and lines[i].strip() \
                and not lines[i].strip().startswith(('#', '|', '- ')) \
                and not lines[i].startswith('    ') \
                and set(lines[i].strip()) != {'-'}:
            block.append(lines[i].strip())
            i += 1
        para(pdf, ' '.join(block))

    os.makedirs(os.path.dirname(dst) or '.', exist_ok=True)
    pdf.output(dst)
    print('%s -> %s (%d pages)' % (src, dst, pdf.page_no()))


if __name__ == '__main__':
    if len(sys.argv) not in (3, 4):
        raise SystemExit('usage: mkmanual.py IN.md OUT.pdf [COVER.png]')
    render(*sys.argv[1:])
