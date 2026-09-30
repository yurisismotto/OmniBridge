"""Emit pliwee-wordmark.svg and pliwee-lockup.svg (Wave 0 review 2).

Lettering: the board's own "Pliwee" and "One flow. Any device.", traced by
trace_lettering.py (custom brand lettering; typographic origin Inter).
Mark: the approved pliwee-mark.svg geometry and paint, copied verbatim, placed
where the horizontal-lockup board places its mark (scale and offset fitted to
that board's mark silhouette). The board's own lockup-mark outline is NOT used.
Coordinates: lockup-board pixels x 0.25, shifted into a 0-origin viewBox.
"""
import io
import json
import re
import sys
import numpy as np
from PIL import Image
from scipy import ndimage as ndi
import resvg_py

OUT = sys.argv[1]
K = 0.25
MARGIN = 4.0
WORD_FILL = '#0B1020'   # Dark token; the board measures #030D25 (dE2000 3.5)
TAG_FILL = '#314871'    # measured on the board; approved as lockup-specific
lt = json.load(open('lettering.json'))
mk = json.load(open('mark.json'))
W, H = int(mk['viewBox'][2]), int(mk['viewBox'][3])
S, TX, TY = mk['S'], mk['TX'], mk['TY']

ref = np.array(Image.open('ref-lockup.png')).astype(float) / 255
Wp, Hp = ref.shape[1], ref.shape[0]
ink = ndi.binary_opening(ref[..., 3] > 0.5)
board_mark = ink.copy(); board_mark[:, 740:] = False
ys, xs = np.where(board_mark)
lx0, lx1, ly0, ly1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
sil = np.load('sil.npy')
sy, sx = np.where(sil)
sx0, sx1, sy0, sy1 = sx.min(), sx.max() + 1, sy.min(), sy.max() + 1

mark_svg = open(f'{OUT}/pliwee-mark.svg').read()
defs = mark_svg[mark_svg.index('<defs>'):mark_svg.index('</defs>') + len('</defs>')]


def place(k, ox, oy):
    x = lx0 + ox + (-TX / S - sx0) * k
    y = ly0 + oy + (-TY / S - sy0) * k
    return x, y, W / S * k, H / S * k


def mark_mask(k, ox, oy):
    x, y, w, h = place(k, ox, oy)
    svg = (f'<svg xmlns="http://www.w3.org/2000/svg" width="{Wp}" height="{Hp}" viewBox="0 0 {Wp} {Hp}">'
           f'{defs}<use href="#mark" x="{x:.3f}" y="{y:.3f}" width="{w:.3f}" height="{h:.3f}"/></svg>')
    a = np.array(Image.open(io.BytesIO(bytes(resvg_py.svg_to_bytes(svg_string=svg, width=Wp, height=Hp)))))[..., 3]
    return a > 127


def iou(m):
    r, o = board_mark[:, :740], m[:, :740]
    return (r & o).sum() / (r | o).sum()


k0 = ((lx1 - lx0) / (sx1 - sx0) + (ly1 - ly0) / (sy1 - sy0)) / 2
best = (iou(mark_mask(k0, 0, 0)), k0, 0.0, 0.0)
start = best
for step_k, step_o in ((0.004, 2.0), (0.001, 0.5)):
    improved = True
    while improved:
        improved = False
        _, k, ox, oy = best
        for dk, ddx, ddy in [(step_k, 0, 0), (-step_k, 0, 0), (0, step_o, 0), (0, -step_o, 0), (0, 0, step_o), (0, 0, -step_o)]:
            c = (iou(mark_mask(k + dk, ox + ddx, oy + ddy)), k + dk, ox + ddx, oy + ddy)
            if c[0] > best[0] + 1e-5:
                best, improved = c, True
print(f'mark placement: ink-box fit IoU {start[0]:.4f} (k {start[1]:.4f}) -> refined {best[0]:.4f} '
      f'(k {best[1]:.4f}, offset {best[2]:+.1f},{best[3]:+.1f} px)')
mx, my, mw, mh = place(best[1], best[2], best[3])


def bbox(glyphs):
    nums = np.array([[float(a), float(b)] for g in glyphs for a, b in re.findall(r'(-?\d+\.\d+),(-?\d+\.\d+)', g['d'])])
    return nums[:, 0].min(), nums[:, 1].min(), nums[:, 0].max(), nums[:, 1].max()


wb, tb = bbox(lt['word']), bbox(lt['tag'])
m_ink = (lx0 * K, ly0 * K, lx1 * K, ly1 * K)
x0 = min(wb[0], tb[0], m_ink[0]) - MARGIN
y0 = min(wb[1], tb[1], m_ink[1]) - MARGIN
x1 = max(wb[2], tb[2], m_ink[2]) + MARGIN
y1 = max(wb[3], tb[3], m_ink[3]) + MARGIN
LW, LH = int(np.ceil(x1 - x0)), int(np.ceil(y1 - y0))
dx, dy = -x0, -y0


def group(gid, glyphs, fill, tx, ty):
    body = ''.join(f'<path d="{g["d"]}"/>' for g in glyphs)
    return f'<g id="{gid}" fill="{fill}" transform="translate({tx:.2f} {ty:.2f})">{body}</g>'


label = 'Pliwee — One flow. Any device.'
lockup = (
    f'<svg xmlns="http://www.w3.org/2000/svg" width="{LW}" height="{LH}" viewBox="0 0 {LW} {LH}" '
    f'role="img" aria-label="{label}"><title>{label}</title>\n{defs}\n'
    f'<use href="#mark" x="{mx * K + dx:.2f}" y="{my * K + dy:.2f}" width="{mw * K:.2f}" height="{mh * K:.2f}"/>\n'
    f'{group("wordmark", lt["word"], WORD_FILL, dx, dy)}\n'
    f'{group("tagline", lt["tag"], TAG_FILL, dx, dy)}\n</svg>\n')
open(f'{OUT}/pliwee-lockup.svg', 'w').write(lockup)

WW, WH = int(np.ceil(wb[2] - wb[0] + 2 * MARGIN)), int(np.ceil(wb[3] - wb[1] + 2 * MARGIN))
wordmark = (
    f'<svg xmlns="http://www.w3.org/2000/svg" width="{WW}" height="{WH}" viewBox="0 0 {WW} {WH}" '
    f'role="img" aria-label="Pliwee"><title>Pliwee</title>\n'
    f'{group("wordmark", lt["word"], WORD_FILL, MARGIN - wb[0], MARGIN - wb[1])}\n</svg>\n')
open(f'{OUT}/pliwee-wordmark.svg', 'w').write(wordmark)

json.dump({'lockup_viewBox': [0, 0, LW, LH], 'wordmark_viewBox': [0, 0, WW, WH],
           'offset_units': [dx, dy], 'wordmark_offset_units': [MARGIN - wb[0], MARGIN - wb[1]],
           'mark_k': best[1], 'mark_offset_px': [best[2], best[3]], 'mark_iou_fit': best[0],
           'mark_iou_boxfit': start[0], 'kx': (lx1 - lx0) / (sx1 - sx0), 'ky': (ly1 - ly0) / (sy1 - sy0),
           'mark_use': [mx * K + dx, my * K + dy, mw * K, mh * K]},
          open('lockup.json', 'w'), indent=1)
print('lockup', LW, LH, 'wordmark', WW, WH)
