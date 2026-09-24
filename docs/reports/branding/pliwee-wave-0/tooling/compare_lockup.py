import io
import json
import re
import numpy as np
from PIL import Image
from scipy import ndimage as ndi
from skimage import color
import resvg_py

lk = json.load(open('lockup.json'))
K = 0.25
dx, dy = lk['offset_units']
svg = open('out/pliwee-lockup.svg').read()
Wp, Hp = 2172, 724
framed = re.sub(r'viewBox="[^"]*"', f'viewBox="{dx} {dy} {Wp * K} {Hp * K}"', svg, count=1)
framed = re.sub(r'width="\d+" height="\d+"', f'width="{Wp}" height="{Hp}"', framed, count=1)
out = np.array(Image.open(io.BytesIO(bytes(resvg_py.svg_to_bytes(svg_string=framed, width=Wp, height=Hp)))).convert('RGBA')).astype(float) / 255
Image.fromarray((out * 255).astype(np.uint8)).save('render-lockup-ref-frame.png')
ref = np.array(Image.open('ref-lockup.png')).astype(float) / 255
ra = ndi.binary_opening(ref[..., 3] > 0.5)
oa = out[..., 3] > 0.5
wmj = json.load(open('wordmark.json'))
split_y = (wmj['word_bbox'][3] + wmj['tag_bbox'][1]) // 2
zones = {'mark': (slice(None), slice(0, 740)),
         'wordmark': (slice(0, split_y), slice(740, None)),
         'tagline': (slice(split_y, None), slice(740, None))}
m = {}
for k, z in zones.items():
    r, o = ra[z], oa[z]
    m[k + '_iou'] = float((r & o).sum() / (r | o).sum())
z = zones['mark']
both = ra[z] & oa[z]
de = color.deltaE_ciede2000(color.rgb2lab(ref[z][..., :3]), color.rgb2lab(out[z][..., :3]))
m['mark_deltaE2000_median'] = float(np.median(de[both]))
m['mark_deltaE2000_p95'] = float(np.percentile(de[both], 95))
m['mark_scale_kx_ky'] = [lk['kx'], lk['ky']]
json.dump(m, open('metrics-lockup.json', 'w'), indent=1)
print(json.dumps(m, indent=1))
