"""Traced lettering vs Inter setting vs board, in the lockup board's frame."""
import io
import json
import re
import numpy as np
from PIL import Image
from scipy import ndimage as ndi
import resvg_py

K = 0.25
W, H = 2172, 724
ref = np.array(Image.open('ref-lockup.png')).astype(float) / 255
ink = ref[..., 3] > 0.5
ink[:, :740] = False
lab, n = ndi.label(ink)
sizes = ndi.sum(ink, lab, range(1, n + 1))
ink = np.isin(lab, 1 + np.where(sizes > 100)[0])      # letters only, no speckle
zones = {'word': (slice(0, 486), slice(740, None)), 'tag': (slice(486, None), slice(740, None))}


def render(paths):
    body = ''.join(f'<path d="{d}"/>' for d in paths)
    svg = (f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" '
           f'viewBox="0 0 {W * K} {H * K}">{body}</svg>')
    return np.array(Image.open(io.BytesIO(bytes(resvg_py.svg_to_bytes(svg_string=svg, width=W, height=H)))))[..., 3] > 127


def edge(m):
    return m ^ ndi.binary_erosion(m)


def metrics(m, zone):
    r, o = ink[zones[zone]], m[zones[zone]]
    er, eo = edge(r), edge(o)
    dr = ndi.distance_transform_edt(~er)
    do = ndi.distance_transform_edt(~eo)
    d1, d2 = dr[eo], do[er]
    xr, xo = np.where(r.any(0))[0], np.where(o.any(0))[0]
    yr, yo = np.where(r.any(1))[0], np.where(o.any(1))[0]
    return {'iou': float((r & o).sum() / (r | o).sum()),
            'boundary_mean_px': float((d1.mean() + d2.mean()) / 2),
            'boundary_p99_px': float(max(np.percentile(d1, 99), np.percentile(d2, 99))),
            'boundary_max_px': float(max(d1.max(), d2.max())),
            'ink_width_px_board_vs_svg': [int(xr.max() - xr.min() + 1), int(xo.max() - xo.min() + 1)],
            'ink_height_px_board_vs_svg': [int(yr.max() - yr.min() + 1), int(yo.max() - yo.min() + 1)],
            'left_right_px_board': [int(xr.min()), int(xr.max())], 'left_right_px_svg': [int(xo.min()), int(xo.max())]}


if __name__ == '__main__':
    lt = json.load(open('lettering.json'))
    res = {}
    for zone in ('word', 'tag'):
        res['traced_' + zone] = metrics(render([g['d'] for g in lt[zone]]), zone)
    # the Inter setting that c6fbe99 shipped, from the committed lockup
    svg = open('out-c6fbe99/pliwee-lockup.svg').read()
    lk = json.load(open('lockup.json'))
    for zone, gid in (('word', 'wordmark'), ('tag', 'tagline')):
        grp = svg.split(f'<g id="{gid}"')[1].split('</g>')[0]
        tx, ty = map(float, re.search(r'translate\(([-\d.]+) ([-\d.]+)\)', grp).groups())
        paths = re.findall(r'<path d="([^"]+)"', grp)
        body = ''.join(f'<path d="{d}"/>' for d in paths)
        s2 = (f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W * K} {H * K}">'
              f'<g>{body}</g></svg>')
        m = np.array(Image.open(io.BytesIO(bytes(resvg_py.svg_to_bytes(svg_string=s2, width=W, height=H)))))[..., 3] > 127
        res['inter_c6fbe99_' + zone] = metrics(m, zone)
    json.dump(res, open('metrics-lettering.json', 'w'), indent=1)
    for k, v in res.items():
        print(k, {kk: (round(vv, 4) if isinstance(vv, float) else vv) for kk, vv in v.items()})
