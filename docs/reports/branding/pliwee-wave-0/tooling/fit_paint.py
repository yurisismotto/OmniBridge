"""Fit each face's paint to the reference pixels: one linear gradient plus up to
K elliptical radial overlays (colour c, opacity a0 at the centre falling
linearly to 0 at the ellipse edge -- exactly what an SVG two-stop
radialGradient with gradientTransform renders).

Geometry is not touched here: overlays paint the same face paths.
"""
import json
import numpy as np
from PIL import Image
from scipy import ndimage as ndi
from scipy.optimize import least_squares
from skimage import color

m = json.load(open('mark.json'))
S, TX, TY = m['S'], m['TX'], m['TY']
ref = np.array(Image.open('ref-mark.png')).astype(float) / 255
rgb = ref[..., :3]
lbl = np.load('lbl.npy')
STEP = 3
FACES = {'inner': (2, 3, 0), 'loop': (1, 6, 4), 'tail': (4, 5, 2), 'sweep': (3, 6, 3)}


def samples(v):
    mk = ndi.binary_erosion(lbl == v, iterations=3)
    ys, xs = np.where(mk)
    keep = (ys % STEP == 0) & (xs % STEP == 0)
    ys, xs = ys[keep], xs[keep]
    return np.stack([(xs + 0.5) * S + TX, (ys + 0.5) * S + TY], 1), rgb[ys, xs]


def linear_basis(p, g, n):
    d = np.array([g['x2'] - g['x1'], g['y2'] - g['y1']])
    t = ((p - [g['x1'], g['y1']]) @ d) / (d @ d)
    t = np.clip(t, 0, 1)
    knots = np.linspace(0, 1, n)
    return np.clip(1 - np.abs(t[:, None] - knots[None]) * (n - 1), 0, 1)


def overlay_alpha(p, q):
    cx, cy, lrx, lry, rot, a0 = q[:6]
    rx, ry = np.exp(lrx), np.exp(lry)
    c, s = np.cos(rot), np.sin(rot)
    dx, dy = p[:, 0] - cx, p[:, 1] - cy
    u = (c * dx + s * dy) / rx
    w = (-s * dx + c * dy) / ry
    r = np.sqrt(u * u + w * w)
    return (1 / (1 + np.exp(-a0))) * np.clip(1 - r, 0, 1)


def compose(p, B, stops, overlays):
    out = B @ stops
    for q in overlays:
        a = overlay_alpha(p, q)[:, None]
        col = 1 / (1 + np.exp(-np.array(q[6:9])))
        out = out * (1 - a) + col * a
    return out


def solve_stops(p, B, overlays, target):
    # out = base*P + K, where P = prod(1-a_i) and K the accumulated overlay colour
    P = np.ones((len(p), 1))
    K = np.zeros((len(p), 3))
    for q in overlays:
        a = overlay_alpha(p, q)[:, None]
        col = 1 / (1 + np.exp(-np.array(q[6:9])))
        K = K * (1 - a) + col * a
        P = P * (1 - a)
    stops, *_ = np.linalg.lstsq(B * P, target - K, rcond=None)
    return np.clip(stops, 0, 1)


def fit_face(name):
    v, n, K = FACES[name]
    p, target = samples(v)
    g = m['grads'][name]
    B = linear_basis(p, g, n)
    overlays = []
    stops = solve_stops(p, B, overlays, target)
    base_err = np.sqrt(np.mean((compose(p, B, stops, overlays) - target) ** 2))
    for k in range(K):
        # multi-start: seeds at the worst-fitting areas and on a coarse grid
        res = np.linalg.norm(compose(p, B, stops, overlays) - target, axis=1)
        order = np.argsort(res)[::-1]
        rng = np.random.default_rng(k)
        cand = [p[order[:max(50, len(res) // 50)]].mean(0)]
        cand += [p[i] for i in rng.choice(order[:len(order) // 4], 5, replace=False)]
        cand += [p[i] for i in rng.choice(len(p), 4, replace=False)]

        def resid(q):
            ov = overlays + [q]
            st = solve_stops(p, B, ov, target)
            return (compose(p, B, st, ov) - target).ravel()
        prev = np.sqrt(np.mean((compose(p, B, stops, overlays) - target) ** 2))
        best = None
        for (cx, cy) in cand:
            near = np.linalg.norm(p - [cx, cy], axis=1) < 20
            mean_col = np.clip(target[near].mean(0) if near.any() else target.mean(0), 0.02, 0.98)
            for rad in (25, 60):
                q0 = [cx, cy, np.log(rad), np.log(rad * 0.7), 0.0, 0.0,
                      *np.log(mean_col / (1 - mean_col))]
                sol = least_squares(resid, q0, max_nfev=300, x_scale='jac')
                e = np.sqrt(np.mean(sol.fun ** 2))
                if best is None or e < best[0]:
                    best = (e, list(sol.x))
        trial = overlays + [best[1]]
        st = solve_stops(p, B, trial, target)
        err = best[0]
        if err < prev * 0.96:
            overlays, stops = trial, st
    err = np.sqrt(np.mean((compose(p, B, stops, overlays) - target) ** 2))
    print(name, 'rmse/255', round(base_err * 255, 1), '->', round(err * 255, 1), 'overlays', len(overlays))
    ov_out = []
    for q in overlays:
        cx, cy, lrx, lry, rot, a0 = q[:6]
        col = 1 / (1 + np.exp(-np.array(q[6:9])))
        ov_out.append({'cx': cx, 'cy': cy, 'rx': float(np.exp(lrx)), 'ry': float(np.exp(lry)),
                       'rot_deg': float(np.degrees(rot)), 'opacity': float(1 / (1 + np.exp(-a0))),
                       'color': '#%02X%02X%02X' % tuple(int(round(c * 255)) for c in col)})
    g['stops'] = [(float(o), '#%02X%02X%02X' % tuple(int(round(c * 255)) for c in stops[i]))
                  for i, o in enumerate(np.linspace(0, 1, n))]
    g['overlays'] = ov_out
    g['rmse_fitted'] = float(err)


for f in FACES:
    fit_face(f)
json.dump(m, open('mark.json', 'w'), indent=1)
