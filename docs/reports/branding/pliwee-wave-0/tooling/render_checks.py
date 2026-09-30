"""Render each master with two independent renderers (resvg, librsvg via
ImageMagick), check transparency, and build the mono light/dark sheet."""
import io
import re
import subprocess
import sys
import numpy as np
from PIL import Image
import resvg_py

OUT = sys.argv[1]
report = []


def resvg(svg, w, h):
    return Image.open(io.BytesIO(bytes(resvg_py.svg_to_bytes(svg_string=svg, width=w, height=h)))).convert('RGBA')


def rsvg(path, w):
    png = subprocess.run(['magick', '-background', 'none', '-density', '300', f'rsvg:{path}',
                          '-resize', f'{w}x', 'png:-'], capture_output=True, check=True).stdout
    return Image.open(io.BytesIO(png)).convert('RGBA')


for name in ['pliwee-mark.svg', 'pliwee-mark-mono.svg', 'pliwee-wordmark.svg', 'pliwee-lockup.svg']:
    path = f'{OUT}/{name}'
    svg = open(path).read()
    vb = [float(v) for v in re.search(r'viewBox="([^"]+)"', svg).group(1).split()]
    w = 2048 if vb[2] >= vb[3] else int(2048 * vb[2] / vb[3])
    h = int(round(w * vb[3] / vb[2]))
    a = resvg(svg, w, h)
    a.save(f'render-{name[:-4]}.png')
    b = rsvg(path, w)
    arr_a = np.array(a).astype(float)
    arr_b = np.array(b.resize(a.size)).astype(float)
    alpha = arr_a[..., 3]
    corners = [alpha[0, 0], alpha[0, -1], alpha[-1, 0], alpha[-1, -1]]
    transparent = (alpha == 0).mean()
    both = (arr_a[..., 3] > 250) & (arr_b[..., 3] > 250)
    diff = np.abs(arr_a[..., :3] - arr_b[..., :3])[both].mean() if both.any() else -1
    a_iou = ((arr_a[..., 3] > 127) & (arr_b[..., 3] > 127)).sum() / max(1, ((arr_a[..., 3] > 127) | (arr_b[..., 3] > 127)).sum())
    report.append(f'{name}: viewBox {vb} render {w}x{h}; corner alpha {corners}; '
                  f'transparent px {transparent:.3f}; resvg-vs-librsvg alpha IoU {a_iou:.4f}, '
                  f'mean |dRGB| on opaque {diff:.2f}')

# mono on light and dark: currentColor overridden per background
mono = open(f'{OUT}/pliwee-mark-mono.svg').read()
tiles = []
for bg, fg in [('#F7F9FC', '#0B1020'), ('#0B1020', '#F7F9FC'), ('#FFFFFF', '#4F6BFF')]:
    svg = mono.replace('color="#0B1020"', f'color="{fg}"')
    im = resvg(svg, 552, 510)
    tile = Image.new('RGBA', im.size, bg)
    tile.alpha_composite(im)
    tiles.append(tile)
colour = resvg(open(f'{OUT}/pliwee-mark.svg').read(), 552, 510)
for bg in ['#F7F9FC', '#0B1020']:
    t = Image.new('RGBA', colour.size, bg); t.alpha_composite(colour); tiles.insert(0 if bg == '#F7F9FC' else 1, t)
sheet = Image.new('RGBA', (552 * len(tiles) + 16 * (len(tiles) + 1), 510 + 32), '#CBD3E1')
for i, t in enumerate(tiles):
    sheet.paste(t, (16 + i * (552 + 16), 16))
sheet.save('mark-variants.png')
print('\n'.join(report))
