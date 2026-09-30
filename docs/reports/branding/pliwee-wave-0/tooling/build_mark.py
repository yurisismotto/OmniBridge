"""Controlled vector reconstruction of the Pliwee Flow Monogram.

Every coordinate comes from the owner-supplied reference PNG:
  * the silhouette is the reference's own alpha channel (sub-pixel, via 2x
    bicubic upsampling of alpha, threshold 0.5);
  * the internal edges between ribbon faces are the reference's own colour
    edges (CIELAB Sobel gradient, watershed from one hand-placed seed set per
    face — seeds pick *which* face, the image decides *where* the edge is);
  * every contour is traced by potrace; nothing is drawn by hand;
  * every gradient is least-squares fitted to the reference pixels of the face
    it paints.
"""
import json
import numpy as np
from PIL import Image
from scipy import ndimage as ndi
from skimage import color
import potrace

U = 2            # tracing supersample
S = 0.25         # reference px -> viewBox units
MARGIN = 2.0     # viewBox units around the ink

ref = np.array(Image.open('ref-mark.png')).astype(float) / 255
alpha = ref[..., 3]
rgb = ref[..., :3]
lbl = np.load('lbl.npy')
sil = np.load('sil.npy')
A, B, D, E = 1, 2, 3, 4

# --- adjacency (paint order sanity) ----------------------------------------
def adjacent(p, q):
    return bool((ndi.binary_dilation(lbl == p, iterations=2) & (lbl == q)).any())
adj = {f'{x}-{y}': adjacent(i, j) for (x, i), (y, j) in
       [(('A', A), ('B', B)), (('A', A), ('D', D)), (('A', A), ('E', E)),
        (('B', B), ('D', D)), (('B', B), ('E', E)), (('D', D), ('E', E))]}

# --- masks, supersampled ----------------------------------------------------
def up_alpha():
    im = Image.fromarray((alpha * 255).astype(np.uint8))
    im = im.resize((im.width * U, im.height * U), Image.BICUBIC)
    m = np.array(im) > 127
    # drop the reference's faint speckle (alpha noise off the ribbon)
    lab_, n = ndi.label(m)
    sizes = ndi.sum(m, lab_, range(1, n + 1))
    keep = np.zeros(n + 1, bool)
    keep[1:] = sizes > 5000
    return keep[lab_]

def up_region(mask, grow_outside):
    f = Image.fromarray((mask * 255).astype(np.uint8))
    f = f.resize((f.width * U, f.height * U), Image.BICUBIC)
    f = ndi.gaussian_filter(np.array(f).astype(float) / 255, 1.2 * U)
    m = f > 0.5
    if grow_outside is not None:
        # grow only across the silhouette boundary: the clip-path draws that
        # edge, so every layer's own outer contour is hidden under it
        m = m | (ndi.binary_dilation(m, iterations=6 * U) & ~grow_outside)
    return m

SIL = up_alpha()
layers = {
    'silhouette': SIL,
    'loop': up_region((lbl == A) | (lbl == E) | (lbl == D), SIL),
    'tail': up_region((lbl == E) | (lbl == D), SIL),
    'sweep': up_region(lbl == D, SIL),
}

# --- tracing ----------------------------------------------------------------
ys, xs = np.where(sil)
x0, y0 = xs.min(), ys.min()
W = (xs.max() + 1 - x0) * S + 2 * MARGIN
H = (ys.max() + 1 - y0) * S + 2 * MARGIN
W, H = np.ceil(W), np.ceil(H)
TX = (W - (xs.max() + 1 - x0) * S) / 2 - x0 * S
TY = (H - (ys.max() + 1 - y0) * S) / 2 - y0 * S

def pt(p):
    return f"{p.x / U * S + TX:.2f},{p.y / U * S + TY:.2f}"

def trace(mask):
    path = potrace.Bitmap(~mask).trace(turdsize=200, alphamax=1.0, opticurve=True, opttolerance=0.2)
    out = []
    for curve in path:
        d = [f'M{pt(curve.start_point)}']
        for s in curve.segments:
            if s.is_corner:
                d.append(f'L{pt(s.c)}L{pt(s.end_point)}')
            else:
                d.append(f'C{pt(s.c1)} {pt(s.c2)} {pt(s.end_point)}')
        d.append('Z')
        out.append(''.join(d))
    return ''.join(out), len(path.curves)

paths, subpaths = {}, {}
for name, m in layers.items():
    paths[name], subpaths[name] = trace(m)

# --- gradient fitting -------------------------------------------------------
YY, XX = np.mgrid[0:alpha.shape[0], 0:alpha.shape[1]]
def to_units(x, y):
    return x * S + TX, y * S + TY

def fit_gradient(region, nstops=5):
    m = ndi.binary_erosion(region, iterations=3)
    px = np.stack([XX[m] + 0.5, YY[m] + 0.5], 1)
    col = rgb[m]
    best = None
    for deg in range(0, 180, 2):
        th = np.radians(deg)
        u = np.array([np.cos(th), np.sin(th)])
        t = px @ u
        lo, hi = t.min(), t.max()
        tn = (t - lo) / (hi - lo)
        knots = np.linspace(0, 1, nstops)
        # hat basis
        Bm = np.clip(1 - np.abs(tn[:, None] - knots[None, :]) * (nstops - 1), 0, 1)
        coef, *_ = np.linalg.lstsq(Bm, col, rcond=None)
        res = np.mean((Bm @ coef - col) ** 2)
        if best is None or res < best[0]:
            best = (res, deg, u, lo, hi, np.clip(coef, 0, 1))
    res, deg, u, lo, hi, coef = best
    p1 = to_units(*(u * lo)); p2 = to_units(*(u * hi))
    # the gradient vector through the origin-projected line: x = u*t
    stops = [(float(k), '#%02X%02X%02X' % tuple(int(round(c * 255)) for c in coef[i]))
             for i, k in enumerate(np.linspace(0, 1, len(coef)))]
    return {'deg': deg, 'x1': p1[0], 'y1': p1[1], 'x2': p2[0], 'y2': p2[1],
            'stops': stops, 'rmse': float(np.sqrt(res))}

grads = {
    'inner': fit_gradient(lbl == B, 3),
    'loop': fit_gradient(lbl == A, 6),
    'tail': fit_gradient(lbl == E, 5),
    'sweep': fit_gradient(lbl == D, 6),
}

# mono tones: each face's mean CIELAB L*, relative to the brightest face
L = color.rgb2lab(rgb)[..., 0]
Lmean = {k: float(L[lbl == v].mean()) for k, v in [('inner', B), ('loop', A), ('tail', E), ('sweep', D)]}
top = max(Lmean.values())
tones = {k: round(v / top, 2) for k, v in Lmean.items()}

json.dump({'viewBox': [0, 0, W, H], 'S': S, 'TX': TX, 'TY': TY, 'paths': paths,
           'subpaths': subpaths, 'grads': grads, 'tones': tones, 'Lmean': Lmean,
           'adjacency': adj}, open('mark.json', 'w'), indent=1)
print('viewBox', W, H, 'TX', TX, 'TY', TY)
print('adjacency', adj)
print('subpaths', subpaths, {k: len(v) for k, v in paths.items()})
for k, g in grads.items():
    print(k, g['deg'], 'rmse', round(g['rmse'] * 255, 1), g['stops'])
print('L*', Lmean, 'tones', tones)
