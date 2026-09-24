"""Trace the board's own lettering: "Pliwee" and "One flow. Any device.".

Custom brand lettering (owner decision, Wave 0 review 2): the outlines come
from the horizontal lockup board's alpha channel, not from a font.
  * letters = connected components of alpha > 0.5 (the i's dot joins its stem);
  * each letter is traced by potrace on 4x bicubic-supersampled alpha,
    threshold 0.5 -- the same edge definition as the Flow Monogram;
  * anything that is not one of those components (the board's faint
    generation speckle, alpha < 0.5) is dropped: that is the only cleanup.
Coordinates: lockup-board pixels x 0.25, not yet shifted into the lockup.
"""
import json
import numpy as np
from PIL import Image
from scipy import ndimage as ndi
import potrace

U = 4
K = 0.25
ref = np.array(Image.open('ref-lockup.png')).astype(float) / 255
alpha = ref[..., 3]
ink = alpha > 0.5
TEXT_X0, SPLIT_Y = 740, 486


def letters(zone, glyph_names):
    m = ink.copy()
    m[:, :TEXT_X0] = False
    if zone == 'word':
        m[SPLIT_Y:] = False
    else:
        m[:SPLIT_Y] = False
    lab, n = ndi.label(m)
    objs = ndi.find_objects(lab)
    comps = sorted(range(1, n + 1), key=lambda i: objs[i - 1][1].start)
    # a component whose x-range lies inside the previous one's and sits above
    # it is an i's dot: it joins that letter
    groups = []
    for i in comps:
        xs, ys = objs[i - 1][1], objs[i - 1][0]
        if groups:
            pi = groups[-1][-1]
            pxs, pys = objs[pi - 1][1], objs[pi - 1][0]
            overlap = min(xs.stop, pxs.stop) - max(xs.start, pxs.start)
            if overlap > 0.6 * min(xs.stop - xs.start, pxs.stop - pxs.start) and \
                    (ys.stop <= pys.start or pys.stop <= ys.start):
                groups[-1].append(i)
                continue
        groups.append([i])
    assert len(groups) == len(glyph_names), (zone, len(groups), glyph_names)
    return lab, groups


# supersampled alpha, once
import os
SIGMA = float(os.environ.get('SIGMA', '0.6'))      # board px
OPTTOL = float(os.environ.get('OPTTOL', '0.4'))
up = Image.fromarray((alpha * 255).astype(np.uint8))
up = np.array(up.resize((up.width * U, up.height * U), Image.BICUBIC)).astype(float) / 255
# symmetric smoothing of the edge: a 0.5 threshold of a symmetric blur leaves
# straight edges where they are and only removes sub-pixel raster noise
up = ndi.gaussian_filter(up, SIGMA * U) > 0.5


def trace_group(lab, ids):
    own = np.isin(lab, ids)
    own = ndi.binary_dilation(own, iterations=2)
    own_up = np.kron(own, np.ones((U, U), bool))
    m = up & own_up
    ys, xs = np.where(own)
    y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
    crop = m[y0 * U:y1 * U, x0 * U:x1 * U]
    path = potrace.Bitmap(~np.pad(crop, 2)).trace(
        turdsize=4 * U * U, alphamax=1.0, opticurve=True, opttolerance=OPTTOL)

    def pt(p):
        return f'{(p.x - 2) / U * K + x0 * K:.2f},{(p.y - 2) / U * K + y0 * K:.2f}'
    d = []
    for curve in path:
        d.append(f'M{pt(curve.start_point)}')
        for s in curve.segments:
            if s.is_corner:
                d.append(f'L{pt(s.c)}L{pt(s.end_point)}')
            else:
                d.append(f'C{pt(s.c1)} {pt(s.c2)} {pt(s.end_point)}')
        d.append('Z')
    # the drop-shadow of the padding frame: potrace returns the frame when
    # the bitmap is inverted; ~ on a padded array keeps the border white
    bbox = [x0 * K, y0 * K, x1 * K, y1 * K]
    return ''.join(d), len(path.curves), bbox


out = {}
for zone, names in [('word', list('Pliwee')), ('tag', [c for c in 'One flow. Any device.' if c != ' '])]:
    lab, groups = letters(zone, names)
    glyphs = []
    for name, ids in zip(names, groups):
        d, nsub, bbox = trace_group(lab, ids)
        glyphs.append({'char': name, 'd': d, 'subpaths': nsub, 'bbox': bbox})
    out[zone] = glyphs
    print(zone, [(g['char'], g['subpaths']) for g in glyphs])
json.dump(out, open(os.environ.get('OUT', 'lettering.json'), 'w'), indent=1)
