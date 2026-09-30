"""Wave 0 review 2 -- comparison sheets and metrics for wordmark, lockup and
the mark variants. Validation artefacts, not product assets.

usage: make_sheets2.py <masters dir> <previous lockup svg> <sheet dir>
"""
import io
import json
import os
import re
import sys
import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage as ndi
from skimage import color
import resvg_py

MD, PREV, DEST = sys.argv[1:4]
K = 0.25
FONT = os.path.join(os.environ['INTER_DIR'], 'extras/ttf/Inter-Medium.ttf')
f_title = ImageFont.truetype(FONT, 30)
f_lab = ImageFont.truetype(FONT, 22)
BG, INK = (247, 249, 252), (11, 16, 32)
STATUS = 'STATUS: READY FOR FINAL HUMAN BRAND APPROVAL — validation artefact, not a product asset.'

ref = np.array(Image.open('ref-lockup.png').convert('RGBA'))
Wp, Hp = ref.shape[1], ref.shape[0]
ra = ref[..., 3] > 127
lab_, n = ndi.label(ra)
sizes = ndi.sum(ra, lab_, range(1, n + 1))
ra = np.isin(lab_, 1 + np.where(sizes > 100)[0])   # drop the board's faint speckle
lk = json.load(open('lockup.json'))
ZONES = {'mark': (slice(None), slice(0, 740)), 'wordmark': (slice(0, 486), slice(740, None)),
         'tagline': (slice(486, None), slice(740, None))}


def in_board_frame(svg, dx, dy):
    """Render a lockup-coordinate SVG in the board's pixel frame."""
    s = re.sub(r'viewBox="[^"]*"', f'viewBox="{dx} {dy} {Wp * K} {Hp * K}"', svg, count=1)
    s = re.sub(r'width="\d+" height="\d+"', f'width="{Wp}" height="{Hp}"', s, count=1)
    return np.array(Image.open(io.BytesIO(bytes(resvg_py.svg_to_bytes(svg_string=s, width=Wp, height=Hp)))).convert('RGBA'))


new = in_board_frame(open(f'{MD}/pliwee-lockup.svg').read(), *lk['offset_units'])
prev_svg = open(PREV).read()
# the previous lockup's own offset: its viewBox origin was ink-min - 4 in board units
prev_off = json.load(open('lockup-c6fbe99.json'))['offset_units']
prev = in_board_frame(prev_svg, *prev_off)
oa, pa = new[..., 3] > 127, prev[..., 3] > 127


def edge(m):
    return m ^ ndi.binary_erosion(m)


def zone_metrics(o, z):
    r, s = ra[z], o[z]
    er, es = edge(r), edge(s)
    d1 = ndi.distance_transform_edt(~er)[es]
    d2 = ndi.distance_transform_edt(~es)[er]
    xr, xs = np.where(r.any(0))[0], np.where(s.any(0))[0]
    yr, ys = np.where(r.any(1))[0], np.where(s.any(1))[0]
    return {'iou': float((r & s).sum() / (r | s).sum()),
            'boundary_mean_px': float((d1.mean() + d2.mean()) / 2),
            'boundary_p99_px': float(max(np.percentile(d1, 99), np.percentile(d2, 99))),
            'boundary_max_px': float(max(d1.max(), d2.max())),
            'width_px': [int(np.ptp(xr) + 1), int(np.ptp(xs) + 1)],
            'height_px': [int(np.ptp(yr) + 1), int(np.ptp(ys) + 1)],
            'left_top_px': [[int(xr.min()), int(yr.min())], [int(xs.min()), int(ys.min())]]}


metrics = {'new': {k: zone_metrics(oa, z) for k, z in ZONES.items()},
           'c6fbe99': {k: zone_metrics(pa, z) for k, z in ZONES.items()}}
