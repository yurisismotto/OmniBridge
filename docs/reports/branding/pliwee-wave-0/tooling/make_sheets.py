"""Human-review comparison sheets. Validation artefacts, not product assets."""
import os
import json
import sys
import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage as ndi
from skimage import segmentation

DEST = sys.argv[1]
FONT = os.path.join(os.environ['INTER_DIR'], 'extras/ttf/Inter-Medium.ttf')
f_title = ImageFont.truetype(FONT, 30)
f_lab = ImageFont.truetype(FONT, 22)
BG = (247, 249, 252)
INK = (11, 16, 32)


def on_white(rgba):
    a = rgba[..., 3:4] / 255.0
    return (rgba[..., :3] * a + 255 * (1 - a)).astype(np.uint8)


def panel(img, label, size):
    im = Image.fromarray(img).resize((size, size), Image.LANCZOS) if img.shape[0] == img.shape[1] else Image.fromarray(img)
    canvas = Image.new('RGB', (im.width, im.height + 40), BG)
    canvas.paste(im, (0, 40))
    ImageDraw.Draw(canvas).text((4, 6), label, font=f_lab, fill=INK)
    return canvas


def sheet(rows, title, footer):
    pad = 24
    w = max(sum(p.width for p in r) + pad * (len(r) + 1) for r in rows)
    h = 70 + sum(max(p.height for p in r) + pad for r in rows) + 40 * len(footer) + pad
    s = Image.new('RGB', (w, h), BG)
    d = ImageDraw.Draw(s)
    d.text((pad, 20), title, font=f_title, fill=INK)
    y = 70
    for r in rows:
        x = pad
        for p in r:
            s.paste(p, (x, y))
            x += p.width + pad
        y += max(p.height for p in r) + pad
    for line in footer:
        d.text((pad, y), line, font=f_lab, fill=INK)
        y += 40
    return s


# ---- symbol ----------------------------------------------------------------
ref = np.array(Image.open('ref-mark.png').convert('RGBA'))
svg = np.array(Image.open('render-ref-frame.png').convert('RGBA'))
lbl = np.load('lbl.npy')
refw, svgw = on_white(ref), on_white(svg)
blend = ((refw.astype(float) + svgw.astype(float)) / 2).astype(np.uint8)
# reference edges (silhouette + face boundaries) over the render, in grey
grey = np.repeat((svgw.mean(2, keepdims=True) * 0.55 + 255 * 0.45).astype(np.uint8), 3, 2)
edges = segmentation.find_boundaries(lbl, mode='thick')
edges = ndi.binary_dilation(edges, iterations=1)
grey[edges] = [230, 0, 60]
heat = np.array(Image.open('diff-heat.png').convert('RGB'))
metrics = json.load(open('metrics.json'))
S = 520
row1 = [panel(refw, 'A  reference board (symbol)', S), panel(svgw, 'B  pliwee-mark.svg (resvg)', S),
        panel(blend, 'C  A/B 50 % blend', S), panel(grey, 'D  reference edges (red) on B', S),
        panel(heat, 'E  colour dE2000 (red = 20+)', S)]
# 1:1 detail crops: left crossing, upper-right fold, tail tip
crops = [((170, 640, 470, 940), 'left crossing'), ((830, 400, 1130, 700), 'upper-right fold'),
         ((800, 900, 1100, 1200), 'tail tip')]
row2 = []
for (x0, y0, x1, y1), name in crops:
    for src, tag in ((refw, 'ref'), (svgw, 'svg')):
        row2.append(panel(src[y0:y1, x0:x1], f'{name} 1:1 {tag}', 300))
m = metrics
footer = [
    f'Silhouette IoU {m["silhouette_iou"]:.4f} · boundary mean {m["boundary_px_mean"]:.2f} px, p99 {m["boundary_px_p99"]:.1f} px, max {m["boundary_px_max"]:.2f} px (board px, 1254 frame)',
    f'Colour dE2000 median {m["deltaE2000_median"]:.2f}, p95 {m["deltaE2000_p95"]:.2f} · per face: ' +
    ', '.join(f'{k} {v:.2f}' for k, v in m['deltaE2000_median_per_face'].items()),
    'STATUS: AWAITING HUMAN BRAND APPROVAL — validation artefact, not a product asset.',
]
sheet([row1, row2], 'Pliwee Flow Monogram — reconstruction vs. board', footer).save(f'{DEST}/pliwee-mark-comparison.png', optimize=True)

# ---- lockup ----------------------------------------------------------------
lref = np.array(Image.open('ref-lockup.png').convert('RGBA'))
lsvg = np.array(Image.open('render-lockup-ref-frame.png').convert('RGBA'))
ra = lref[..., 3] > 127
oa = lsvg[..., 3] > 127
diff = np.full(ra.shape + (3,), 255, np.uint8)
diff[ra & oa] = [150, 156, 170]
diff[ra & ~oa] = [230, 0, 60]
diff[oa & ~ra] = [0, 110, 255]
W = 1400
def wide(img, label):
    im = Image.fromarray(img).resize((W, int(W * img.shape[0] / img.shape[1])), Image.LANCZOS)
    c = Image.new('RGB', (im.width, im.height + 40), BG); c.paste(im, (0, 40))
    ImageDraw.Draw(c).text((4, 6), label, font=f_lab, fill=INK)
    return c
lm = json.load(open('metrics-lockup.json'))
footer = [
    f'Ink IoU — mark {lm["mark_iou"]:.4f} · wordmark {lm["wordmark_iou"]:.4f} · tagline {lm["tagline_iou"]:.4f} · mark dE2000 median {lm["mark_deltaE2000_median"]:.2f}',
    'Diff: grey = both, red = board only, blue = SVG only. Lettering is genuine Inter outlines; the board letters are wider (see report §6).',
    'STATUS: AWAITING HUMAN BRAND APPROVAL — validation artefact, not a product asset.',
]
sheet([[wide(on_white(lref), 'A  reference board (lockup)')], [wide(on_white(lsvg), 'B  pliwee-lockup.svg (resvg)')],
       [wide(diff, 'C  ink difference')]], 'Pliwee lockup — reconstruction vs. board', footer).save(
    f'{DEST}/pliwee-lockup-comparison.png', optimize=True)

# ---- variants --------------------------------------------------------------
v = Image.open('mark-variants.png').convert('RGB')
c = Image.new('RGB', (v.width, v.height + 110), BG)
c.paste(v, (0, 60))
d = ImageDraw.Draw(c)
d.text((16, 14), 'pliwee-mark.svg on Surface / Dark · pliwee-mark-mono.svg as Dark, Surface and Primary Blue currentColor', font=f_lab, fill=INK)
d.text((16, v.height + 70), 'STATUS: AWAITING HUMAN BRAND APPROVAL — validation artefact, not a product asset.', font=f_lab, fill=INK)
c.save(f'{DEST}/pliwee-mark-variants.png', optimize=True)
print('sheets written')
