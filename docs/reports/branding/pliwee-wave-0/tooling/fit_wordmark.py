"""Fit Inter to the board's wordmark and tagline, then outline it.

Nothing is drawn: every letter is an Inter glyph outline (OFL, v4.1), with
`cv05` (l with tail, glyph l.ss02) because the board's l has a tail. What is
fitted to the board:
  * the instance (opsz, wght) of InterVariable -- chosen by IoU against the
    board's text mask;
  * the scale -- from the board's cap height;
  * each wordmark glyph's x position -- so the board's visual kerning is kept;
  * the tagline's weight/opsz, scale, tracking and word spacing.
"""
import os
import io
import json
import itertools
import numpy as np
from PIL import Image
from scipy import ndimage as ndi
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.pens.boundsPen import BoundsPen
import resvg_py

VAR = os.path.join(os.environ['INTER_DIR'], 'InterVariable.ttf')
ref = np.array(Image.open('ref-lockup.png')).astype(float) / 255
alpha = ref[..., 3]
rgb = ref[..., :3]
Hh, Ww = alpha.shape
ink = alpha > 0.5
ink = ndi.binary_opening(ink)
TEXT_X0 = 740
text = ink.copy()
text[:, :TEXT_X0] = False
rows = np.where(text.any(1))[0]
occ = text.any(1)
# split into two text lines at the largest empty row gap
gaps = [(y, y2) for y, y2 in zip(rows[:-1], rows[1:]) if y2 - y > 1]
g0 = max(gaps, key=lambda g: g[1] - g[0])
word = text.copy(); word[g0[1]:] = False
tag = text.copy(); tag[:g0[1]] = False
wy = np.where(word.any(1))[0]; ty = np.where(tag.any(1))[0]
wx = np.where(word.any(0))[0]; tx = np.where(tag.any(0))[0]
print('word bbox x', wx.min(), wx.max(), 'y', wy.min(), wy.max())
print('tag  bbox x', tx.min(), tx.max(), 'y', ty.min(), ty.max())

# colours: median of fully-opaque interior pixels
def ink_colour(mk):
    core = ndi.binary_erosion(mk, iterations=2) & (alpha > 0.9)
    c = np.median(rgb[core], 0)
    return '#%02X%02X%02X' % tuple(int(round(v * 255)) for v in c)
word_col, tag_col = ink_colour(word), ink_colour(tag)
print('colours word', word_col, 'tag', tag_col)

# P: leftmost component of the word line -> cap height and baseline
lab, n = ndi.label(word)
objs = ndi.find_objects(lab)
comps = sorted([(o[1].start, o[1].stop, o[0].start, o[0].stop, i + 1) for i, o in enumerate(objs)])
P = comps[0]
cap_px = P[3] - P[2]
base_px = P[3]
print('P comp', P, 'cap px', cap_px)

# tagline: capital O and A give the cap height; baseline from 'O' bottom is an
# overshoot, so use 'A' (flat) -- find it as the component after "flow."
lab_t, nt = ndi.label(tag)
objs_t = ndi.find_objects(lab_t)
comps_t = sorted([(o[1].start, o[1].stop, o[0].start, o[0].stop) for o in objs_t])


_cache = {}
def instance(opsz, wght):
    key = (opsz, wght)
    if key not in _cache:
        f = TTFont(VAR)
        inst = instancer.instantiateVariableFont(f, {'opsz': opsz, 'wght': wght})
        _cache[key] = inst
    return _cache[key]


def glyph_path(font, gname, x, baseline, s):
    gs = font.getGlyphSet()
    pen = SVGPathPen(gs, ntos=lambda v: f'{v:.2f}'.rstrip('0').rstrip('.'))
    gs[gname].draw(TransformPen(pen, (s, 0, 0, -s, x, baseline)))
    return pen.getCommands()


def glyph_bounds(font, gname):
    gs = font.getGlyphSet()
    bp = BoundsPen(gs)
    gs[gname].draw(bp)
    return bp.bounds


def render(paths, w=Ww, h=Hh):
    body = ''.join(f'<path d="{d}"/>' for d in paths)
    svg = f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">{body}</svg>'
    png = bytes(resvg_py.svg_to_bytes(svg_string=svg, width=w, height=h))
    return np.array(Image.open(io.BytesIO(png)))[..., 3] > 127


def iou(a, b):
    return (a & b).sum() / max(1, (a | b).sum())


WORD = ['P', 'l.ss02', 'i', 'w', 'e', 'e']