z = ZONES['mark']
both = ra[z] & oa[z]
de = color.deltaE_ciede2000(color.rgb2lab(ref[z][..., :3] / 255), color.rgb2lab(new[z][..., :3] / 255))
metrics['new']['mark']['deltaE2000_median'] = float(np.median(de[both]))
metrics['new']['mark']['deltaE2000_p95'] = float(np.percentile(de[both], 95))
# colour of the lettering, board vs SVG (interior pixels)
for zone, zz in (('wordmark', ZONES['wordmark']), ('tagline', ZONES['tagline'])):
    core = ndi.binary_erosion(ra[zz] & oa[zz], iterations=2)
    metrics['new'][zone]['deltaE2000_median'] = float(np.median(color.deltaE_ciede2000(
        color.rgb2lab(ref[zz][..., :3][core] / 255), color.rgb2lab(new[zz][..., :3][core] / 255))))
json.dump(metrics, open('metrics-review2.json', 'w'), indent=1)


def on_white(rgba):
    a = rgba[..., 3:4] / 255.0
    return (rgba[..., :3] * a + 255 * (1 - a)).astype(np.uint8)


def diffmap(r, o):
    d = np.full(r.shape + (3,), 255, np.uint8)
    d[r & o] = [150, 156, 170]
    d[r & ~o] = [230, 0, 60]
    d[o & ~r] = [0, 110, 255]
    return d


def edge_overlay(img, r):
    g = np.repeat((img.mean(2, keepdims=True) * 0.45 + 255 * 0.55).astype(np.uint8), 3, 2)
    g[ndi.binary_dilation(edge(r))] = [230, 0, 60]
    return g


def tile(img, label, width):
    im = Image.fromarray(img)
    im = im.resize((width, int(width * im.height / im.width)), Image.LANCZOS)
    c = Image.new('RGB', (im.width, im.height + 40), BG)
    c.paste(im, (0, 40))
    ImageDraw.Draw(c).text((4, 6), label, font=f_lab, fill=INK)
    return c


def sheet(rows, title, footer, path):
    pad = 24
    w = max(sum(p.width for p in r) + pad * (len(r) + 1) for r in rows)
    h = 70 + sum(max(p.height for p in r) + pad for r in rows) + 36 * len(footer) + pad
    s = Image.new('RGB', (w, h), BG)
    d = ImageDraw.Draw(s)
    d.text((pad, 20), title, font=f_title, fill=INK)
    y = 70
    for r in rows:
        x = pad
        for p in r:
            s.paste(p, (x, y)); x += p.width + pad
        y += max(p.height for p in r) + pad
    for line in footer:
        d.text((pad, y), line, font=f_lab, fill=INK); y += 36
    s.save(path, optimize=True)


def fmt(m):
    return (f'IoU {m["iou"]:.4f} · boundary mean {m["boundary_mean_px"]:.2f} px, p99 {m["boundary_p99_px"]:.1f}, '
            f'max {m["boundary_max_px"]:.2f} · width {m["width_px"][0]}→{m["width_px"][1]} px, '
            f'height {m["height_px"][0]}→{m["height_px"][1]} px')


# ---- wordmark --------------------------------------------------------------
y0, y1, x0, x1 = 150, 486, 760, 2060
crop = lambda a: a[y0:y1, x0:x1]
rw, nw, pw = on_white(crop(ref)), on_white(crop(new)), on_white(crop(prev))
r_m, n_m, p_m = crop(ra), crop(oa), crop(pa)
TW = 1300
blend = ((rw.astype(float) + nw.astype(float)) / 2).astype(np.uint8)
m, pm = metrics['new']['wordmark'], metrics['c6fbe99']['wordmark']
sheet([[tile(rw, 'A  reference board — "Pliwee"', TW)], [tile(nw, 'B  new pliwee-wordmark.svg (resvg, board frame)', TW)],
       [tile(blend, 'C  A/B 50 % blend', TW)], [tile(edge_overlay(nw, r_m), 'D  board edges (red) on B', TW)],
       [tile(diffmap(r_m, n_m), 'E  difference: grey both · red board only · blue SVG only', TW)],
       [tile(diffmap(r_m, p_m), 'F  for contrast: c6fbe99 (Inter 900, rejected) against the board', TW)]],
      'Pliwee wordmark — board lettering reconstruction vs. board',
      ['New:      ' + fmt(m),
       f'          fill #030D25 (Pliwee Wordmark Ink, board-derived) vs board ink: dE2000 median {m["deltaE2000_median"]:.2f}',
       'c6fbe99:  ' + fmt(pm), STATUS], f'{DEST}/pliwee-wordmark-comparison.png')

