"""Tagline: per-glyph x positions fitted to the board, for a few Inter instances.
Renders only the tagline band, so each trial is cheap."""
import io
import json
import numpy as np
from PIL import Image
import resvg_py
exec(open('fit_wordmark.py').read().split("results = {}")[0])

X0, Y0 = tx.min() - 30, ty.min() - 20
BW, BH = tx.max() - X0 + 60, ty.max() - Y0 + 40
tag_crop = tag[Y0:Y0 + BH, X0:X0 + BW]


def render_band(paths):
    body = ''.join(f'<path d="{d}"/>' for d in paths)
    svg = (f'<svg xmlns="http://www.w3.org/2000/svg" width="{BW}" height="{BH}" '
           f'viewBox="{X0} {Y0} {BW} {BH}">{body}</svg>')
    png = bytes(resvg_py.svg_to_bytes(svg_string=svg, width=int(BW), height=int(BH)))
    return np.array(Image.open(io.BytesIO(png)))[..., 3] > 127


def fit(opsz, wght):
    f = instance(opsz, wght)
    names = tag_glyphs(f)
    Ob = glyph_bounds(f, names[0])
    cO = comps_t[0]
    best_all = None
    for s_mult in (0.985, 1.0, 1.015):
        s = (cO[3] - cO[2]) / (Ob[3] - Ob[1]) * s_mult
        base = cO[3] + Ob[1] * s
        x = tx.min() - Ob[0] * s
        xs = []
        for g in names:
            xs.append(x)
            x += f['hmtx'][g][0] * s
        idx = [i for i, c in enumerate(TAG) if c != ' ']
        # stretch to the board's line width first (tracking), then per glyph
        paths_of = lambda xs_: [glyph_path(f, names[i], xs_[i], base, s) for i in idx]
        for _ in range(2):
            for i in idx:
                best = None
                for dx in np.arange(-24, 24.1, 1.5):
                    trial = xs[:]
                    trial[i] += dx
                    if i == idx[0] and _ == 0:
                        pass
                    sc = iou(render_band(paths_of(trial)), tag_crop)
                    if best is None or sc > best[0]:
                        best = (sc, dx)
                xs[i] += best[1]
                # glyphs to the right follow, so the next search starts near
                for j in range(i + 1, len(xs)):
                    xs[j] += best[1]
        sc = iou(render_band(paths_of(xs)), tag_crop)
        if best_all is None or sc > best_all[0]:
            best_all = (sc, s, base, xs)
    return best_all


res = {}
for inst in [(14, 450), (14, 500), (24, 450), (24, 500), (24, 550), (32, 500)]:
    res[inst] = fit(*inst)
    print(inst, 'IoU', round(res[inst][0], 4))
b = max(res, key=lambda k: res[k][0])
print('best', b, res[b][0])
wm = json.load(open('wordmark.json'))
wm['tag'] = {'opsz': b[0], 'wght': b[1], 'iou': res[b][0], 'scale': res[b][1],
             'baseline': res[b][2], 'xs': res[b][3], 'colour_measured': wm['tag']['colour_measured']}
json.dump(wm, open('wordmark.json', 'w'), indent=1)
