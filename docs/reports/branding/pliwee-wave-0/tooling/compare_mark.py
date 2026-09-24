"""Render the reconstructed mark in the reference's pixel frame and measure it.

Outputs:
  render-ref-frame.png   the SVG rendered by resvg into the reference's 1254 px frame
  metrics.json           silhouette IoU, boundary distance, colour error (CIEDE2000)
  compare-*.png          side-by-side, overlay, difference heat map
"""
import json
import re
import sys
import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage as ndi
from skimage import color
import resvg_py

m = json.load(open('mark.json'))
svg = open(sys.argv[1]).read()
N = 1254
S, TX, TY = m['S'], m['TX'], m['TY']
# put the reference frame (0..1254 px) into the viewBox
framed = re.sub(r'viewBox="[^"]*"', f'viewBox="{TX} {TY} {N * S} {N * S}"', svg, count=1)
framed = re.sub(r'width="\d+" height="\d+"', f'width="{N}" height="{N}"', framed, count=1)
png = bytes(resvg_py.svg_to_bytes(svg_string=framed, width=N, height=N))
open('render-ref-frame.png', 'wb').write(png)
out = np.array(Image.open('render-ref-frame.png').convert('RGBA')).astype(float) / 255

ref = np.array(Image.open('ref-mark.png')).astype(float) / 255
ra, oa = ref[..., 3] > 0.5, out[..., 3] > 0.5
ra = ndi.binary_opening(ra, iterations=1)
lab_, n = ndi.label(ra)
sizes = ndi.sum(ra, lab_, range(1, n + 1))
ra = np.isin(lab_, 1 + np.where(sizes > 2000)[0])
iou = (ra & oa).sum() / (ra | oa).sum()
# symmetric boundary distance
def edge(mk):
    return mk ^ ndi.binary_erosion(mk)
dr = ndi.distance_transform_edt(~edge(ra))
do = ndi.distance_transform_edt(~edge(oa))
d1, d2 = dr[edge(oa)], do[edge(ra)]
both = ra & oa
lab_r = color.rgb2lab(ref[..., :3])
lab_o = color.rgb2lab(out[..., :3])
de = color.deltaE_ciede2000(lab_r, lab_o)
lbl = np.load('lbl.npy')
per_face = {k: float(np.median(de[(lbl == v) & both])) for k, v in
            [('inner', 2), ('loop', 1), ('tail', 4), ('sweep', 3)]}
metrics = {
    'silhouette_iou': float(iou),
    'boundary_px_mean': float((d1.mean() + d2.mean()) / 2),
    'boundary_px_p99': float(max(np.percentile(d1, 99), np.percentile(d2, 99))),
    'boundary_px_max': float(max(d1.max(), d2.max())),
    'deltaE2000_median': float(np.median(de[both])),
    'deltaE2000_p95': float(np.percentile(de[both], 95)),
    'deltaE2000_median_per_face': per_face,
    'ref_only_px': int((ra & ~oa).sum()),
    'svg_only_px': int((oa & ~ra).sum()),
}
json.dump(metrics, open('metrics.json', 'w'), indent=1)
print(json.dumps(metrics, indent=1))

# heat map of colour difference
heat = np.clip(de / 20, 0, 1)
hm = np.zeros((N, N, 3))
hm[..., 0] = heat
hm[..., 1] = 0.15 * (1 - heat)
hm[..., 2] = 0.15 * (1 - heat)
hm[~(ra | oa)] = 1
hm[ra ^ oa] = [1, 1, 0]
Image.fromarray((hm * 255).astype(np.uint8)).save('diff-heat.png')
