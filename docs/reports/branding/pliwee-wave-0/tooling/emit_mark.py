"""Emit pliwee-mark.svg and pliwee-mark-mono.svg from mark.json.

The two files are generated from ONE template and differ only in the root
<use> target and the default colour: the geometry (the <path id=...> elements
in <defs>) is literally the same bytes in both.
"""
import json
import sys

m = json.load(open('mark.json'))
W, H = int(m['viewBox'][2]), int(m['viewBox'][3])
P, G, T = m['paths'], m['grads'], m['tones']


def grad(gid, g):
    stops = ''.join(f'<stop offset="{o:g}" stop-color="{c}"/>' for o, c in g['stops'])
    return (f'<linearGradient id="{gid}" x1="{g["x1"]:.2f}" y1="{g["y1"]:.2f}" '
            f'x2="{g["x2"]:.2f}" y2="{g["y2"]:.2f}" gradientUnits="userSpaceOnUse">'
            f'{stops}</linearGradient>')


def overlay_grads(face):
    out = []
    for i, o in enumerate(G[face].get('overlays', [])):
        out.append(
            f'<radialGradient id="paint-{face}-{i + 1}" cx="0" cy="0" r="1" gradientUnits="userSpaceOnUse" '
            f'gradientTransform="translate({o["cx"]:.2f} {o["cy"]:.2f}) rotate({o["rot_deg"]:.1f}) '
            f'scale({o["rx"]:.2f} {o["ry"]:.2f})">'
            f'<stop offset="0" stop-color="{o["color"]}" stop-opacity="{o["opacity"]:.2f}"/>'
            f'<stop offset="1" stop-color="{o["color"]}" stop-opacity="0"/></radialGradient>')
    return out


def overlay_uses(face, href):
    return [f'<use href="#{href}" fill="url(#paint-{face}-{i + 1})"/>'
            for i in range(len(G[face].get('overlays', [])))]


def defs():
    return '\n'.join([
        '<defs>',
        # --- geometry: defined once, painted twice ---------------------------
        f'<path id="silhouette" d="{P["silhouette"]}"/>',
        f'<path id="face-loop" d="{P["loop"]}"/>',
        f'<path id="face-tail" d="{P["tail"]}"/>',
        f'<path id="face-sweep" d="{P["sweep"]}"/>',
        '<clipPath id="clip"><use href="#silhouette"/></clipPath>',
        # --- colour paint ------------------------------------------------------
        grad('paint-inner', G['inner']),
        grad('paint-loop', G['loop']),
        grad('paint-tail', G['tail']),
        grad('paint-sweep', G['sweep']),
        *overlay_grads('inner'), *overlay_grads('loop'),
        *overlay_grads('tail'), *overlay_grads('sweep'),
        # --- mono paint: each face keeps only its visible part, so a tone is
        #     never composited over another; pure white/black masks only ------
        '<mask id="only-inner" maskUnits="userSpaceOnUse" x="0" y="0" '
        f'width="{W}" height="{H}"><use href="#silhouette" fill="#FFFFFF"/>'
        '<use href="#face-loop" fill="#000000"/></mask>',
        '<mask id="only-loop" maskUnits="userSpaceOnUse" x="0" y="0" '
        f'width="{W}" height="{H}"><use href="#face-loop" fill="#FFFFFF"/>'
        '<use href="#face-tail" fill="#000000"/></mask>',
        '<mask id="only-tail" maskUnits="userSpaceOnUse" x="0" y="0" '
        f'width="{W}" height="{H}"><use href="#face-tail" fill="#FFFFFF"/>'
        '<use href="#face-sweep" fill="#000000"/></mask>',
        # --- the two cuts ------------------------------------------------------
        f'<symbol id="mark" viewBox="0 0 {W} {H}">',
        '<use href="#silhouette" fill="url(#paint-inner)"/>',
        *overlay_uses('inner', 'silhouette'),
        '<g clip-path="url(#clip)">',
        '<use href="#face-loop" fill="url(#paint-loop)"/>',
        *overlay_uses('loop', 'face-loop'),
        '<use href="#face-tail" fill="url(#paint-tail)"/>',
        *overlay_uses('tail', 'face-tail'),
        '<use href="#face-sweep" fill="url(#paint-sweep)"/>',
        *overlay_uses('sweep', 'face-sweep'),
        '</g>',
        '</symbol>',
        f'<symbol id="markMono" viewBox="0 0 {W} {H}">',
        '<g clip-path="url(#clip)" fill="currentColor">',
        f'<use href="#silhouette" fill-opacity="{T["inner"]}" mask="url(#only-inner)"/>',
        f'<use href="#face-loop" fill-opacity="{T["loop"]}" mask="url(#only-loop)"/>',
        f'<use href="#face-tail" fill-opacity="{T["tail"]}" mask="url(#only-tail)"/>',
        f'<use href="#face-sweep" fill-opacity="{T["sweep"]}"/>',
        '</g>',
        '</symbol>',
        '</defs>',
    ])


def document(which, extra_root='', title='Pliwee'):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" '
            f'viewBox="0 0 {W} {H}"{extra_root} role="img" aria-label="{title}">'
            f'<title>{title}</title>\n{defs()}\n<use href="#{which}" width="{W}" height="{H}"/></svg>\n')


out = sys.argv[1]
open(f'{out}/pliwee-mark.svg', 'w').write(document('mark'))
open(f'{out}/pliwee-mark-mono.svg', 'w').write(document('markMono', ' color="#0B1020"'))
print('written')
