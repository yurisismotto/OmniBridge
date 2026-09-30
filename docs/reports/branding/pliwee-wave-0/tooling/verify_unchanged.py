"""pliwee-mark.svg vs c6fbe99: same geometry, same paint, same pixels."""
import io
import re
import subprocess
import sys
import numpy as np
from PIL import Image
import resvg_py

old = open(sys.argv[1]).read()
new = open(sys.argv[2]).read()


def elements(s, tag):
    return re.findall(rf'<{tag}\b.*?</{tag}>' if tag in ('linearGradient', 'radialGradient', 'symbol', 'clipPath', 'mask')
                      else rf'<{tag} id="[^"]+" d="[^"]+"/>', s, re.S)


for tag in ('path', 'linearGradient', 'radialGradient', 'clipPath'):
    print(f'{tag}: {len(elements(old, tag))} -> {len(elements(new, tag))}, identical: {elements(old, tag) == elements(new, tag)}')
sym = lambda s, i: re.search(rf'<symbol id="{i}".*?</symbol>', s, re.S).group(0)
print('symbol #mark identical:', sym(old, 'mark') == sym(new, 'mark'))
print('removed from the colour file:', sorted(set(re.findall(r'<(mask|symbol) id="([^"]+)"', old)) - set(re.findall(r'<(mask|symbol) id="([^"]+)"', new))))
print('root <use>:', re.findall(r'<use href="#\w+" width[^>]*/></svg>', old), re.findall(r'<use href="#\w+" width[^>]*/></svg>', new))


def rv(svg, w, h):
    return np.array(Image.open(io.BytesIO(bytes(resvg_py.svg_to_bytes(svg_string=svg, width=w, height=h)))).convert('RGBA')).astype(int)


def rs(path, w):
    png = subprocess.run(['magick', '-background', 'none', '-density', '600', f'rsvg:{path}', '-resize', f'{w}x', 'png:-'],
                         capture_output=True, check=True).stdout
    return np.array(Image.open(io.BytesIO(png)).convert('RGBA')).astype(int)


for w, h in ((276, 255), (1104, 1020), (2208, 2040)):
    d = np.abs(rv(old, w, h) - rv(new, w, h))
    print(f'resvg {w}x{h}: max |diff| {d.max()}, differing px {(d.max(2) > 0).sum()}')
d = np.abs(rs(sys.argv[1], 1104) - rs(sys.argv[2], 1104))
print(f'librsvg 1104: max |diff| {d.max()}, differing px {(d.max(2) > 0).sum()}')
if len(sys.argv) > 4:
    d = np.abs(rv(open(sys.argv[3]).read(), 1104, 1020) - rv(open(sys.argv[4]).read(), 1104, 1020))
    print(f'old mono (tonal) vs new tonal, resvg 1104: max |diff| {d.max()}, differing px {(d.max(2) > 0).sum()}')