# ---- lockup ----------------------------------------------------------------
rl, nl = on_white(ref), on_white(new)
TL = 1400
blend = ((rl.astype(float) + nl.astype(float)) / 2).astype(np.uint8)
mm, mw, mt = metrics['new']['mark'], metrics['new']['wordmark'], metrics['new']['tagline']
pm = metrics['c6fbe99']
sheet([[tile(rl, 'A  reference board (horizontal lockup)', TL)], [tile(nl, 'B  new pliwee-lockup.svg (resvg)', TL)],
       [tile(blend, 'C  A/B 50 % blend', TL)], [tile(edge_overlay(nl, ra), 'D  board edges (red) on B', TL)],
       [tile(diffmap(ra, oa), 'E  difference: grey both · red board only · blue SVG only', TL)]],
      'Pliwee lockup — reconstruction vs. board',
      [f'Ink IoU  mark {mm["iou"]:.4f} (c6fbe99 {pm["mark"]["iou"]:.4f}) · wordmark {mw["iou"]:.4f} ({pm["wordmark"]["iou"]:.4f}) · '
       f'tagline {mt["iou"]:.4f} ({pm["tagline"]["iou"]:.4f})',
       f'Mark: approved pliwee-mark.svg geometry, placed by fit (dE2000 median {mm["deltaE2000_median"]:.2f}).',
       'Its residual is the board drawing its lockup mark slightly differently from the symbol board (ruled: symbol board wins).',
       f'Lettering: traced from this board. Wordmark {mw["boundary_mean_px"]:.2f} px / tagline {mt["boundary_mean_px"]:.2f} px mean boundary distance.',
       STATUS], f'{DEST}/pliwee-lockup-comparison.png')

# ---- variants --------------------------------------------------------------
def rv(path, colour=None, w=552, h=510):
    s = open(path).read()
    if colour:
        s = s.replace('color="#0B1020"', f'color="{colour}"')
    return Image.open(io.BytesIO(bytes(resvg_py.svg_to_bytes(svg_string=s, width=w, height=h)))).convert('RGBA')


cells = [('colour · Surface', f'{MD}/pliwee-mark.svg', None, '#F7F9FC'),
         ('colour · Dark', f'{MD}/pliwee-mark.svg', None, '#0B1020'),
         ('mono · Dark ink', f'{MD}/pliwee-mark-mono.svg', '#0B1020', '#F7F9FC'),
         ('mono · Surface ink', f'{MD}/pliwee-mark-mono.svg', '#F7F9FC', '#0B1020'),
         ('mono · Primary Blue ink', f'{MD}/pliwee-mark-mono.svg', '#4F6BFF', '#FFFFFF'),
         ('tonal · Dark', f'{MD}/pliwee-mark-tonal.svg', '#0B1020', '#F7F9FC'),
         ('tonal · Surface', f'{MD}/pliwee-mark-tonal.svg', '#F7F9FC', '#0B1020')]
tiles = []
for label, path, colour, bg in cells:
    im = rv(path, colour, 368, 340)
    t = Image.new('RGBA', (368, 340), bg); t.alpha_composite(im)
    c = Image.new('RGB', (368, 380), BG); c.paste(t.convert('RGB'), (0, 40))
    ImageDraw.Draw(c).text((4, 6), label, font=f_lab, fill=INK)
    tiles.append(c)
sheet([tiles[:4], tiles[4:]], 'Flow Monogram — colour, mono (single ink) and tonal cuts',
      ['colour = pliwee-mark.svg (board-derived gradient) · mono = pliwee-mark-mono.svg (currentColor, one ink)',
       'tonal = pliwee-mark-tonal.svg (currentColor with face tones; optional, not a platform requirement)', STATUS],
      f'{DEST}/pliwee-mark-variants.png')
print(json.dumps(metrics, indent=1))
