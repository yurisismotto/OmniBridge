"""Emit pliwee-wordmark.svg and pliwee-lockup.svg.

Coordinates: board-lockup pixels x 0.25 (the same density the mark master uses
for its own board), then shifted so the ink sits inside a 0-origin viewBox.
The lockup copies the mark master's <defs> verbatim and places `#mark`.
"""
import os
import io
import json
import re
import sys
import numpy as np
from PIL import Image
from scipy import ndimage as ndi
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.pens.boundsPen import BoundsPen
import resvg_py

OUT = sys.argv[1]
K = 0.25
MARGIN = 4.0
VAR = os.path.join(os.environ['INTER_DIR'], 'InterVariable.ttf')
wm = json.load(open('wordmark.json'))
mk = json.load(open('mark.json'))
# Dark token (board measured #030D25, dE2000 3.5); tagline: board measured, no token within dE 6.5
WORD_FILL = '#0B1020'
TAG_FILL = wm['tag']['colour_measured']

ref = np.array(Image.open('ref-lockup.png')).astype(float) / 255
ink = ndi.binary_opening(ref[..., 3] > 0.5)
lab, n = ndi.label(ink)
sizes = ndi.sum(ink, lab, range(1, n + 1))
# the mark: everything left of the text column
mark_px = ink.copy(); mark_px[:, 740:] = False
ys, xs = np.where(mark_px)
lx0, lx1, ly0, ly1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1

# the standalone board's silhouette bbox, in its own pixels
sil = np.load('sil.npy')
sy, sx = np.where(sil)
sx0, sx1, sy0, sy1 = sx.min(), sx.max() + 1, sy.min(), sy.max() + 1
kx = (lx1 - lx0) / (sx1 - sx0)
ky = (ly1 - ly0) / (sy1 - sy0)
kk = (kx + ky) / 2
print(f'mark scale in lockup: kx {kx:.4f} ky {ky:.4f} (diff {abs(kx - ky) / kk * 100:.2f}%)')

W, H = int(mk['viewBox'][2]), int(mk['viewBox'][3])
S, TX, TY = mk['S'], mk['TX'], mk['TY']
# mark unit (0,0) is standalone px (-TX/S, -TY/S)
mx_px = lx0 + (-TX / S - sx0) * kk
my_px = ly0 + (-TY / S - sy0) * kk
mw_px, mh_px = W / S * kk, H / S * kk


def font(opsz, wght):
    return instancer.instantiateVariableFont(TTFont(VAR), {'opsz': opsz, 'wght': wght})


BOUNDS = {'word': [], 'tag': []}


def gpath(f, g, x_px, base_px, s_px, kind='word'):
    gs = f.getGlyphSet()
    bp = BoundsPen(gs)
    gs[g].draw(TransformPen(bp, (s_px * K, 0, 0, -s_px * K, x_px * K, base_px * K)))
    if bp.bounds:
        BOUNDS[kind].append(bp.bounds)
    pen = SVGPathPen(gs, ntos=lambda v: ('%.2f' % v).rstrip('0').rstrip('.'))
    # font units -> board px -> lockup units (x K); shift applied later by a
    # group translate so that the wordmark file can reuse the same bytes
    gs[g].draw(TransformPen(pen, (s_px * K, 0, 0, -s_px * K, x_px * K, base_px * K)))
    return pen.getCommands()


fw = font(wm['word']['opsz'], wm['word']['wght'])
word_paths = [gpath(fw, g, x, wm['word']['baseline'], wm['word']['scale'])
              for g, x in zip(wm['word']['glyphs'], wm['word']['xs'])]
ft = font(wm['tag']['opsz'], wm['tag']['wght'])
cmap = ft.getBestCmap()
TAG = 'One flow. Any device.'
bp = BoundsPen(ft.getGlyphSet()); ft.getGlyphSet()[cmap[ord('O')]].draw(bp)
tag_paths = []
for c, xg in zip(TAG, wm['tag']['xs']):
    if c != ' ':
        tag_paths.append(gpath(ft, cmap[ord(c)], xg, wm['tag']['baseline'], wm['tag']['scale'], 'tag'))


def bbox_of(kind):
    b = np.array(BOUNDS[kind])
    return b[:, 0].min(), b[:, 1].min(), b[:, 2].max(), b[:, 3].max()


# overall lockup bbox in units (control points bound the outline conservatively)
wb, tb = bbox_of('word'), bbox_of('tag')
# mark ink bbox in units
m_ink = (lx0 * K, ly0 * K, lx1 * K, ly1 * K)
x0 = min(wb[0], tb[0], m_ink[0]) - MARGIN
y0 = min(wb[1], tb[1], m_ink[1]) - MARGIN
x1 = max(wb[2], tb[2], m_ink[2]) + MARGIN
y1 = max(wb[3], tb[3], m_ink[3]) + MARGIN
LW, LH = int(np.ceil(x1 - x0)), int(np.ceil(y1 - y0))
dx, dy = -x0, -y0

mark_svg = open(f'{OUT}/pliwee-mark.svg').read()
defs = mark_svg[mark_svg.index('<defs>'):mark_svg.index('</defs>') + len('</defs>')]


def group(gid, paths, fill, tx, ty):
    body = ''.join(f'<path d="{d}"/>' for d in paths)
    return f'<g id="{gid}" fill="{fill}" transform="translate({tx:.2f} {ty:.2f})">{body}</g>'


label = 'Pliwee — One flow. Any device.'
lockup = (
    f'<svg xmlns="http://www.w3.org/2000/svg" width="{LW}" height="{LH}" viewBox="0 0 {LW} {LH}" '
    f'role="img" aria-label="{label}"><title>{label}</title>\n{defs}\n'
    f'<use href="#mark" x="{mx_px * K + dx:.2f}" y="{my_px * K + dy:.2f}" '
    f'width="{mw_px * K:.2f}" height="{mh_px * K:.2f}"/>\n'
    f'{group("wordmark", word_paths, WORD_FILL, dx, dy)}\n'
    f'{group("tagline", tag_paths, TAG_FILL, dx, dy)}\n</svg>\n')
open(f'{OUT}/pliwee-lockup.svg', 'w').write(lockup)

WW, WH = int(np.ceil(wb[2] - wb[0] + 2 * MARGIN)), int(np.ceil(wb[3] - wb[1] + 2 * MARGIN))
wordmark = (
    f'<svg xmlns="http://www.w3.org/2000/svg" width="{WW}" height="{WH}" viewBox="0 0 {WW} {WH}" '
    f'role="img" aria-label="Pliwee"><title>Pliwee</title>\n'
    f'{group("wordmark", word_paths, WORD_FILL, MARGIN - wb[0], MARGIN - wb[1])}\n</svg>\n')
open(f'{OUT}/pliwee-wordmark.svg', 'w').write(wordmark)

json.dump({'lockup_viewBox': [0, 0, LW, LH], 'wordmark_viewBox': [0, 0, WW, WH],
           'offset_units': [dx, dy], 'mark_k': kk, 'kx': kx, 'ky': ky,
           'mark_use': [mx_px * K + dx, my_px * K + dy, mw_px * K, mh_px * K]},
          open('lockup.json', 'w'), indent=1)
print('lockup', LW, LH, 'wordmark', WW, WH)