def fit_word(opsz, wght):
    f = instance(opsz, wght)
    hmtx = f['hmtx']
    pb = glyph_bounds(f, 'P')
    s = cap_px / (pb[3] - pb[1])
    # start: natural advances, left edge of P aligned to the board's P
    x = P[0] - pb[0] * s
    xs = []
    for g in WORD:
        xs.append(x)
        x += hmtx[g][0] * s
    # per-glyph x refinement against the board, one glyph at a time
    band = np.zeros_like(word); band[wy.min() - 5:wy.max() + 5] = True
    for i, g in enumerate(WORD):
        best = None
        for dx in range(-40, 41, 2):
            trial = xs[:]
            trial[i] = xs[i] + dx
            m = render([glyph_path(f, WORD[j], trial[j], base_px, s) for j in range(len(WORD))])
            sc = iou(m, word)
            if best is None or sc > best[0]:
                best = (sc, dx)
        # fine
        for dx in np.arange(best[1] - 2, best[1] + 2.01, 0.5):
            trial = xs[:]
            trial[i] = xs[i] + dx
            m = render([glyph_path(f, WORD[j], trial[j], base_px, s) for j in range(len(WORD))])
            sc = iou(m, word)
            if sc > best[0]:
                best = (sc, dx)
        xs[i] += best[1]
    m = render([glyph_path(f, WORD[j], xs[j], base_px, s) for j in range(len(WORD))])
    return iou(m, word), s, xs


TAG = 'One flow. Any device.'


def tag_glyphs(font):
    cmap = font.getBestCmap()
    return [cmap[ord(c)] for c in TAG]


def fit_tag(opsz, wght):
    f = instance(opsz, wght)
    hmtx = f['hmtx']
    names = tag_glyphs(f)
    # cap height from 'A' (flat top? no -- apex); use 'E'-free: take 'n' x-height? use board 'l' of flow:
    # simplest robust scale: fit the full line's ink width and height jointly by search
    # anchor on the first glyph, O: its board height (with overshoot) against
    # Inter's O bounds (same overshoot) gives the scale and the baseline
    Ob = glyph_bounds(f, names[0])
    cO = comps_t[0]
    best = None
    for s_mult in np.linspace(0.97, 1.03, 7):
        s = (cO[3] - cO[2]) / (Ob[3] - Ob[1]) * s_mult
        base = cO[3] + Ob[1] * s
        for track in np.linspace(-20, 60, 17):
            x = tx.min() - glyph_bounds(f, names[0])[0] * s
            paths = []
            for c, g in zip(TAG, names):
                paths.append(glyph_path(f, g, x, base, s))
                x += hmtx[g][0] * s + track
            m = render(paths)
            sc = iou(m, tag)
            if best is None or sc > best[0]:
                best = (sc, s, base, track)
    return best


results = {}
print('--- wordmark instance search')
for opsz, wght in [(14, 900)]:
    sc, s, xs = fit_word(opsz, wght)
    results[(opsz, wght)] = (sc, s, xs)
    print(f'opsz {opsz} wght {wght}: IoU {sc:.4f}')
bw = max(results, key=lambda k: results[k][0])
print('best word', bw, results[bw][0])

print('--- tagline instance search')
tres = {}
for opsz, wght in itertools.product([14, 24, 32], [400, 450, 500, 550]):
    tres[(opsz, wght)] = fit_tag(opsz, wght)
    print(f'opsz {opsz} wght {wght}: IoU {tres[(opsz, wght)][0]:.4f} track {tres[(opsz, wght)][3]:.1f}')
bt = max(tres, key=lambda k: tres[k][0])
print('best tag', bt, tres[bt][0])

json.dump({
    'word': {'opsz': bw[0], 'wght': bw[1], 'iou': results[bw][0], 'scale': results[bw][1],
             'xs': results[bw][2], 'baseline': base_px, 'glyphs': WORD, 'colour_measured': word_col},
    'tag': {'opsz': bt[0], 'wght': bt[1], 'iou': tres[bt][0], 'scale': tres[bt][1],
            'baseline': tres[bt][2], 'tracking': tres[bt][3], 'x0': int(tx.min()),
            'colour_measured': tag_col},
    'word_bbox': [int(wx.min()), int(wy.min()), int(wx.max()), int(wy.max())],
    'tag_bbox': [int(tx.min()), int(ty.min()), int(tx.max()), int(ty.max())],
}, open('wordmark.json', 'w'), indent=1)
